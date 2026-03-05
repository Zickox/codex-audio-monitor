import Foundation

public struct BridgeRequest: Codable, Equatable, Sendable {
    public let id: String
    public let method: String
    public let params: BridgeRequestParams?

    public init(id: String, method: String, params: BridgeRequestParams? = nil) {
        self.id = id
        self.method = method
        self.params = params
    }
}

public struct BridgeRequestParams: Codable, Equatable, Sendable {
    public let limit: Int?
    public let sessionID: String?
    public let muted: Bool?

    public init(limit: Int? = nil, sessionID: String? = nil, muted: Bool? = nil) {
        self.limit = limit
        self.sessionID = sessionID
        self.muted = muted
    }
}

public struct BridgeResponse: Codable, Equatable, Sendable {
    public let id: String
    public let result: BridgeResult?
    public let error: BridgeError?

    public init(id: String, result: BridgeResult? = nil, error: BridgeError? = nil) {
        self.id = id
        self.result = result
        self.error = error
    }

    public static func success(id: String, result: BridgeResult) -> BridgeResponse {
        BridgeResponse(id: id, result: result, error: nil)
    }

    public static func failure(id: String, code: BridgeErrorCode, message: String) -> BridgeResponse {
        BridgeResponse(id: id, result: nil, error: BridgeError(code: code.rawValue, message: message))
    }

    public static func invalidRequest(id: String = "unknown", message: String = "Invalid request payload") -> BridgeResponse {
        failure(id: id, code: .invalidRequest, message: message)
    }
}

public struct BridgeResult: Codable, Equatable, Sendable {
    public let status: String?
    public let sessions: [BridgeAudioSessionDTO]?
    public let total: Int?
    public let mutedCount: Int?
    public let generatedAt: String?
    public let changed: Bool?
    public let changedSessionID: String?

    public init(
        status: String? = nil,
        sessions: [BridgeAudioSessionDTO]? = nil,
        total: Int? = nil,
        mutedCount: Int? = nil,
        generatedAt: String? = nil,
        changed: Bool? = nil,
        changedSessionID: String? = nil
    ) {
        self.status = status
        self.sessions = sessions
        self.total = total
        self.mutedCount = mutedCount
        self.generatedAt = generatedAt
        self.changed = changed
        self.changedSessionID = changedSessionID
    }
}

public struct BridgeAudioSessionDTO: Codable, Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let bundleID: String?
    public let pids: [Int32]
    public let isMuted: Bool
    public let lastSeenAt: String

    public init(
        id: String,
        displayName: String,
        bundleID: String?,
        pids: [Int32],
        isMuted: Bool,
        lastSeenAt: String
    ) {
        self.id = id
        self.displayName = displayName
        self.bundleID = bundleID
        self.pids = pids
        self.isMuted = isMuted
        self.lastSeenAt = lastSeenAt
    }
}

public struct BridgeError: Codable, Equatable, Sendable {
    public let code: String
    public let message: String

    public init(code: String, message: String) {
        self.code = code
        self.message = message
    }
}

public enum BridgeErrorCode: String, Sendable {
    case invalidRequest = "invalid_request"
    case methodNotFound = "method_not_found"
    case internalError = "internal_error"
    case sessionNotFound = "session_not_found"
}
