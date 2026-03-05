import CoreAudio
import Foundation
@testable import CodexAudioMonitor

struct StubCodexCommandExecutor: CodexCommandExecuting {
    typealias Handler = @Sendable (_ executable: String, _ arguments: [String], _ timeout: Duration) async throws -> ProcessResult

    let handler: Handler

    func run(
        executable: String,
        arguments: [String],
        timeout: Duration
    ) async throws -> ProcessResult {
        try await handler(executable, arguments, timeout)
    }
}

final class StubSnapshotProvider: AudioProcessSnapshotProviding {
    var currentSnapshots: [AudioProcessSnapshot]

    init(_ snapshots: [AudioProcessSnapshot]) {
        self.currentSnapshots = snapshots
    }

    func snapshots() throws -> [AudioProcessSnapshot] {
        currentSnapshots
    }
}

final class RecordingProcessControlBackend: AudioProcessControlBackend {
    struct Call: Equatable {
        let processObjectID: AudioObjectID
        let muted: Bool
        let gain: Float
    }

    private(set) var applyCalls: [Call] = []
    private(set) var removedProcessIDs: [AudioObjectID] = []

    func apply(processObjectID: AudioObjectID, muted: Bool, gain: Float) throws {
        applyCalls.append(Call(processObjectID: processObjectID, muted: muted, gain: gain))
    }

    func remove(processObjectID: AudioObjectID) throws {
        removedProcessIDs.append(processObjectID)
    }

    func cleanup() {}
}

final class StubOutputVolumeController: AudioOutputVolumeControlling {
    var state: AudioOutputVolumeState
    private(set) var setVolumeCalls: [Float] = []

    init(state: AudioOutputVolumeState) {
        self.state = state
    }

    func currentState() throws -> AudioOutputVolumeState {
        state
    }

    func setVolume(_ value: Float) throws {
        let clamped = min(max(value, 0), 1)
        state = AudioOutputVolumeState(
            volume: clamped,
            canSetVolume: state.canSetVolume,
            deviceName: state.deviceName
        )
        setVolumeCalls.append(clamped)
    }
}

actor FakeCodexIntegrationService: CodexIntegrationService {
    var authStateValue: CodexAuthState = .loggedIn(provider: "OAuth")
    var connectivityReportValue: CodexConnectivityReport = CodexConnectivityReport(
        binaryFound: true,
        authState: .loggedIn(provider: "OAuth"),
        pingOK: true,
        structuredProbeOK: true,
        roundTripMs: 50,
        assistantPreview: "ok",
        errorMessage: nil,
        checkedAt: Date()
    )
    var defaultPlan: CodexActionPlan = CodexActionPlan(
        assistantMessage: "Listo.",
        actions: []
    )
    var plansByMessage: [String: CodexActionPlan] = [:]
    private(set) var receivedMessages: [String] = []

    func setAuthState(_ state: CodexAuthState) {
        authStateValue = state
    }

    func setConnectivityReport(_ report: CodexConnectivityReport) {
        connectivityReportValue = report
    }

    func setDefaultPlan(_ plan: CodexActionPlan) {
        defaultPlan = plan
    }

    func setPlan(_ plan: CodexActionPlan, for message: String) {
        plansByMessage[message] = plan
    }

    func allReceivedMessages() -> [String] {
        receivedMessages
    }

    func authState() async -> CodexAuthState {
        authStateValue
    }

    func ensureLogin() async -> CodexAuthState {
        authStateValue
    }

    func runConnectivityChecks() async -> CodexConnectivityReport {
        connectivityReportValue
    }

    func generateActionPlan(message: String, context: CodexChatContext) async throws -> CodexActionPlan {
        receivedMessages.append(message)
        return plansByMessage[message] ?? defaultPlan
    }
}
