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
        let muteBackend = RecordingMuteBackend()
        let backend = RecordingProcessControlBackend()
        let storeDefaults = makeDefaults()
        let store = AppGainStore(userDefaults: storeDefaults, key: "test.gain.store")
        let monitor = makeMonitor(
            snapshotProvider: snapshots,
            muteBackend: muteBackend,
            backend: backend,
            store: store
        )

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

        XCTAssertEqual(muteBackend.mutedProcessIDs, [AudioObjectID(501)])
        XCTAssertTrue(backend.applyCalls.isEmpty)
    }

    func testUnmutedSessionsArePrioritizedOverMutedSessions() {
        let snapshots = StubSnapshotProvider([
            AudioProcessSnapshot(
                processObjectID: AudioObjectID(511),
                pid: 1902,
                bundleID: "com.zeta.player",
                isRunningOutput: true
            ),
            AudioProcessSnapshot(
                processObjectID: AudioObjectID(512),
                pid: 1903,
                bundleID: "com.alpha.browser",
                isRunningOutput: true
            )
        ])
        let backend = RecordingProcessControlBackend()
        let monitor = makeMonitor(snapshotProvider: snapshots, backend: backend, store: AppGainStore())

        monitor.refresh()
        monitor.setMuted(sessionID: "bundle:com.alpha.browser", muted: true)

        XCTAssertEqual(monitor.sessions.map(\.id), [
            "bundle:com.zeta.player",
            "bundle:com.alpha.browser"
        ])
    }

    func testSoloMutesOtherSessionsAndLeavesTargetActive() {
        let snapshots = StubSnapshotProvider([
            AudioProcessSnapshot(
                processObjectID: AudioObjectID(521),
                pid: 2001,
                bundleID: "com.spotify.client",
                isRunningOutput: true
            ),
            AudioProcessSnapshot(
                processObjectID: AudioObjectID(522),
                pid: 2002,
                bundleID: "com.apple.Safari",
                isRunningOutput: true
            )
        ])
        let backend = RecordingProcessControlBackend()
        let monitor = makeMonitor(snapshotProvider: snapshots, backend: backend, store: AppGainStore())

        monitor.refresh()
        monitor.solo(sessionID: "bundle:com.spotify.client")

        XCTAssertEqual(monitor.sessions.first(where: { $0.id == "bundle:com.spotify.client" })?.isMuted, false)
        XCTAssertEqual(monitor.sessions.first(where: { $0.id == "bundle:com.apple.Safari" })?.isMuted, true)
    }

    func testMuteOthersMutesRemainingSessionsOnly() {
        let snapshots = StubSnapshotProvider([
            AudioProcessSnapshot(
                processObjectID: AudioObjectID(531),
                pid: 2201,
                bundleID: "com.spotify.client",
                isRunningOutput: true
            ),
            AudioProcessSnapshot(
                processObjectID: AudioObjectID(532),
                pid: 2202,
                bundleID: "com.apple.Safari",
                isRunningOutput: true
            )
        ])
        let backend = RecordingProcessControlBackend()
        let monitor = makeMonitor(snapshotProvider: snapshots, backend: backend, store: AppGainStore())

        monitor.refresh()
        monitor.muteOthers(except: "bundle:com.apple.Safari")

        XCTAssertEqual(monitor.sessions.first(where: { $0.id == "bundle:com.spotify.client" })?.isMuted, true)
        XCTAssertEqual(monitor.sessions.first(where: { $0.id == "bundle:com.apple.Safari" })?.isMuted, false)
    }

    func testRestoreAllSessionGainsResetsRuntimeAndPersistedValues() {
        let defaults = makeDefaults()
        let store = AppGainStore(userDefaults: defaults, key: "test.gain.store")
        let snapshots = StubSnapshotProvider([
            AudioProcessSnapshot(
                processObjectID: AudioObjectID(541),
                pid: 2301,
                bundleID: "com.spotify.client",
                isRunningOutput: true
            )
        ])
        let backend = RecordingProcessControlBackend()
        let monitor = makeMonitor(snapshotProvider: snapshots, backend: backend, store: store)

        monitor.refresh()
        monitor.setSessionGain(sessionID: "bundle:com.spotify.client", gain: 0.28)
        monitor.restoreAllSessionGains()

        XCTAssertEqual(monitor.sessions.first?.appGain ?? 0, 1, accuracy: 0.0001)
        XCTAssertNil(store.gain(for: "com.spotify.client"))
    }

    func testRemovedMutedProcessTriggersBackendUnmute() {
        let snapshots = StubSnapshotProvider([
            AudioProcessSnapshot(
                processObjectID: AudioObjectID(601),
                pid: 2101,
                bundleID: "com.spotify.client",
                isRunningOutput: true
            )
        ])
        let muteBackend = RecordingMuteBackend()
        let backend = RecordingProcessControlBackend()
        let monitor = makeMonitor(
            snapshotProvider: snapshots,
            muteBackend: muteBackend,
            backend: backend,
            store: AppGainStore()
        )

        monitor.refresh()
        monitor.setMuted(sessionID: "bundle:com.spotify.client", muted: true)
        snapshots.currentSnapshots = []
        monitor.refresh()

        XCTAssertTrue(muteBackend.unmutedProcessIDs.contains(AudioObjectID(601)))
    }

    func testAudioCapturePermissionFailureKeepsSessionVisibleAndSurfacesError() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: "audio.perAppGain.enabled")
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
            store: store,
            defaults: defaults,
            audioCaptureAccessState: .granted,
            perAppControlsState: .active
        )

        monitor.refresh()

        XCTAssertEqual(monitor.sessions.count, 1)
        XCTAssertEqual(monitor.sessions.first?.appGain ?? 0, 0.5, accuracy: 0.0001)
        XCTAssertEqual(monitor.audioCaptureAccessState, .denied)
        XCTAssertEqual(monitor.perAppControlsState, .inactive)
        XCTAssertEqual(monitor.sessions.first?.isMuted, false)
        XCTAssertNil(monitor.errorMessage)
    }

    func testAppGainPermissionFailureDoesNotClearExistingMutedState() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: "audio.perAppGain.enabled")
        let store = AppGainStore(userDefaults: defaults, key: "test.gain.store")
        store.setGain(0.4, for: "com.apple.TV")

        let snapshots = StubSnapshotProvider([
            AudioProcessSnapshot(
                processObjectID: AudioObjectID(702),
                pid: 3102,
                bundleID: "com.apple.Music",
                isRunningOutput: true
            ),
            AudioProcessSnapshot(
                processObjectID: AudioObjectID(703),
                pid: 3103,
                bundleID: "com.apple.TV",
                isRunningOutput: true
            )
        ])

        let muteBackend = RecordingMuteBackend()
        let backend = PermissionFailingProcessControlBackend()
        let monitor = makeMonitor(
            snapshotProvider: snapshots,
            muteBackend: muteBackend,
            backend: backend,
            store: store,
            defaults: defaults,
            audioCaptureAccessState: .granted,
            perAppControlsState: .active
        )

        monitor.refresh()
        monitor.setMuted(sessionID: "bundle:com.apple.Music", muted: true)
        monitor.setSessionGain(sessionID: "bundle:com.apple.TV", gain: 0.4)

        XCTAssertEqual(monitor.sessions.count, 2)
        XCTAssertEqual(
            monitor.sessions.first(where: { $0.id == "bundle:com.apple.Music" })?.isMuted,
            true
        )
        XCTAssertEqual(monitor.audioCaptureAccessState, .denied)
        XCTAssertEqual(monitor.perAppControlsState, .inactive)
        XCTAssertNil(monitor.errorMessage)
        XCTAssertEqual(muteBackend.mutedProcessIDs.last, AudioObjectID(702))
    }

    func testDisabledPerAppGainFallsBackToMuteOnlyPath() {
        let defaults = makeDefaults()
        defaults.set(false, forKey: "audio.perAppGain.enabled")
        let store = AppGainStore(userDefaults: defaults, key: "test.gain.store")
        store.setGain(0.35, for: "com.spotify.client")

        let snapshots = StubSnapshotProvider([
            AudioProcessSnapshot(
                processObjectID: AudioObjectID(711),
                pid: 3201,
                bundleID: "com.spotify.client",
                isRunningOutput: true
            )
        ])

        let backend = RecordingProcessControlBackend()
        let monitor = makeMonitor(
            snapshotProvider: snapshots,
            backend: backend,
            store: store,
            defaults: defaults
        )

        monitor.refresh()

        XCTAssertFalse(monitor.isPerAppGainEnabled)
        XCTAssertEqual(monitor.sessions.first?.appGain ?? 0, 0.35, accuracy: 0.0001)
        XCTAssertTrue(backend.applyCalls.isEmpty)
    }

    func testSetPerAppGainEnabledDoesNotRequestAudioCaptureAccess() {
        let defaults = makeDefaults()
        defaults.set(false, forKey: "audio.perAppGain.enabled")

        let snapshots = StubSnapshotProvider([
            AudioProcessSnapshot(
                processObjectID: AudioObjectID(712),
                pid: 3202,
                bundleID: "com.apple.Music",
                isRunningOutput: true
            )
        ])

        let backend = RecordingProcessControlBackend()
        let monitor = makeMonitor(
            snapshotProvider: snapshots,
            backend: backend,
            store: AppGainStore(userDefaults: defaults, key: "test.gain.store"),
            defaults: defaults,
            audioCaptureAccessState: .unknown,
            perAppControlsState: .inactive
        )

        monitor.refresh()
        monitor.setPerAppGainEnabled(true)

        XCTAssertTrue(monitor.isPerAppGainEnabled)
        XCTAssertEqual(backend.permissionProbeProcessIDs, [])
        XCTAssertEqual(monitor.audioCaptureAccessState, .unknown)
        XCTAssertEqual(monitor.perAppControlsState, .inactive)
    }

    func testToggleMuteDoesNotRequestAudioCaptureAccessWhenControlsAreInactive() {
        let defaults = makeDefaults()
        defaults.set(false, forKey: "audio.perAppGain.enabled")

        let snapshots = StubSnapshotProvider([
            AudioProcessSnapshot(
                processObjectID: AudioObjectID(717),
                pid: 3207,
                bundleID: "com.apple.Music",
                isRunningOutput: true
            )
        ])

        let muteBackend = RecordingMuteBackend()
        let backend = RecordingProcessControlBackend()
        let monitor = makeMonitor(
            snapshotProvider: snapshots,
            muteBackend: muteBackend,
            backend: backend,
            store: AppGainStore(userDefaults: defaults, key: "test.gain.store"),
            defaults: defaults,
            audioCaptureAccessState: .unknown,
            perAppControlsState: .inactive
        )

        monitor.refresh()
        monitor.toggleMute(sessionID: "bundle:com.apple.Music")

        XCTAssertEqual(backend.permissionProbeProcessIDs, [])
        XCTAssertEqual(monitor.audioCaptureAccessState, .unknown)
        XCTAssertEqual(monitor.perAppControlsState, .inactive)
        XCTAssertEqual(monitor.sessions.first?.isMuted, true)
        XCTAssertEqual(muteBackend.mutedProcessIDs.last, AudioObjectID(717))
    }

    func testSetAllMutedDoesNotRequestAudioCaptureAccessWhenControlsAreInactive() {
        let defaults = makeDefaults()
        defaults.set(false, forKey: "audio.perAppGain.enabled")

        let snapshots = StubSnapshotProvider([
            AudioProcessSnapshot(
                processObjectID: AudioObjectID(718),
                pid: 3208,
                bundleID: "com.apple.Music",
                isRunningOutput: true
            ),
            AudioProcessSnapshot(
                processObjectID: AudioObjectID(719),
                pid: 3209,
                bundleID: "com.spotify.client",
                isRunningOutput: true
            )
        ])

        let muteBackend = RecordingMuteBackend()
        let backend = RecordingProcessControlBackend()
        let monitor = makeMonitor(
            snapshotProvider: snapshots,
            muteBackend: muteBackend,
            backend: backend,
            store: AppGainStore(userDefaults: defaults, key: "test.gain.store"),
            defaults: defaults,
            audioCaptureAccessState: .unknown,
            perAppControlsState: .inactive
        )

        monitor.refresh()
        monitor.setAllMuted(true)

        XCTAssertEqual(backend.permissionProbeProcessIDs, [])
        XCTAssertEqual(monitor.audioCaptureAccessState, .unknown)
        XCTAssertEqual(monitor.perAppControlsState, .inactive)
        XCTAssertTrue(monitor.sessions.allSatisfy(\.isMuted))
        XCTAssertEqual(Set(muteBackend.mutedProcessIDs), Set([AudioObjectID(718), AudioObjectID(719)]))
    }

    func testToggleMuteDoesNotChangeAppGainActivationStateWhenControlsAreInactive() {
        let defaults = makeDefaults()
        defaults.set(false, forKey: "audio.perAppGain.enabled")

        let snapshots = StubSnapshotProvider([
            AudioProcessSnapshot(
                processObjectID: AudioObjectID(720),
                pid: 3210,
                bundleID: "com.apple.Music",
                isRunningOutput: true
            )
        ])

        let muteBackend = RecordingMuteBackend()
        let backend = RecordingProcessControlBackend()
        let monitor = makeMonitor(
            snapshotProvider: snapshots,
            muteBackend: muteBackend,
            backend: backend,
            store: AppGainStore(userDefaults: defaults, key: "test.gain.store"),
            defaults: defaults,
            audioCaptureAccessState: .unknown,
            perAppControlsState: .inactive
        )

        monitor.refresh()
        monitor.toggleMute(sessionID: "bundle:com.apple.Music")

        XCTAssertEqual(monitor.audioCaptureAccessState, .unknown)
        XCTAssertEqual(monitor.perAppControlsState, .inactive)
        XCTAssertEqual(monitor.sessions.first?.isMuted, true)
        XCTAssertNil(monitor.errorMessage)
        XCTAssertEqual(muteBackend.mutedProcessIDs.last, AudioObjectID(720))
    }

    func testRequestPerAppControlsActivationRequestsAudioCaptureAccessForActiveSession() {
        let defaults = makeDefaults()
        defaults.set(false, forKey: "audio.perAppGain.enabled")

        let snapshots = StubSnapshotProvider([
            AudioProcessSnapshot(
                processObjectID: AudioObjectID(713),
                pid: 3203,
                bundleID: "com.apple.Music",
                isRunningOutput: true
            )
        ])

        let backend = RecordingProcessControlBackend()
        let monitor = makeMonitor(
            snapshotProvider: snapshots,
            backend: backend,
            store: AppGainStore(userDefaults: defaults, key: "test.gain.store"),
            defaults: defaults,
            audioCaptureAccessState: .unknown,
            perAppControlsState: .inactive
        )

        monitor.refresh()
        monitor.requestPerAppControlsActivation()

        XCTAssertEqual(backend.permissionProbeProcessIDs, [AudioObjectID(713)])
        XCTAssertEqual(monitor.audioCaptureAccessState, .granted)
        XCTAssertEqual(monitor.perAppControlsState, .active)
        XCTAssertNil(monitor.errorMessage)
    }

    func testRequestPerAppControlsActivationAppliesStoredGainWhenAppGainIsEnabled() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: "audio.perAppGain.enabled")
        let store = AppGainStore(userDefaults: defaults, key: "test.gain.store")
        store.setGain(0.32, for: "com.apple.Music")

        let snapshots = StubSnapshotProvider([
            AudioProcessSnapshot(
                processObjectID: AudioObjectID(716),
                pid: 3206,
                bundleID: "com.apple.Music",
                isRunningOutput: true
            )
        ])

        let backend = RecordingProcessControlBackend()
        let monitor = makeMonitor(
            snapshotProvider: snapshots,
            backend: backend,
            store: store,
            defaults: defaults,
            audioCaptureAccessState: .unknown,
            perAppControlsState: .inactive
        )

        monitor.refresh()
        monitor.requestPerAppControlsActivation()

        XCTAssertEqual(monitor.audioCaptureAccessState, .granted)
        XCTAssertEqual(monitor.perAppControlsState, .active)
        XCTAssertEqual(monitor.sessions.first?.appGain ?? 0, 0.32, accuracy: 0.0001)
        XCTAssertEqual(backend.permissionProbeProcessIDs, [AudioObjectID(716)])
        XCTAssertEqual(backend.applyCalls.last?.gain ?? 0, 0.32, accuracy: 0.0001)
    }

    func testRequestPerAppControlsActivationKeepsPermissionDeniedStateWhenProbeFails() {
        let defaults = makeDefaults()
        defaults.set(false, forKey: "audio.perAppGain.enabled")

        let snapshots = StubSnapshotProvider([
            AudioProcessSnapshot(
                processObjectID: AudioObjectID(714),
                pid: 3204,
                bundleID: "com.apple.Music",
                isRunningOutput: true
            )
        ])

        let backend = PermissionFailingProcessControlBackend()
        let monitor = makeMonitor(
            snapshotProvider: snapshots,
            backend: backend,
            store: AppGainStore(userDefaults: defaults, key: "test.gain.store"),
            defaults: defaults,
            audioCaptureAccessState: .unknown,
            perAppControlsState: .inactive
        )

        monitor.refresh()
        monitor.requestPerAppControlsActivation()

        XCTAssertEqual(monitor.audioCaptureAccessState, .denied)
        XCTAssertEqual(monitor.perAppControlsState, .inactive)
        XCTAssertNil(monitor.errorMessage)
    }

    func testRefreshWithPersistedGainDoesNotApplyWhenPerAppControlsAreInactive() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: "audio.perAppGain.enabled")
        let store = AppGainStore(userDefaults: defaults, key: "test.gain.store")
        store.setGain(0.4, for: "com.apple.Music")

        let snapshots = StubSnapshotProvider([
            AudioProcessSnapshot(
                processObjectID: AudioObjectID(715),
                pid: 3205,
                bundleID: "com.apple.Music",
                isRunningOutput: true
            )
        ])

        let backend = RecordingProcessControlBackend()
        let monitor = makeMonitor(
            snapshotProvider: snapshots,
            backend: backend,
            store: store,
            defaults: defaults,
            audioCaptureAccessState: .unknown,
            perAppControlsState: .inactive
        )

        monitor.refresh()

        XCTAssertEqual(monitor.sessions.first?.appGain ?? 0, 0.4, accuracy: 0.0001)
        XCTAssertEqual(backend.applyCalls, [])
        XCTAssertEqual(backend.permissionProbeProcessIDs, [])
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
        muteBackend: any AudioMuteBackend = RecordingMuteBackend(),
        backend: any AudioProcessControlBackend,
        store: AppGainStore
    ) -> AudioProcessMonitor {
        let defaults = makeDefaults()
        defaults.set(true, forKey: "audio.perAppGain.enabled")
        return makeMonitor(
            snapshotProvider: snapshotProvider,
            muteBackend: muteBackend,
            backend: backend,
            store: store,
            defaults: defaults
        )
    }

    private func makeMonitor(
        snapshotProvider: StubSnapshotProvider,
        muteBackend: any AudioMuteBackend = RecordingMuteBackend(),
        backend: any AudioProcessControlBackend,
        store: AppGainStore,
        defaults: UserDefaults,
        audioCaptureAccessState: AudioCaptureAccessState = .granted,
        perAppControlsState: PerAppControlsState = .active
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
            muteBackend: muteBackend,
            processControlBackend: backend,
            outputVolumeController: volumeController,
            appGainStore: store,
            userDefaults: defaults,
            audioCaptureAccessState: audioCaptureAccessState,
            perAppControlsState: perAppControlsState,
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

    func requestAudioCaptureAccess(processObjectID: AudioObjectID) throws {
        throw AudioMonitorError.audioCapturePermissionRequired
    }

    func remove(processObjectID: AudioObjectID) throws {}

    func cleanup() {}
}
