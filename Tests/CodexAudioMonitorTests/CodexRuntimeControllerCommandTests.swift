@testable import CodexAudioCore
@testable import CodexAudioMonitor
import CoreAudio
import XCTest

private actor MockCodexService: CodexIntegrationService {
    var currentAuthState: CodexAuthState = .loggedIn(provider: "OAuth")
    var currentAppServerState: CodexAppServerState = .stopped

    func authState() async -> CodexAuthState {
        currentAuthState
    }

    func ensureLogin() async -> CodexAuthState {
        currentAuthState = .loggedIn(provider: "OAuth")
        return currentAuthState
    }

    func startAppServer() async throws {
        currentAppServerState = .running
    }

    func stopAppServer() async {
        currentAppServerState = .stopped
    }

    func send(request: String) async throws -> String {
        "sent"
    }

    func appServerState() async -> CodexAppServerState {
        currentAppServerState
    }
}

private final class ChatMockSnapshotProvider: AudioProcessSnapshotProviding {
    var snapshotsValue: [AudioProcessSnapshot]

    init(snapshotsValue: [AudioProcessSnapshot]) {
        self.snapshotsValue = snapshotsValue
    }

    func snapshots() throws -> [AudioProcessSnapshot] {
        snapshotsValue
    }
}

private final class ChatMockMuteBackend: AudioMuteBackend {
    func mute(processObjectID: AudioObjectID) throws {}
    func unmute(processObjectID: AudioObjectID) throws {}
    func cleanup() {}
}

private final class ChatMockOutputVolumeController: AudioOutputVolumeControlling {
    var currentStateValue = AudioOutputVolumeState(volume: 0.5, canSetVolume: true, deviceName: "Mock Output")

    func currentState() throws -> AudioOutputVolumeState {
        currentStateValue
    }

    func setVolume(_ value: Float) throws {
        currentStateValue = AudioOutputVolumeState(
            volume: value,
            canSetVolume: currentStateValue.canSetVolume,
            deviceName: currentStateValue.deviceName
        )
    }
}

@MainActor
final class CodexRuntimeControllerCommandTests: XCTestCase {
    func testMuteAllCommandMutesEverySession() async {
        let provider = ChatMockSnapshotProvider(
            snapshotsValue: [
                AudioProcessSnapshot(processObjectID: 11, pid: 1001, bundleID: "com.spotify.client", isRunningOutput: true),
                AudioProcessSnapshot(processObjectID: 12, pid: 1002, bundleID: "com.apple.Safari", isRunningOutput: true)
            ]
        )
        let monitor = AudioProcessMonitor(
            snapshotProvider: provider,
            muteBackend: ChatMockMuteBackend(),
            outputVolumeController: ChatMockOutputVolumeController(),
            pollInterval: .seconds(60)
        )
        monitor.refresh()

        let runtime = CodexRuntimeController(service: MockCodexService())
        _ = await runtime.handleChatCommand("mutea todo los sonidos", monitor: monitor)

        XCTAssertTrue(monitor.sessions.allSatisfy(\.isMuted))
    }

    func testUnmuteSpecificAppCommand() async {
        let provider = ChatMockSnapshotProvider(
            snapshotsValue: [
                AudioProcessSnapshot(processObjectID: 21, pid: 2001, bundleID: "com.spotify.client", isRunningOutput: true),
                AudioProcessSnapshot(processObjectID: 22, pid: 2002, bundleID: "com.apple.Safari", isRunningOutput: true)
            ]
        )
        let monitor = AudioProcessMonitor(
            snapshotProvider: provider,
            muteBackend: ChatMockMuteBackend(),
            outputVolumeController: ChatMockOutputVolumeController(),
            pollInterval: .seconds(60)
        )
        monitor.refresh()
        monitor.setAllMuted(true)

        let runtime = CodexRuntimeController(service: MockCodexService())
        _ = await runtime.handleChatCommand("desmutea spotify", monitor: monitor)

        let spotify = monitor.sessions.first { $0.bundleID == "com.spotify.client" }
        let safari = monitor.sessions.first { $0.bundleID == "com.apple.Safari" }
        XCTAssertEqual(spotify?.isMuted, false)
        XCTAssertEqual(safari?.isMuted, true)
    }

    func testVolumePercentageCommandUpdatesVolume() async {
        let provider = ChatMockSnapshotProvider(snapshotsValue: [])
        let volumeController = ChatMockOutputVolumeController()
        let monitor = AudioProcessMonitor(
            snapshotProvider: provider,
            muteBackend: ChatMockMuteBackend(),
            outputVolumeController: volumeController,
            pollInterval: .seconds(60)
        )

        let runtime = CodexRuntimeController(service: MockCodexService())
        _ = await runtime.handleChatCommand("volumen 35", monitor: monitor)

        XCTAssertEqual(monitor.outputVolume, 0.35, accuracy: 0.001)
    }
}
