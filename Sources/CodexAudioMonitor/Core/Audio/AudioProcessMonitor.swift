import AppKit
import CoreAudio
import Foundation
import Observation

@MainActor
@Observable
public final class AudioProcessMonitor: AudioMonitoringService {
    private static let perAppGainEnabledKey = "audio.perAppGain.enabled"

    public private(set) var sessions: [AudioSession] = []
    public private(set) var errorMessage: String?
    public private(set) var lastRefresh = Date.distantPast
    public private(set) var outputVolume: Float = 0.5
    public private(set) var canControlOutputVolume = false
    public private(set) var outputDeviceName = "System Output"
    public private(set) var isPerAppGainEnabled: Bool
    public private(set) var audioCaptureAccessState: AudioCaptureAccessState
    public private(set) var perAppControlsState: PerAppControlsState

    private let snapshotProvider: AudioProcessSnapshotProviding
    private let muteBackend: AudioMuteBackend
    private let processControlBackend: AudioProcessControlBackend
    private let outputVolumeController: AudioOutputVolumeControlling
    private let appGainStore: AppGainStore
    private let userDefaults: UserDefaults
    private let pollInterval: Duration

    private var mutedSessionIDs = Set<String>()
    private var sessionGainByID: [String: Float] = [:]
    private var sessionLastSeenByID: [String: Date] = [:]
    private var previousMutedProcessObjectIDs = Set<AudioObjectID>()
    private var previousGainProcessObjectIDs = Set<AudioObjectID>()
    private var refreshTask: Task<Void, Never>?

    public init(pollInterval: Duration = .seconds(1)) {
        self.snapshotProvider = CoreAudioProcessSnapshotProvider()
        self.muteBackend = CoreAudioTapMuteBackend()
        self.processControlBackend = AppGainServiceClient()
        self.outputVolumeController = CoreAudioOutputVolumeController()
        self.appGainStore = AppGainStore()
        self.userDefaults = .standard
        self.isPerAppGainEnabled = Self.loadPerAppGainEnabled(from: .standard)
        self.audioCaptureAccessState = .unknown
        self.perAppControlsState = .inactive
        self.pollInterval = pollInterval
        refreshOutputVolume()
    }

    init(
        snapshotProvider: AudioProcessSnapshotProviding = CoreAudioProcessSnapshotProvider(),
        muteBackend: AudioMuteBackend = CoreAudioTapMuteBackend(),
        processControlBackend: AudioProcessControlBackend = AppGainServiceClient(),
        outputVolumeController: AudioOutputVolumeControlling = CoreAudioOutputVolumeController(),
        appGainStore: AppGainStore = AppGainStore(),
        userDefaults: UserDefaults = .standard,
        audioCaptureAccessState: AudioCaptureAccessState = .unknown,
        perAppControlsState: PerAppControlsState = .inactive,
        pollInterval: Duration = .seconds(1)
    ) {
        self.snapshotProvider = snapshotProvider
        self.muteBackend = muteBackend
        self.processControlBackend = processControlBackend
        self.outputVolumeController = outputVolumeController
        self.appGainStore = appGainStore
        self.userDefaults = userDefaults
        self.isPerAppGainEnabled = Self.loadPerAppGainEnabled(from: userDefaults)
        self.audioCaptureAccessState = audioCaptureAccessState
        self.perAppControlsState = perAppControlsState
        self.pollInterval = pollInterval
        refreshOutputVolume()
    }

    public func start() {
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            guard let self else { return }
            await self.refreshLoop()
        }
    }

    public func stop() {
        refreshTask?.cancel()
        refreshTask = nil
        muteBackend.cleanup()
        processControlBackend.cleanup()
        previousMutedProcessObjectIDs.removeAll()
        previousGainProcessObjectIDs.removeAll()
    }

    public func refresh() {
        refreshOutputVolume()

        do {
            let snapshots = try snapshotProvider.snapshots()
            var activeSessions = buildSessions(from: snapshots)
            try reconcileMuteState(with: activeSessions)
            sessions = activeSessions
            lastRefresh = Date()

            guard perAppControlsState == .active else {
                sessions = activeSessions
                errorMessage = nil
                syncInactiveProcessControl()
                return
            }

            do {
                try reconcileProcessControl(with: &activeSessions)
                sessions = activeSessions
                errorMessage = nil
            } catch let error as AudioMonitorError where error == .appGainUnavailable || error == .audioCapturePermissionRequired {
                sessions = activeSessions
                errorMessage = nil
            } catch {
                sessions = activeSessions
                errorMessage = "No se pudo refrescar audio: \(error.localizedDescription)"
            }
        } catch {
            errorMessage = "No se pudo refrescar audio: \(error.localizedDescription)"
        }
    }

    public func toggleMute(sessionID: String) {
        guard sessions.contains(where: { $0.id == sessionID }) else {
            errorMessage = AudioMonitorError.sessionNotFound(sessionID).localizedDescription
            return
        }

        if mutedSessionIDs.contains(sessionID) {
            mutedSessionIDs.remove(sessionID)
        } else {
            mutedSessionIDs.insert(sessionID)
        }
        refresh()
    }

    public func setMuted(sessionID: String, muted: Bool) {
        guard sessions.contains(where: { $0.id == sessionID }) else {
            errorMessage = AudioMonitorError.sessionNotFound(sessionID).localizedDescription
            return
        }

        if muted {
            mutedSessionIDs.insert(sessionID)
        } else {
            mutedSessionIDs.remove(sessionID)
        }
        refresh()
    }

    public func setAllMuted(_ muted: Bool) {
        let sessionIDs = sessions.map(\.id)
        if muted {
            mutedSessionIDs.formUnion(sessionIDs)
        } else {
            mutedSessionIDs.subtract(sessionIDs)
        }
        refresh()
    }

    public func solo(sessionID: String) {
        guard sessions.contains(where: { $0.id == sessionID }) else {
            errorMessage = AudioMonitorError.sessionNotFound(sessionID).localizedDescription
            return
        }

        mutedSessionIDs = Set(sessions.map(\.id))
        mutedSessionIDs.remove(sessionID)
        refresh()
    }

    public func muteOthers(except sessionID: String) {
        guard sessions.contains(where: { $0.id == sessionID }) else {
            errorMessage = AudioMonitorError.sessionNotFound(sessionID).localizedDescription
            return
        }

        let otherSessionIDs = sessions
            .map(\.id)
            .filter { $0 != sessionID }

        mutedSessionIDs.formUnion(otherSessionIDs)
        refresh()
    }

    public func setSessionGain(sessionID: String, gain: Float) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else {
            errorMessage = AudioMonitorError.sessionNotFound(sessionID).localizedDescription
            return
        }

        let clamped = clampGain(gain)
        sessionGainByID[sessionID] = clamped
        sessions[index].appGain = clamped

        if let bundleID = sessions[index].bundleID {
            if clamped >= 0.999 {
                appGainStore.removeGain(for: bundleID)
            } else {
                appGainStore.setGain(clamped, for: bundleID)
            }
        }

        guard perAppControlsState == .active else {
            errorMessage = nil
            return
        }

        applyProcessControlForSession(at: index)
    }

    public func setAllSessionGains(_ gain: Float) {
        let clamped = clampGain(gain)
        for index in sessions.indices {
            let session = sessions[index]
            sessionGainByID[session.id] = clamped
            sessions[index].appGain = clamped
            if let bundleID = session.bundleID {
                if clamped >= 0.999 {
                    appGainStore.removeGain(for: bundleID)
                } else {
                    appGainStore.setGain(clamped, for: bundleID)
                }
            }
            applyProcessControlForSession(at: index)
        }
    }

    public func restoreAllSessionGains() {
        setAllSessionGains(1)
    }

    public func setPerAppGainEnabled(_ enabled: Bool) {
        isPerAppGainEnabled = enabled
        userDefaults.set(enabled, forKey: Self.perAppGainEnabledKey)
        errorMessage = nil
        if perAppControlsState == .active {
            refresh()
        }
    }

    public func requestPerAppControlsActivation() {
        errorMessage = nil

        if sessions.isEmpty {
            refresh()
        }

        _ = activatePerAppControlsIfNeeded(
            processObjectID: sessions.first(where: { !$0.processObjectIDs.isEmpty })?.processObjectIDs.first,
            refreshAfterActivation: true
        )
    }

    public func deactivatePerAppControls() {
        perAppControlsState = .inactive
        processControlBackend.cleanup()
        previousGainProcessObjectIDs.removeAll()
    }

    public func toggleMute(for session: AudioSession) {
        toggleMute(sessionID: session.id)
    }

    public func refreshOutputVolume() {
        do {
            let state = try outputVolumeController.currentState()
            outputVolume = state.volume
            canControlOutputVolume = state.canSetVolume
            outputDeviceName = state.deviceName
        } catch {
            canControlOutputVolume = false
        }
    }

    public func setOutputVolume(_ value: Float) {
        let clamped = max(0, min(1, value))
        do {
            try outputVolumeController.setVolume(clamped)
            outputVolume = clamped
            canControlOutputVolume = true
        } catch {
            refreshOutputVolume()
        }
    }

    public func stepOutputVolume(by delta: Float) {
        setOutputVolume(outputVolume + delta)
    }

    private func refreshLoop() async {
        refresh()

        while !Task.isCancelled {
            try? await Task.sleep(for: pollInterval)
            refresh()
        }
    }

    private func buildSessions(from snapshots: [AudioProcessSnapshot]) -> [AudioSession] {
        struct SessionAccumulator {
            var id: String
            var displayName: String
            var bundleID: String?
            var pids = Set<pid_t>()
            var processObjectIDs = Set<AudioObjectID>()
        }

        var byID: [String: SessionAccumulator] = [:]
        let now = Date()

        for snapshot in snapshots where snapshot.isRunningOutput {
            let sessionID = makeSessionID(bundleID: snapshot.bundleID, pid: snapshot.pid)

            if var existing = byID[sessionID] {
                existing.pids.insert(snapshot.pid)
                existing.processObjectIDs.insert(snapshot.processObjectID)
                byID[sessionID] = existing
            } else {
                var entry = SessionAccumulator(
                    id: sessionID,
                    displayName: resolveDisplayName(bundleID: snapshot.bundleID, pid: snapshot.pid),
                    bundleID: snapshot.bundleID
                )
                entry.pids.insert(snapshot.pid)
                entry.processObjectIDs.insert(snapshot.processObjectID)
                byID[sessionID] = entry
            }

            sessionLastSeenByID[sessionID] = now
        }

        let activeIDs = Set(byID.keys)
        mutedSessionIDs = mutedSessionIDs.intersection(activeIDs)
        sessionGainByID = sessionGainByID.filter { activeIDs.contains($0.key) }
        sessionLastSeenByID = sessionLastSeenByID.filter { activeIDs.contains($0.key) }

        return sortSessions(
            byID.values
            .map { value in
                let appGain = resolvedGain(for: value.id, bundleID: value.bundleID)
                return AudioSession(
                    id: value.id,
                    displayName: value.displayName,
                    bundleID: value.bundleID,
                    pids: value.pids.sorted(),
                    processObjectIDs: value.processObjectIDs.sorted(),
                    isMuted: mutedSessionIDs.contains(value.id),
                    appGain: appGain,
                    isAppGainAvailable: true,
                    lastSeenAt: sessionLastSeenByID[value.id] ?? now
                )
            }
        )
    }

    private func reconcileMuteState(with activeSessions: [AudioSession]) throws {
        let mutedProcessObjectIDs = Set(
            activeSessions
                .filter(\.isMuted)
                .flatMap(\.processObjectIDs)
        )

        let processObjectIDsToUnmute = previousMutedProcessObjectIDs.subtracting(mutedProcessObjectIDs)
        var firstError: Error?

        for processObjectID in processObjectIDsToUnmute {
            do {
                try muteBackend.unmute(processObjectID: processObjectID)
            } catch {
                if firstError == nil {
                    firstError = error
                }
            }
        }

        for processObjectID in mutedProcessObjectIDs {
            do {
                try muteBackend.mute(processObjectID: processObjectID)
            } catch {
                if firstError == nil {
                    firstError = error
                }
            }
        }

        previousMutedProcessObjectIDs = mutedProcessObjectIDs

        if let firstError {
            throw firstError
        }
    }

    private func reconcileProcessControl(with activeSessions: inout [AudioSession]) throws {
        let currentProcessObjectIDs = Set(
            activeSessions
                .filter { shouldApplyGainControl(for: $0) }
                .flatMap(\.processObjectIDs)
        )
        let removedProcessObjectIDs = previousGainProcessObjectIDs.subtracting(currentProcessObjectIDs)

        var firstError: Error?

        for processObjectID in removedProcessObjectIDs {
            do {
                try processControlBackend.remove(processObjectID: processObjectID)
            } catch {
                if firstError == nil {
                    firstError = error
                }
            }
        }

        struct ProcessState {
            let sessionID: String
            let gain: Float
        }

        let desiredStateByProcessObjectID = Dictionary(
            uniqueKeysWithValues: activeSessions
                .filter { shouldApplyGainControl(for: $0) }
                .flatMap { session in
                    session.processObjectIDs.map { processObjectID in
                        (
                            processObjectID,
                            ProcessState(
                                sessionID: session.id,
                                gain: effectiveGain(for: session)
                            )
                        )
                    }
                }
        )

        for (processObjectID, state) in desiredStateByProcessObjectID {
            do {
                try processControlBackend.apply(
                    processObjectID: processObjectID,
                    muted: false,
                    gain: state.gain
                )
            } catch let error as AudioMonitorError where error == .appGainUnavailable || error == .audioCapturePermissionRequired {
                if let index = activeSessions.firstIndex(where: { $0.id == state.sessionID }) {
                    activeSessions[index].isAppGainAvailable = false
                }

                if error == .audioCapturePermissionRequired {
                    handlePermissionDenial(in: &activeSessions)
                    firstError = error
                    break
                }

                if firstError == nil {
                    firstError = error
                }

                do {
                    try processControlBackend.remove(processObjectID: processObjectID)
                } catch {
                    if firstError == nil {
                        firstError = error
                    }
                }
            } catch {
                if firstError == nil {
                    firstError = error
                }
            }
        }

        previousGainProcessObjectIDs = perAppControlsState == .active ? currentProcessObjectIDs : []

        if let firstError {
            throw firstError
        }
    }

    private func makeSessionID(bundleID: String?, pid: pid_t) -> String {
        if let bundleID, !bundleID.isEmpty {
            return "bundle:\(bundleID)"
        }
        return "pid:\(pid)"
    }

    private func resolveDisplayName(bundleID: String?, pid: pid_t) -> String {
        if let app = NSRunningApplication(processIdentifier: pid),
           let localizedName = app.localizedName,
           !localizedName.isEmpty {
            return localizedName
        }

        if let bundleID, !bundleID.isEmpty {
            return bundleID
        }

        return "PID \(pid)"
    }

    private func resolvedGain(for sessionID: String, bundleID: String?) -> Float {
        if let existing = sessionGainByID[sessionID] {
            return clampGain(existing)
        }

        if let bundleID,
           let persisted = appGainStore.gain(for: bundleID)
        {
            let clamped = clampGain(persisted)
            sessionGainByID[sessionID] = clamped
            return clamped
        }

        sessionGainByID[sessionID] = 1
        return 1
    }

    private func clampGain(_ value: Float) -> Float {
        min(max(value, 0), 1)
    }

    private func sortSessions(_ sessions: [AudioSession]) -> [AudioSession] {
        sessions.sorted { lhs, rhs in
            if lhs.isMuted != rhs.isMuted {
                return !lhs.isMuted
            }

            if lhs.lastSeenAt != rhs.lastSeenAt {
                return lhs.lastSeenAt > rhs.lastSeenAt
            }

            let lhsHasCustomGain = lhs.appGain < 0.999
            let rhsHasCustomGain = rhs.appGain < 0.999
            if lhsHasCustomGain != rhsHasCustomGain {
                return lhsHasCustomGain
            }

            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    private func applyProcessControlForSession(at index: Int) {
        guard sessions.indices.contains(index) else { return }
        guard perAppControlsState == .active else {
            errorMessage = nil
            return
        }

        let session = sessions[index]
        var firstError: Error?
        let effectiveGain = effectiveGain(for: session)

        for processObjectID in session.processObjectIDs {
            guard shouldApplyGainControl(for: session) else {
                do {
                    try processControlBackend.remove(processObjectID: processObjectID)
                } catch {
                    if firstError == nil {
                        firstError = error
                    }
                }
                continue
            }

            do {
                try processControlBackend.apply(
                    processObjectID: processObjectID,
                    muted: false,
                    gain: effectiveGain
                )
            } catch AudioMonitorError.appGainUnavailable {
                sessions[index].isAppGainAvailable = false

                do {
                    try processControlBackend.remove(processObjectID: processObjectID)
                } catch {
                    if firstError == nil {
                        firstError = error
                    }
                }
            } catch AudioMonitorError.audioCapturePermissionRequired {
                sessions[index].isAppGainAvailable = false
                handlePermissionDenial()
                firstError = AudioMonitorError.audioCapturePermissionRequired
                break
            } catch {
                if firstError == nil {
                    firstError = error
                }
            }
        }

        if let firstError {
            if let monitorError = firstError as? AudioMonitorError,
               monitorError == .appGainUnavailable || monitorError == .audioCapturePermissionRequired {
                errorMessage = nil
            } else {
                errorMessage = "No se pudo aplicar App Gain: \(firstError.localizedDescription)"
            }
        } else {
            errorMessage = nil
        }
    }

    private func effectiveGain(for session: AudioSession) -> Float {
        guard perAppControlsState == .active, isPerAppGainEnabled, !session.isMuted else {
            return 1.0
        }
        return session.appGain
    }

    private func shouldApplyGainControl(for session: AudioSession) -> Bool {
        effectiveGain(for: session) < 0.999
    }

    @discardableResult
    private func activatePerAppControlsIfNeeded(
        processObjectID: AudioObjectID?,
        refreshAfterActivation: Bool
    ) -> Bool {
        if perAppControlsState == .active {
            return true
        }

        guard let processObjectID else {
            return false
        }

        do {
            try processControlBackend.requestAudioCaptureAccess(processObjectID: processObjectID)
            audioCaptureAccessState = .granted
            perAppControlsState = .active
            if refreshAfterActivation {
                refresh()
            }
            return true
        } catch AudioMonitorError.audioCapturePermissionRequired {
            audioCaptureAccessState = .denied
            deactivatePerAppControls()
            errorMessage = nil
            return false
        } catch {
            perAppControlsState = .inactive
            errorMessage = "No se pudieron activar los controles por app: \(error.localizedDescription)"
            return false
        }
    }

    private func syncInactiveProcessControl() {
        guard previousGainProcessObjectIDs.isEmpty == false else { return }
        processControlBackend.cleanup()
        previousGainProcessObjectIDs.removeAll()
    }

    private func handlePermissionDenial(in activeSessions: inout [AudioSession]) {
        audioCaptureAccessState = .denied
        deactivatePerAppControls()
        errorMessage = nil
    }

    private func handlePermissionDenial() {
        audioCaptureAccessState = .denied
        deactivatePerAppControls()
        errorMessage = nil
    }

    private static func loadPerAppGainEnabled(from userDefaults: UserDefaults) -> Bool {
        if userDefaults.object(forKey: perAppGainEnabledKey) == nil {
            return false
        }
        return userDefaults.bool(forKey: perAppGainEnabledKey)
    }
}
