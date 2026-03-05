import CoreAudio
import Foundation

struct AudioProcessSnapshot: Equatable {
    let processObjectID: AudioObjectID
    let pid: pid_t
    let bundleID: String?
    let isRunningOutput: Bool
}

protocol AudioProcessSnapshotProviding {
    func snapshots() throws -> [AudioProcessSnapshot]
}
