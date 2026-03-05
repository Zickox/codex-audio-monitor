import Foundation

struct CodexChatContext: Codable, Sendable {
    let sessions: [CodexSessionContext]
    let outputVolumePercent: Int
    let outputDeviceName: String
}

struct CodexSessionContext: Codable, Sendable {
    let id: String
    let displayName: String
    let bundleID: String?
    let isMuted: Bool
    let appGainPercent: Int?
    let appGainAvailable: Bool?

    init(
        id: String,
        displayName: String,
        bundleID: String?,
        isMuted: Bool,
        appGainPercent: Int? = nil,
        appGainAvailable: Bool? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.bundleID = bundleID
        self.isMuted = isMuted
        self.appGainPercent = appGainPercent
        self.appGainAvailable = appGainAvailable
    }
}

struct CodexActionPlan: Codable, Sendable {
    let assistantMessage: String
    let actions: [CodexAction]
}

struct CodexAction: Codable, Sendable {
    let type: CodexActionType
    let sessionID: String?
    let volumePercent: Int?
    let gainPercent: Int?
}

enum CodexActionType: String, Codable, Sendable {
    case none = "none"
    case refresh = "refresh"
    case status = "status"
    case muteAll = "mute_all"
    case unmuteAll = "unmute_all"
    case muteSession = "mute_session"
    case unmuteSession = "unmute_session"
    case setVolume = "set_volume"
    case setSessionGain = "set_session_gain"
}
