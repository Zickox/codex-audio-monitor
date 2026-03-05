@testable import CodexAudioCore
import CoreAudio
import XCTest

private enum MockError: Error {
    case injected
}

private final class MockSnapshotProvider: AudioProcessSnapshotProviding {
    var snapshotsValue: [AudioProcessSnapshot]
    var injectedError: Error?

    init(snapshotsValue: [AudioProcessSnapshot]) {
        self.snapshotsValue = snapshotsValue
    }

    func snapshots() throws -> [AudioProcessSnapshot] {
        if let injectedError {
            throw injectedError
        }
        return snapshotsValue
    }
}

private final class MockMuteBackend: AudioMuteBackend {
    var mutedProcessIDs = Set<AudioObjectID>()
    var muteCalls: [AudioObjectID] = []
    var unmuteCalls: [AudioObjectID] = []
    var cleanupCalled = false

    func mute(processObjectID: AudioObjectID) throws {
        mutedProcessIDs.insert(processObjectID)
        muteCalls.append(processObjectID)
    }

    func unmute(processObjectID: AudioObjectID) throws {
        mutedProcessIDs.remove(processObjectID)
        unmuteCalls.append(processObjectID)
    }

    func cleanup() {
        cleanupCalled = true
        mutedProcessIDs.removeAll()
    }
}

private final class MockOutputVolumeController: AudioOutputVolumeControlling {
    var currentStateValue = AudioOutputVolumeState(volume: 0.4, canSetVolume: true, deviceName: "Mock Output")
    var currentStateError: Error?
    var setVolumeCalls: [Float] = []
    var setVolumeError: Error?

    func currentState() throws -> AudioOutputVolumeState {
        if let currentStateError {
            throw currentStateError
        }
        return currentStateValue
    }

    func setVolume(_ value: Float) throws {
        if let setVolumeError {
            throw setVolumeError
        }
        setVolumeCalls.append(value)
        currentStateValue = AudioOutputVolumeState(
            volume: value,
            canSetVolume: currentStateValue.canSetVolume,
            deviceName: currentStateValue.deviceName
        )
    }
}

@MainActor
final class AudioProcessMonitorTests: XCTestCase {
    func testGroupingByBundleAndPIDFallback() {
        let provider = MockSnapshotProvider(
            snapshotsValue: [
                AudioProcessSnapshot(processObjectID: 11, pid: 1001, bundleID: "com.spotify.client", isRunningOutput: true),
                AudioProcessSnapshot(processObjectID: 12, pid: 1002, bundleID: "com.spotify.client", isRunningOutput: true),
                AudioProcessSnapshot(processObjectID: 20, pid: 2001, bundleID: nil, isRunningOutput: true)
            ]
        )
        let muteBackend = MockMuteBackend()
        let volumeController = MockOutputVolumeController()
        let monitor = AudioProcessMonitor(
            snapshotProvider: provider,
            muteBackend: muteBackend,
            outputVolumeController: volumeController,
            pollInterval: .seconds(60)
        )

        monitor.refresh()

        XCTAssertEqual(monitor.sessions.count, 2)
        XCTAssertTrue(monitor.sessions.contains(where: { $0.id == "bundle:com.spotify.client" }))
        XCTAssertTrue(monitor.sessions.contains(where: { $0.id == "pid:2001" }))
    }

    func testMutedSessionIsReconciledWhenSessionDisappears() {
        let provider = MockSnapshotProvider(
            snapshotsValue: [
                AudioProcessSnapshot(processObjectID: 33, pid: 3001, bundleID: "com.example.player", isRunningOutput: true)
            ]
        )
        let muteBackend = MockMuteBackend()
        let volumeController = MockOutputVolumeController()
        let monitor = AudioProcessMonitor(
            snapshotProvider: provider,
            muteBackend: muteBackend,
            outputVolumeController: volumeController,
            pollInterval: .seconds(60)
        )

        monitor.refresh()
        let sessionID = monitor.sessions[0].id

        monitor.toggleMute(sessionID: sessionID)
        XCTAssertTrue(monitor.sessions[0].isMuted)

        provider.snapshotsValue = []
        monitor.refresh()
        XCTAssertTrue(monitor.sessions.isEmpty)

        provider.snapshotsValue = [
            AudioProcessSnapshot(processObjectID: 33, pid: 3001, bundleID: "com.example.player", isRunningOutput: true)
        ]
        monitor.refresh()

        XCTAssertEqual(monitor.sessions.count, 1)
        XCTAssertFalse(monitor.sessions[0].isMuted)
    }

    func testStopCallsCleanupOnMuteBackend() {
        let provider = MockSnapshotProvider(snapshotsValue: [])
        let muteBackend = MockMuteBackend()
        let volumeController = MockOutputVolumeController()
        let monitor = AudioProcessMonitor(
            snapshotProvider: provider,
            muteBackend: muteBackend,
            outputVolumeController: volumeController,
            pollInterval: .seconds(60)
        )

        monitor.stop()

        XCTAssertTrue(muteBackend.cleanupCalled)
    }

    func testRefreshSurfaceErrorsFromSnapshotProvider() {
        let provider = MockSnapshotProvider(snapshotsValue: [])
        provider.injectedError = MockError.injected
        let muteBackend = MockMuteBackend()
        let volumeController = MockOutputVolumeController()
        let monitor = AudioProcessMonitor(
            snapshotProvider: provider,
            muteBackend: muteBackend,
            outputVolumeController: volumeController,
            pollInterval: .seconds(60)
        )

        monitor.refresh()

        XCTAssertNotNil(monitor.errorMessage)
    }

    func testSetAllMutedUpdatesEverySession() {
        let provider = MockSnapshotProvider(
            snapshotsValue: [
                AudioProcessSnapshot(processObjectID: 11, pid: 1001, bundleID: "com.spotify.client", isRunningOutput: true),
                AudioProcessSnapshot(processObjectID: 12, pid: 1002, bundleID: "com.music.player", isRunningOutput: true)
            ]
        )
        let muteBackend = MockMuteBackend()
        let volumeController = MockOutputVolumeController()
        let monitor = AudioProcessMonitor(
            snapshotProvider: provider,
            muteBackend: muteBackend,
            outputVolumeController: volumeController,
            pollInterval: .seconds(60)
        )

        monitor.refresh()
        monitor.setAllMuted(true)

        XCTAssertTrue(monitor.sessions.allSatisfy(\.isMuted))
        XCTAssertEqual(muteBackend.mutedProcessIDs, Set([11, 12]))

        monitor.setAllMuted(false)

        XCTAssertTrue(monitor.sessions.allSatisfy { !$0.isMuted })
        XCTAssertTrue(muteBackend.mutedProcessIDs.isEmpty)
    }

    func testSetOutputVolumeCallsOutputController() {
        let provider = MockSnapshotProvider(snapshotsValue: [])
        let muteBackend = MockMuteBackend()
        let volumeController = MockOutputVolumeController()
        let monitor = AudioProcessMonitor(
            snapshotProvider: provider,
            muteBackend: muteBackend,
            outputVolumeController: volumeController,
            pollInterval: .seconds(60)
        )

        monitor.setOutputVolume(0.7)

        XCTAssertEqual(volumeController.setVolumeCalls.last ?? 0, 0.7, accuracy: 0.001)
        XCTAssertEqual(monitor.outputVolume, 0.7, accuracy: 0.001)
        XCTAssertTrue(monitor.canControlOutputVolume)
    }

    func testRefreshOutputVolumeDisablesControlWhenUnavailable() {
        let provider = MockSnapshotProvider(snapshotsValue: [])
        let muteBackend = MockMuteBackend()
        let volumeController = MockOutputVolumeController()
        let monitor = AudioProcessMonitor(
            snapshotProvider: provider,
            muteBackend: muteBackend,
            outputVolumeController: volumeController,
            pollInterval: .seconds(60)
        )
        volumeController.currentStateError = MockError.injected

        monitor.refreshOutputVolume()

        XCTAssertFalse(monitor.canControlOutputVolume)
    }
}
