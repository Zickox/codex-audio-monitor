import Foundation

enum CodexAuthState: Equatable {
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

enum CodexAppServerState: Equatable {
    case stopped
    case starting
    case running
    case restarting(attempt: Int)
    case failed(String)

    var label: String {
        switch self {
        case .stopped:
            return "Stopped"
        case .starting:
            return "Starting"
        case .running:
            return "Running"
        case let .restarting(attempt):
            return "Restarting (\(attempt))"
        case let .failed(message):
            return "Failed: \(message)"
        }
    }
}
