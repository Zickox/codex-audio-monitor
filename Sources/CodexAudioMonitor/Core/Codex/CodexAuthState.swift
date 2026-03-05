import Foundation

enum CodexAuthState: Equatable, Sendable {
    case checking
    case loggedOut
    case loggedIn(provider: String)
    case error(String)

    var label: String {
        switch self {
        case .checking:
            return "Checking"
        case .loggedOut:
            return "Logged out"
        case let .loggedIn(provider):
            return "Logged in (\(provider))"
        case let .error(message):
            return "Error: \(message)"
        }
    }
}
