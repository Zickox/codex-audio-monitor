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

final class RecordingMuteBackend: AudioMuteBackend {
    private(set) var mutedProcessIDs: [AudioObjectID] = []
    private(set) var unmutedProcessIDs: [AudioObjectID] = []
    private(set) var cleanupCallCount = 0

    func mute(processObjectID: AudioObjectID) throws {
        mutedProcessIDs.append(processObjectID)
    }

    func unmute(processObjectID: AudioObjectID) throws {
        unmutedProcessIDs.append(processObjectID)
    }

    func cleanup() {
        cleanupCallCount += 1
    }
}

final class RecordingProcessControlBackend: AudioProcessControlBackend {
    struct Call: Equatable {
        let processObjectID: AudioObjectID
        let muted: Bool
        let gain: Float
    }

    private(set) var applyCalls: [Call] = []
    private(set) var permissionProbeProcessIDs: [AudioObjectID] = []
    private(set) var removedProcessIDs: [AudioObjectID] = []

    func apply(processObjectID: AudioObjectID, muted: Bool, gain: Float) throws {
        applyCalls.append(Call(processObjectID: processObjectID, muted: muted, gain: gain))
    }

    func requestAudioCaptureAccess(processObjectID: AudioObjectID) throws {
        permissionProbeProcessIDs.append(processObjectID)
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

struct StubAudioCaptureAccessAuthorizer: AudioCaptureAccessAuthorizing {
    var preflightResult: Bool = true
    var requestResult: Bool = true

    func preflightScreenAndSystemAudioCaptureAccess() -> Bool {
        preflightResult
    }

    func requestScreenAndSystemAudioCaptureAccess() -> Bool {
        requestResult
    }
}

final class RecordingAudioCaptureAccessAuthorizer: AudioCaptureAccessAuthorizing {
    var preflightResult: Bool
    var requestResult: Bool
    private(set) var preflightCallCount = 0
    private(set) var requestCallCount = 0

    init(preflightResult: Bool, requestResult: Bool) {
        self.preflightResult = preflightResult
        self.requestResult = requestResult
    }

    func preflightScreenAndSystemAudioCaptureAccess() -> Bool {
        preflightCallCount += 1
        return preflightResult
    }

    func requestScreenAndSystemAudioCaptureAccess() -> Bool {
        requestCallCount += 1
        return requestResult
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
