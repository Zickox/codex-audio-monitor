import Foundation
import Observation

#if canImport(CodexAudioCore)
import CodexAudioCore
#endif

@MainActor
@Observable
final class CodexRuntimeController {
    private let service: CodexIntegrationService
    private var startupTask: Task<Void, Never>?

    private(set) var authState: CodexAuthState = .checking
    private(set) var isBusy = false
    private(set) var isCheckingConnection = false
    private(set) var lastMessage: String?
    private(set) var connectivityReport: CodexConnectivityReport?

    init(service: CodexIntegrationService) {
        self.service = service
    }

    func start() {
        guard startupTask == nil else {
            return
        }

        startupTask = Task { [weak self] in
            guard let self else { return }
            await self.refreshAuth()
        }
    }

    func stop() {
        startupTask?.cancel()
        startupTask = nil
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

    func checkConnectivity() async {
        isCheckingConnection = true
        defer { isCheckingConnection = false }

        let report = await service.runConnectivityChecks()
        connectivityReport = report
        authState = report.authState

        if report.isConnected {
            let latency = report.roundTripMs.map { "\($0) ms" } ?? "n/a"
            lastMessage = "Codex conectado (\(latency))."
        } else {
            lastMessage = report.errorMessage ?? "No se pudo validar la conexión con Codex."
        }
    }

    func handleChatCommand(_ rawCommand: String, monitor: AudioProcessMonitor) async -> String {
        let command = rawCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else {
            return "Escribe una instrucción. Ejemplo: `mutea todo` o `volumen 35`."
        }

        let normalizedCommand = normalize(command)
        if containsAny(normalizedCommand, Self.helpKeywords) {
            return Self.helpMessage
        }

        if containsAny(normalizedCommand, Self.loginKeywords) {
            await connectCodex()
            return lastMessage ?? "Comando ejecutado."
        }

        isBusy = true
        defer { isBusy = false }

        monitor.refresh()
        if case .loggedIn = authState {
            // already authenticated
        } else {
            authState = await service.ensureLogin()
            guard case .loggedIn = authState else {
                let authMessage = "No pude autenticar Codex. Ejecuta `login codex` y vuelve a intentar."
                lastMessage = authMessage
                return authMessage
            }
        }

        do {
            let context = CodexChatContext(
                sessions: monitor.sessions.map { session in
                    CodexSessionContext(
                        id: session.id,
                        displayName: session.displayName,
                        bundleID: session.bundleID,
                        isMuted: session.isMuted
                    )
                },
                outputVolumePercent: Int(monitor.outputVolume * 100),
                outputDeviceName: monitor.outputDeviceName
            )

            let plan = try await service.generateActionPlan(message: command, context: context)
            let effects = apply(plan.actions, monitor: monitor)
            let response = composeResponse(baseMessage: plan.assistantMessage, effects: effects)
            lastMessage = response
            return response
        } catch {
            let failure = "Error usando Codex real: \(error.localizedDescription)"
            lastMessage = failure
            return failure
        }
    }

    private func apply(_ actions: [CodexAction], monitor: AudioProcessMonitor) -> [String] {
        var notes: [String] = []

        for action in actions {
            switch action.type {
            case .none:
                continue

            case .refresh:
                monitor.refresh()
                notes.append("Actualicé la lista de audio.")

            case .status:
                monitor.refresh()
                notes.append(statusMessage(for: monitor))

            case .muteAll:
                monitor.setAllMuted(true)
                notes.append("Muteé todas las sesiones.")

            case .unmuteAll:
                monitor.setAllMuted(false)
                notes.append("Desmuteé todas las sesiones.")

            case .muteSession:
                guard let sessionID = action.sessionID else {
                    notes.append("No se indicó `sessionID` para mutear.")
                    continue
                }
                if let session = monitor.sessions.first(where: { $0.id == sessionID }) {
                    monitor.setMuted(sessionID: sessionID, muted: true)
                    notes.append("Muteé \(session.displayName).")
                } else {
                    notes.append("No encontré sesión \(sessionID).")
                }

            case .unmuteSession:
                guard let sessionID = action.sessionID else {
                    notes.append("No se indicó `sessionID` para desmutear.")
                    continue
                }
                if let session = monitor.sessions.first(where: { $0.id == sessionID }) {
                    monitor.setMuted(sessionID: sessionID, muted: false)
                    notes.append("Desmuteé \(session.displayName).")
                } else {
                    notes.append("No encontré sesión \(sessionID).")
                }

            case .setVolume:
                guard let percent = action.volumePercent else {
                    notes.append("No se indicó `volumePercent` para cambiar volumen.")
                    continue
                }
                if !monitor.canControlOutputVolume {
                    notes.append("No puedo controlar el volumen del dispositivo actual.")
                    continue
                }
                monitor.setOutputVolume(Float(percent) / 100)
                notes.append("Volumen ajustado a \(Int(monitor.outputVolume * 100))%.")
            }
        }

        return notes
    }

    private func composeResponse(baseMessage: String, effects: [String]) -> String {
        if effects.isEmpty {
            return baseMessage
        }

        if baseMessage.isEmpty {
            return effects.joined(separator: "\n")
        }

        return ([baseMessage] + effects).joined(separator: "\n")
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
}

private extension CodexRuntimeController {
    static let helpKeywords = ["ayuda", "help", "comandos"]
    static let loginKeywords = ["login", "inicia sesion", "iniciar sesion", "conectar codex"]

    static let helpMessage = """
    Comandos sugeridos:
    - `mutea todo`
    - `desmutea todo`
    - `mutea spotify`
    - `volumen 40`
    - `estado`
    - `login codex`
    """
}
