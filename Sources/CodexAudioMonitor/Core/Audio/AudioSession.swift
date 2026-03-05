import CoreAudio
import Foundation

public struct AudioSession: Identifiable, Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let bundleID: String?
    public let pids: [pid_t]
    public let processObjectIDs: [AudioObjectID]
    public var isMuted: Bool
    public var lastSeenAt: Date

    public init(
        id: String,
        displayName: String,
        bundleID: String?,
        pids: [pid_t],
        processObjectIDs: [AudioObjectID],
        isMuted: Bool,
        lastSeenAt: Date
    ) {
        self.id = id
        self.displayName = displayName
        self.bundleID = bundleID
        self.pids = pids
        self.processObjectIDs = processObjectIDs
        self.isMuted = isMuted
        self.lastSeenAt = lastSeenAt
    }
}
