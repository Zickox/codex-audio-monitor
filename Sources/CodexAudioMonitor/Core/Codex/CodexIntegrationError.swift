import Foundation

enum CodexIntegrationError: LocalizedError {
    case cliUnavailable
    case commandFailed(command: String, exitCode: Int32, message: String)
    case timeout(command: String)
    case appServerNotRunning
    case appServerIOUnavailable

    var errorDescription: String? {
        switch self {
        case .cliUnavailable:
            return "No se encontró `codex` en PATH."
        case let .commandFailed(command, exitCode, message):
            return "Comando falló: \(command) (\(exitCode)) - \(message)"
        case let .timeout(command):
            return "Timeout ejecutando: \(command)"
        case .appServerNotRunning:
            return "El app-server de Codex no está corriendo."
        case .appServerIOUnavailable:
            return "No hay canales de IO disponibles para el app-server."
        }
    }
}
