import CoreAudio
import XCTest
@testable import CodexAudioMonitor

@MainActor
final class CodexRuntimeControllerTests: XCTestCase {
    func testHandleChatCommandAppliesMuteAllAndVolumeActions() async {
        let service = FakeCodexIntegrationService()
        await service.setAuthState(.loggedIn(provider: "OAuth"))
        await service.setPlan(
            CodexActionPlan(
                assistantMessage: "Aplicando cambios",
                actions: [
                    CodexAction(type: .muteAll, sessionID: nil, volumePercent: nil, gainPercent: nil),
                    CodexAction(type: .setVolume, sessionID: nil, volumePercent: 35, gainPercent: nil)
                ]
            ),
            for: "mutea todo"
        )

        let monitor = makeMonitor()
        let runtime = CodexRuntimeController(service: service)

        let response = await runtime.handleChatCommand("mutea todo", monitor: monitor)

        XCTAssertTrue(monitor.sessions.allSatisfy(\.isMuted))
        XCTAssertEqual(Int(monitor.outputVolume * 100), 35)
        XCTAssertTrue(response.contains("Volumen ajustado"))
    }

    func testHolaCommandDoesNotApplyDestructiveActions() async {
        let service = FakeCodexIntegrationService()
        await service.setAuthState(.loggedIn(provider: "OAuth"))
        await service.setPlan(
            CodexActionPlan(
                assistantMessage: "Hola, ¿en qué te ayudo?",
                actions: [CodexAction(type: .none, sessionID: nil, volumePercent: nil, gainPercent: nil)]
            ),
            for: "hola"
        )

        let monitor = makeMonitor()
        monitor.refresh()
        let initialMuted = monitor.sessions.map(\.isMuted)
        let initialVolume = monitor.outputVolume

        let runtime = CodexRuntimeController(service: service)
        let response = await runtime.handleChatCommand("hola", monitor: monitor)

        XCTAssertEqual(monitor.sessions.map(\.isMuted), initialMuted)
        XCTAssertEqual(monitor.outputVolume, initialVolume)
        XCTAssertTrue(response.localizedCaseInsensitiveContains("hola"))
    }

    func testHandleChatCommandAppliesSessionGainAction() async {
        let service = FakeCodexIntegrationService()
        await service.setAuthState(.loggedIn(provider: "OAuth"))
        await service.setPlan(
            CodexActionPlan(
                assistantMessage: "Ajustando gain",
                actions: [
                    CodexAction(
                        type: .setSessionGain,
                        sessionID: "bundle:com.spotify.client",
                        volumePercent: nil,
                        gainPercent: 30
                    )
                ]
            ),
            for: "spotify 30%"
        )

        let monitor = makeMonitor()
        monitor.refresh()
        let runtime = CodexRuntimeController(service: service)

        let response = await runtime.handleChatCommand("spotify 30%", monitor: monitor)
        let spotify = monitor.sessions.first { $0.id == "bundle:com.spotify.client" }

        XCTAssertNotNil(spotify)
        if let spotify {
            XCTAssertEqual(spotify.appGain, 0.3, accuracy: 0.001)
        }
        XCTAssertTrue(response.contains("Ajusté"))
    }

    func testCheckConnectivityStoresReportAndMessage() async {
        let service = FakeCodexIntegrationService()
        await service.setAuthState(.loggedIn(provider: "OAuth"))
        await service.setConnectivityReport(
            CodexConnectivityReport(
                binaryFound: true,
                authState: .loggedIn(provider: "OAuth"),
                pingOK: true,
                structuredProbeOK: true,
                roundTripMs: 88,
                assistantPreview: "ok",
                errorMessage: nil,
                checkedAt: Date()
            )
        )

        let runtime = CodexRuntimeController(service: service)
        await runtime.checkConnectivity()

        XCTAssertNotNil(runtime.connectivityReport)
        XCTAssertEqual(runtime.authState, .loggedIn(provider: "OAuth"))
        XCTAssertEqual(runtime.connectivityReport?.roundTripMs, 88)
        XCTAssertEqual(runtime.lastMessage, "Codex conectado (88 ms).")
    }

    private func makeMonitor() -> AudioProcessMonitor {
        let snapshotProvider = StubSnapshotProvider([
            AudioProcessSnapshot(
                processObjectID: AudioObjectID(101),
                pid: 1201,
                bundleID: "com.spotify.client",
                isRunningOutput: true
            ),
            AudioProcessSnapshot(
                processObjectID: AudioObjectID(102),
                pid: 1202,
                bundleID: "com.apple.Safari",
                isRunningOutput: true
            )
        ])

        let processControlBackend = RecordingProcessControlBackend()
        let outputController = StubOutputVolumeController(
            state: AudioOutputVolumeState(
                volume: 0.6,
                canSetVolume: true,
                deviceName: "Test Device"
            )
        )

        return AudioProcessMonitor(
            snapshotProvider: snapshotProvider,
            processControlBackend: processControlBackend,
            outputVolumeController: outputController,
            pollInterval: .seconds(5)
        )
    }
}
