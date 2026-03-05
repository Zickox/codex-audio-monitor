import CoreAudio
import XCTest
@testable import CodexAudioMonitor

@MainActor
final class AudioProcessMonitorGainTests: XCTestCase {
    func testLoadsPersistedGainByBundleID() {
        let defaults = makeDefaults()
        let store = AppGainStore(userDefaults: defaults, key: "test.gain.store")
        store.setGain(0.42, for: "com.spotify.client")

        let snapshots = StubSnapshotProvider([
            AudioProcessSnapshot(
                processObjectID: AudioObjectID(301),
                pid: 777,
                bundleID: "com.spotify.client",
                isRunningOutput: true
            )
        ])
        let backend = RecordingProcessControlBackend()
        let monitor = makeMonitor(
            snapshotProvider: snapshots,
            backend: backend,
            store: store
        )

        monitor.refresh()

        if let gain = monitor.sessions.first?.appGain {
            XCTAssertEqual(gain, 0.42, accuracy: 0.0001)
        } else {
            XCTFail("Expected a session with persisted gain")
        }
    }

    func testSetSessionGainPersistsOnlyForBundleSessions() {
        let defaults = makeDefaults()
        let store = AppGainStore(userDefaults: defaults, key: "test.gain.store")

        let snapshots = StubSnapshotProvider([
            AudioProcessSnapshot(
                processObjectID: AudioObjectID(401),
                pid: 1701,
                bundleID: "com.spotify.client",
                isRunningOutput: true
            ),
            AudioProcessSnapshot(
                processObjectID: AudioObjectID(402),
                pid: 1702,
                bundleID: nil,
                isRunningOutput: true
            )
        ])

        let backend = RecordingProcessControlBackend()
        let monitor = makeMonitor(
            snapshotProvider: snapshots,
            backend: backend,
            store: store
        )

        monitor.refresh()
        monitor.setSessionGain(sessionID: "bundle:com.spotify.client", gain: 0.33)
        monitor.setSessionGain(sessionID: "pid:1702", gain: 0.25)

        if let spotifyGain = store.gain(for: "com.spotify.client") {
            XCTAssertEqual(spotifyGain, 0.33, accuracy: 0.0001)
        } else {
            XCTFail("Expected persisted Spotify gain")
        }
        XCTAssertNil(store.gain(for: "pid:1702"))
    }

    func testChangingGainKeepsMuteState() {
        let snapshots = StubSnapshotProvider([
            AudioProcessSnapshot(
                processObjectID: AudioObjectID(501),
                pid: 1901,
                bundleID: "com.spotify.client",
                isRunningOutput: true
            )
        ])
        let backend = RecordingProcessControlBackend()
        let monitor = makeMonitor(snapshotProvider: snapshots, backend: backend, store: AppGainStore())

        monitor.refresh()
        monitor.setMuted(sessionID: "bundle:com.spotify.client", muted: true)
        monitor.setSessionGain(sessionID: "bundle:com.spotify.client", gain: 0.2)

        let session = monitor.sessions.first
        XCTAssertEqual(session?.isMuted, true)
        if let gain = session?.appGain {
            XCTAssertEqual(gain, 0.2, accuracy: 0.0001)
        } else {
            XCTFail("Expected a session with gain")
        }

        let latest = backend.applyCalls.last
        XCTAssertEqual(latest?.muted, true)
        if let latest {
            XCTAssertEqual(latest.gain, 0.2, accuracy: 0.0001)
        } else {
            XCTFail("Expected apply call")
        }
    }

    func testRemovedProcessTriggersBackendRemove() {
        let snapshots = StubSnapshotProvider([
            AudioProcessSnapshot(
                processObjectID: AudioObjectID(601),
                pid: 2101,
                bundleID: "com.spotify.client",
                isRunningOutput: true
            )
        ])
        let backend = RecordingProcessControlBackend()
        let monitor = makeMonitor(snapshotProvider: snapshots, backend: backend, store: AppGainStore())

        monitor.refresh()
        snapshots.currentSnapshots = []
        monitor.refresh()

        XCTAssertTrue(backend.removedProcessIDs.contains(AudioObjectID(601)))
    }

    func testAudioCapturePermissionFailureKeepsSessionVisibleAndSurfacesError() {
        let defaults = makeDefaults()
        let store = AppGainStore(userDefaults: defaults, key: "test.gain.store")
        store.setGain(0.5, for: "com.apple.Music")

        let snapshots = StubSnapshotProvider([
            AudioProcessSnapshot(
                processObjectID: AudioObjectID(701),
                pid: 3101,
                bundleID: "com.apple.Music",
                isRunningOutput: true
            )
        ])

        let backend = PermissionFailingProcessControlBackend()
        let monitor = makeMonitor(
            snapshotProvider: snapshots,
            backend: backend,
            store: store
        )

        monitor.refresh()

        XCTAssertEqual(monitor.sessions.count, 1)
        XCTAssertEqual(monitor.sessions.first?.isAppGainAvailable, false)
        XCTAssertEqual(monitor.sessions.first?.appGain ?? 0, 1.0, accuracy: 0.0001)
        XCTAssertTrue(monitor.errorMessage?.contains("permiso de captura de audio del sistema") == true)
    }

    func testTapPCMScalerAttenuatesFloat32SamplesProgressively() {
        let inputSamples: [Float32] = [1.0, -0.5, 0.25, -0.125]
        var outputSamples = Array(repeating: Float32.zero, count: inputSamples.count)

        inputSamples.withUnsafeBytes { inputBytes in
            outputSamples.withUnsafeMutableBytes { outputBytes in
                TapPCMScaler.scaleSamples(
                    input: inputBytes.baseAddress!,
                    output: outputBytes.baseAddress!,
                    byteCount: inputBytes.count,
                    gain: 0.5,
                    format: .float32
                )
            }
        }

        XCTAssertEqual(outputSamples[0], 0.5, accuracy: 0.0001)
        XCTAssertEqual(outputSamples[1], -0.25, accuracy: 0.0001)
        XCTAssertEqual(outputSamples[2], 0.125, accuracy: 0.0001)
        XCTAssertEqual(outputSamples[3], -0.0625, accuracy: 0.0001)
    }

    func testTapPCMScalerAttenuatesSignedIntegerSamplesProgressively() {
        let inputSamples: [Int16] = [12_000, -8_000, 4_000, -2_000]
        var outputSamples = Array(repeating: Int16.zero, count: inputSamples.count)

        inputSamples.withUnsafeBytes { inputBytes in
            outputSamples.withUnsafeMutableBytes { outputBytes in
                TapPCMScaler.scaleSamples(
                    input: inputBytes.baseAddress!,
                    output: outputBytes.baseAddress!,
                    byteCount: inputBytes.count,
                    gain: 0.25,
                    format: .int16
                )
            }
        }

        XCTAssertEqual(outputSamples, [3_000, -2_000, 1_000, -500])
    }

    private func makeMonitor(
        snapshotProvider: StubSnapshotProvider,
        backend: any AudioProcessControlBackend,
        store: AppGainStore
    ) -> AudioProcessMonitor {
        let volumeController = StubOutputVolumeController(
            state: AudioOutputVolumeState(
                volume: 0.5,
                canSetVolume: true,
                deviceName: "Test Device"
            )
        )

        return AudioProcessMonitor(
            snapshotProvider: snapshotProvider,
            processControlBackend: backend,
            outputVolumeController: volumeController,
            appGainStore: store,
            pollInterval: .seconds(5)
        )
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "AudioProcessMonitorGainTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

private final class PermissionFailingProcessControlBackend: AudioProcessControlBackend {
    func apply(processObjectID: AudioObjectID, muted: Bool, gain: Float) throws {
        if muted || gain < 0.999 {
            throw AudioMonitorError.audioCapturePermissionRequired
        }
    }

    func remove(processObjectID: AudioObjectID) throws {}

    func cleanup() {}
}
