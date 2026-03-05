import Foundation

enum CodexIntegrationError: LocalizedError {
    case cliUnavailable
    case commandFailed(command: String, exitCode: Int32, message: String)
    case timeout(command: String)
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .cliUnavailable:
            return "No se encontró `codex` en PATH."
        case let .commandFailed(command, exitCode, message):
            return "Comando falló: \(command) (\(exitCode)) - \(message)"
        case let .timeout(command):
            return "Timeout ejecutando: \(command)"
        case let .invalidResponse(message):
            return "Respuesta inválida de Codex: \(message)"
        }
    }
}
