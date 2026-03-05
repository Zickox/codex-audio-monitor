import Foundation
import Observation

#if canImport(CodexAudioCore)
import CodexAudioCore
#endif

@MainActor
@Observable
final class CodexRuntimeController {
    private let service: CodexIntegrationService
    private var pollingTask: Task<Void, Never>?

    private(set) var authState: CodexAuthState = .checking
    private(set) var appServerState: CodexAppServerState = .stopped
    private(set) var isBusy = false
    private(set) var lastMessage: String?

    init(service: CodexIntegrationService) {
        self.service = service
    }

    func start() {
        if pollingTask != nil {
            return
        }

        pollingTask = Task { [weak self] in
            guard let self else { return }
            await self.refreshAuth()
            await self.pollLoop()
        }
    }

    func stop() {
        pollingTask?.cancel()
        pollingTask = nil

        Task {
            await service.stopAppServer()
        }
    }

    func refreshAuth() async {
        authState = .checking
        authState = await service.authState()
    }

    func connectCodex() async {
        isBusy = true
        defer { isBusy = false }

        authState = await service.ensureLogin()
        if case .loggedIn = authState {
            lastMessage = "Sesión Codex activa."
        } else {
            lastMessage = "No se pudo iniciar sesión en Codex."
        }
    }

    func startServer() async {
        isBusy = true
        defer { isBusy = false }

        do {
            try await service.startAppServer()
            appServerState = await service.appServerState()
            lastMessage = "Codex app-server iniciado."
        } catch {
            appServerState = .failed(error.localizedDescription)
            lastMessage = "Error iniciando app-server: \(error.localizedDescription)"
        }
    }

    func stopServer() async {
        isBusy = true
        defer { isBusy = false }

        await service.stopAppServer()
        appServerState = await service.appServerState()
        lastMessage = "Codex app-server detenido."
    }

    func send(request: String) async {
        isBusy = true
        defer { isBusy = false }

        do {
            _ = try await service.send(request: request)
            lastMessage = "Mensaje enviado al app-server."
        } catch {
            lastMessage = "Error enviando mensaje: \(error.localizedDescription)"
        }
    }

    func handleChatCommand(_ rawCommand: String, monitor: AudioProcessMonitor) async -> String {
        let command = rawCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else {
            return "Escribe un comando. Ejemplo: `mutea todo los sonidos`."
        }

        let normalizedCommand = normalize(command)

        if containsAny(normalizedCommand, Self.helpKeywords) {
            return Self.helpMessage
        }

        if containsAny(normalizedCommand, Self.loginKeywords) {
            await connectCodex()
            return lastMessage ?? "Comando ejecutado."
        }

        if containsAny(normalizedCommand, Self.startRPCKeywords) {
            await startServer()
            return lastMessage ?? "Comando ejecutado."
        }

        if containsAny(normalizedCommand, Self.stopRPCKeywords) {
            await stopServer()
            return lastMessage ?? "Comando ejecutado."
        }

        if containsAny(normalizedCommand, Self.refreshKeywords) {
            monitor.refresh()
            await refreshAuth()
            return "Actualicé sesiones de audio y estado de Codex."
        }

        if containsAny(normalizedCommand, Self.statusKeywords) {
            monitor.refresh()
            return statusMessage(for: monitor)
        }

        if containsAny(normalizedCommand, Self.unmuteKeywords) {
            monitor.refresh()
            if referencesAllSessions(normalizedCommand) {
                monitor.setAllMuted(false)
                return "Desmuteé todas las sesiones activas."
            }

            if let session = matchingSession(for: normalizedCommand, sessions: monitor.sessions) {
                monitor.setMuted(sessionID: session.id, muted: false)
                return "Desmuteé \(session.displayName)."
            }

            return "No encontré la app a desmutear. Prueba `desmutea todo` o usa el nombre exacto."
        }

        if containsAny(normalizedCommand, Self.muteKeywords) {
            monitor.refresh()
            if referencesAllSessions(normalizedCommand) {
                monitor.setAllMuted(true)
                return "Muteé todas las sesiones activas."
            }

            if let session = matchingSession(for: normalizedCommand, sessions: monitor.sessions) {
                monitor.setMuted(sessionID: session.id, muted: true)
                return "Muteé \(session.displayName)."
            }

            return "No encontré la app a mutear. Prueba `mutea todo` o usa el nombre exacto."
        }

        if containsAny(normalizedCommand, Self.volumeKeywords) {
            monitor.refreshOutputVolume()
            guard monitor.canControlOutputVolume else {
                return "No puedo controlar el volumen del dispositivo de salida actual."
            }

            if let explicitPercent = extractPercentage(from: normalizedCommand) {
                monitor.setOutputVolume(Float(explicitPercent) / 100)
                return "Volumen ajustado a \(Int(monitor.outputVolume * 100))%."
            }

            if containsAny(normalizedCommand, Self.volumeUpKeywords) {
                monitor.stepOutputVolume(by: 0.05)
                return "Subí volumen a \(Int(monitor.outputVolume * 100))%."
            }

            if containsAny(normalizedCommand, Self.volumeDownKeywords) {
                monitor.stepOutputVolume(by: -0.05)
                return "Bajé volumen a \(Int(monitor.outputVolume * 100))%."
            }

            return "Para volumen usa: `volumen 40`, `sube volumen` o `baja volumen`."
        }

        return "No entendí ese comando. Escribe `ayuda` para ver comandos disponibles."
    }

    private func pollLoop() async {
        while !Task.isCancelled {
            appServerState = await service.appServerState()
            try? await Task.sleep(for: .seconds(2))
        }
    }

    private func statusMessage(for monitor: AudioProcessMonitor) -> String {
        let total = monitor.sessions.count
        let muted = monitor.sessions.filter(\.isMuted).count
        let volumePercent = Int(monitor.outputVolume * 100)

        if total == 0 {
            return "No hay sesiones activas. Volumen \(volumePercent)% en \(monitor.outputDeviceName)."
        }

        let preview = monitor.sessions.prefix(3).map { session in
            "\(session.displayName)\(session.isMuted ? " (muted)" : "")"
        }.joined(separator: ", ")
        let extra = total > 3 ? " +\(total - 3) más." : "."

        return "Sesiones: \(total) (\(muted) muteadas). Volumen \(volumePercent)% en \(monitor.outputDeviceName). \(preview)\(extra)"
    }

    private func matchingSession(for command: String, sessions: [AudioSession]) -> AudioSession? {
        var bestSession: AudioSession?
        var bestScore = 0

        for session in sessions {
            let displayName = normalize(session.displayName)
            let bundleID = normalize(session.bundleID ?? "")
            let rawSegments = bundleID.split(separator: ".")
            var bundleSegments: [String] = []
            bundleSegments.reserveCapacity(rawSegments.count)
            for rawSegment in rawSegments {
                let segment = String(rawSegment)
                if segment.count > 2 && segment != "com" && segment != "org" && segment != "net" {
                    bundleSegments.append(segment)
                }
            }

            let displayMatch = command.contains(displayName) ? displayName.count : 0
            let bundleMatch = !bundleID.isEmpty && command.contains(bundleID) ? bundleID.count : 0
            var segmentMatch = 0
            for segment in bundleSegments {
                if command.contains(segment) {
                    segmentMatch = max(segmentMatch, segment.count)
                }
            }
            let score = max(displayMatch, max(bundleMatch, segmentMatch))

            if score > bestScore {
                bestScore = score
                bestSession = session
            }
        }

        return bestSession
    }

    private func normalize(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: "[^a-z0-9\\.\\s]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func containsAny(_ value: String, _ terms: [String]) -> Bool {
        terms.contains { value.contains($0) }
    }

    private func referencesAllSessions(_ value: String) -> Bool {
        containsAny(value, Self.allTargetsKeywords)
    }

    private func extractPercentage(from value: String) -> Int? {
        let numericTokens = value.split { !$0.isNumber }
        guard let raw = numericTokens.first, let number = Int(raw) else {
            return nil
        }
        return min(max(number, 0), 100)
    }
}

private extension CodexRuntimeController {
    static let helpKeywords = ["ayuda", "help", "comandos"]
    static let refreshKeywords = ["refresh", "actualiza", "refresca", "sincroniza", "sync"]
    static let statusKeywords = ["estado", "status", "que suena", "what is playing"]
    static let muteKeywords = ["mutea", "mutear", "silencia", "mute"]
    static let unmuteKeywords = ["desmutea", "desmutear", "unmute", "activa audio", "habilita audio"]
    static let volumeKeywords = ["volumen", "volume"]
    static let volumeUpKeywords = ["sube volumen", "aumenta volumen", "mas volumen", "volume up", "subir volumen"]
    static let volumeDownKeywords = ["baja volumen", "reduce volumen", "menos volumen", "volume down", "bajar volumen"]
    static let loginKeywords = ["login", "inicia sesion", "iniciar sesion", "conectar codex"]
    static let startRPCKeywords = ["start rpc", "inicia rpc", "iniciar rpc", "start server", "inicia servidor", "arranca rpc"]
    static let stopRPCKeywords = ["stop rpc", "deten rpc", "detener rpc", "stop server", "deten servidor"]
    static let allTargetsKeywords = ["todo", "todos", "all", "everything", "global", "sonidos"]

    static let helpMessage = """
    Comandos disponibles:
    - `mutea todo` / `desmutea todo`
    - `mutea <app>` / `desmutea <app>`
    - `volumen 40` / `sube volumen` / `baja volumen`
    - `estado` / `refresh`
    - `login codex` / `start rpc` / `stop rpc`
    """
}
