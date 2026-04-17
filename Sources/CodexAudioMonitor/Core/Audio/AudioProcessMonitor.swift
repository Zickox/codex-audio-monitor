import AppKit
import CoreAudio
import CoreGraphics
import Foundation
import Observation
import OSLog

@MainActor
@Observable
public final class AudioProcessMonitor: AudioMonitoringService {
    private static let perAppGainEnabledKey = "audio.perAppGain.enabled"
    private static let audioCaptureAccessStateKey = "audio.perAppGain.accessState"

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
    private let captureAccessAuthorizer: AudioCaptureAccessAuthorizing
    private let outputVolumeController: AudioOutputVolumeControlling
    private let appGainStore: AppGainStore
    private let userDefaults: UserDefaults
    private let pollInterval: Duration
    private let logger = Logger(subsystem: "com.zickox.codexaudiomonitor", category: "AudioProcessMonitor")

    private var mutedSessionIDs = Set<String>()
    private var sessionGainByID: [String: Float] = [:]
    private var sessionLastSeenByID: [String: Date] = [:]
    private var previousMuteProcessObjectIDs = Set<AudioObjectID>()
    private var previousGainProcessObjectIDs = Set<AudioObjectID>()
    private var refreshTask: Task<Void, Never>?

    public init(pollInterval: Duration = .seconds(1)) {
        let defaults = UserDefaults.standard
        let enabled = defaults.bool(forKey: Self.perAppGainEnabledKey)
        let persistedAccessState = Self.loadAccessState(from: defaults)
        let accessState: AudioCaptureAccessState = persistedAccessState == .denied ? .denied : .unknown

        self.snapshotProvider = CoreAudioProcessSnapshotProvider()
        self.muteBackend = CoreAudioTapMuteBackend()
        self.processControlBackend = AppGainServiceClient()
        self.captureAccessAuthorizer = ScreenAndSystemAudioCaptureAuthorizer()
        self.outputVolumeController = CoreAudioOutputVolumeController()
        self.appGainStore = AppGainStore()
        self.userDefaults = defaults
        self.isPerAppGainEnabled = enabled
        self.audioCaptureAccessState = accessState
        self.perAppControlsState = .inactive
        self.pollInterval = pollInterval
        persistAccessState(accessState)
        refreshOutputVolume()
    }

    init(
        snapshotProvider: AudioProcessSnapshotProviding = CoreAudioProcessSnapshotProvider(),
        muteBackend: AudioMuteBackend = CoreAudioTapMuteBackend(),
        processControlBackend: AudioProcessControlBackend = AppGainServiceClient(),
        captureAccessAuthorizer: AudioCaptureAccessAuthorizing = ScreenAndSystemAudioCaptureAuthorizer(),
        outputVolumeController: AudioOutputVolumeControlling = CoreAudioOutputVolumeController(),
        appGainStore: AppGainStore = AppGainStore(),
        userDefaults: UserDefaults = .standard,
        audioCaptureAccessState: AudioCaptureAccessState = .unknown,
        perAppControlsState: PerAppControlsState = .inactive,
        pollInterval: Duration = .seconds(1)
    ) {
        let enabled = userDefaults.bool(forKey: Self.perAppGainEnabledKey)

        self.snapshotProvider = snapshotProvider
        self.muteBackend = muteBackend
        self.processControlBackend = processControlBackend
        self.captureAccessAuthorizer = captureAccessAuthorizer
        self.outputVolumeController = outputVolumeController
        self.appGainStore = appGainStore
        self.userDefaults = userDefaults
        self.isPerAppGainEnabled = enabled
        self.audioCaptureAccessState = audioCaptureAccessState
        self.perAppControlsState = enabled ? perAppControlsState : .inactive
        self.pollInterval = pollInterval
        persistAccessState(audioCaptureAccessState)
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
        deactivatePerAppControlPathIfNeeded()
    }

    public func refresh() {
        refreshOutputVolume()

        do {
            let snapshots = try snapshotProvider.snapshots()
            var activeSessions = buildSessions(from: snapshots)

            try reconcileMuteState(with: activeSessions)
            try reconcilePerAppGainState(with: &activeSessions)

            sessions = sortSessions(activeSessions)
            lastRefresh = Date()
            errorMessage = nil
        } catch {
            sessions = sortSessions(sessions)
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
        let session = sessions[index]

        sessionGainByID[sessionID] = clamped
        sessions[index].appGain = clamped

        if let bundleID = session.bundleID {
            if clamped >= 0.999 {
                appGainStore.removeGain(for: bundleID)
            } else {
                appGainStore.setGain(clamped, for: bundleID)
            }
        }

        guard shouldApplyPerAppGain else { return }
        applyPerAppGainForSession(sessionID: sessionID)
    }

    public func setAllSessionGains(_ gain: Float) {
        let clamped = clampGain(gain)

        for index in sessions.indices {
            let sessionID = sessions[index].id
            sessionGainByID[sessionID] = clamped
            sessions[index].appGain = clamped

            if let bundleID = sessions[index].bundleID {
                if clamped >= 0.999 {
                    appGainStore.removeGain(for: bundleID)
                } else {
                    appGainStore.setGain(clamped, for: bundleID)
                }
            }
        }

        guard shouldApplyPerAppGain else { return }
        for session in sessions {
            applyPerAppGainForSession(sessionID: session.id)
        }
    }

    public func restoreAllSessionGains() {
        setAllSessionGains(1)
    }

    public func setPerAppGainEnabled(_ enabled: Bool) {
        logger.notice("setPerAppGainEnabled(enabled: \(enabled, privacy: .public)) state=\(String(describing: self.audioCaptureAccessState), privacy: .public)")
        if !enabled {
            isPerAppGainEnabled = false
            userDefaults.set(false, forKey: Self.perAppGainEnabledKey)
            perAppControlsState = .inactive
            errorMessage = nil
            deactivatePerAppControlPathIfNeeded()
            return
        }

        guard audioCaptureAccessState != .denied else {
            isPerAppGainEnabled = false
            userDefaults.set(false, forKey: Self.perAppGainEnabledKey)
            perAppControlsState = .inactive
            errorMessage = "Permiso denegado. Usa Open System Settings para habilitar App Gain."
            return
        }

        isPerAppGainEnabled = true
        userDefaults.set(true, forKey: Self.perAppGainEnabledKey)
        requestPerAppControlsActivation()
    }

    public func requestPerAppControlsActivation() {
        logger.notice(
            "requestPerAppControlsActivation enabled=\(self.isPerAppGainEnabled, privacy: .public) access=\(String(describing: self.audioCaptureAccessState), privacy: .public) sessions=\(self.sessions.count, privacy: .public)"
        )
        guard isPerAppGainEnabled else {
            errorMessage = "Activa App Gain primero."
            logger.error("requestPerAppControlsActivation rejected: App Gain not enabled")
            return
        }

        guard audioCaptureAccessState != .denied else {
            perAppControlsState = .inactive
            errorMessage = "Permiso denegado. Usa Open System Settings y Retry Permission."
            logger.error("requestPerAppControlsActivation rejected: access state denied")
            return
        }

        // Explicit system permission gate: this is the only place where we ask macOS.
        let preflightGranted = captureAccessAuthorizer.preflightScreenAndSystemAudioCaptureAccess()
        if !preflightGranted {
            logger.notice("App Gain permission preflight denied, requesting access")
            let requestGranted = captureAccessAuthorizer.requestScreenAndSystemAudioCaptureAccess()
            logger.notice("App Gain permission request result granted=\(requestGranted, privacy: .public)")
            guard requestGranted else {
                audioCaptureAccessState = .denied
                persistAccessState(.denied)
                perAppControlsState = .inactive
                isPerAppGainEnabled = false
                userDefaults.set(false, forKey: Self.perAppGainEnabledKey)
                deactivatePerAppControlPathIfNeeded()
                errorMessage = nil
                return
            }
        }

        let candidateProcessObjectIDs = permissionProbeCandidates()
        guard !candidateProcessObjectIDs.isEmpty else {
            perAppControlsState = .inactive
            errorMessage = "Start audio in another app first."
            logger.error("requestPerAppControlsActivation rejected: no probe candidates")
            return
        }

        var sawUnavailable = false
        var sawUnknownFailure = false

        for processObjectID in candidateProcessObjectIDs {
            do {
                logger.notice("probing App Gain permission with processObjectID=\(processObjectID, privacy: .public)")
                try processControlBackend.requestAudioCaptureAccess(processObjectID: processObjectID)
                try processControlBackend.apply(
                    processObjectID: processObjectID,
                    muted: false,
                    gain: 0.95
                )
                try processControlBackend.remove(processObjectID: processObjectID)
                audioCaptureAccessState = .granted
                persistAccessState(.granted)
                perAppControlsState = .active
                errorMessage = nil
                logger.notice("App Gain activation probe succeeded for processObjectID=\(processObjectID, privacy: .public)")
                refresh()
                return
            } catch let error as AudioMonitorError where error == .audioCapturePermissionRequired {
                audioCaptureAccessState = .denied
                persistAccessState(.denied)
                perAppControlsState = .inactive
                isPerAppGainEnabled = false
                userDefaults.set(false, forKey: Self.perAppGainEnabledKey)
                deactivatePerAppControlPathIfNeeded()
                errorMessage = nil
                logger.error("App Gain activation probe denied by system for processObjectID=\(processObjectID, privacy: .public)")
                return
            } catch let error as AudioMonitorError where error == .appGainUnavailable {
                sawUnavailable = true
                logger.warning("App Gain activation probe unavailable for processObjectID=\(processObjectID, privacy: .public)")
            } catch {
                sawUnknownFailure = true
                logger.error("App Gain activation probe failed for processObjectID=\(processObjectID, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }

        perAppControlsState = .inactive
        if sawUnavailable {
            errorMessage = "App Gain no está disponible para la app de audio actual."
        } else if sawUnknownFailure {
            errorMessage = "No se pudo validar permisos de App Gain."
        } else {
            errorMessage = "Start audio in another app first."
        }
    }

    public func deactivatePerAppControls() {
        perAppControlsState = .inactive
        deactivatePerAppControlPathIfNeeded()
    }

    public func clearDeniedAppGainState() {
        guard audioCaptureAccessState == .denied else { return }
        audioCaptureAccessState = .unknown
        persistAccessState(.unknown)
        errorMessage = nil
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

        return byID.values.map { value in
            AudioSession(
                id: value.id,
                displayName: value.displayName,
                bundleID: value.bundleID,
                pids: value.pids.sorted(),
                processObjectIDs: value.processObjectIDs.sorted(),
                isMuted: mutedSessionIDs.contains(value.id),
                appGain: resolvedGain(for: value.id, bundleID: value.bundleID),
                isAppGainAvailable: true,
                lastSeenAt: sessionLastSeenByID[value.id] ?? now
            )
        }
    }

    private func reconcileMuteState(with activeSessions: [AudioSession]) throws {
        let currentProcessObjectIDs = Set(activeSessions.flatMap(\.processObjectIDs))
        let removedProcessObjectIDs = previousMuteProcessObjectIDs.subtracting(currentProcessObjectIDs)

        for processObjectID in removedProcessObjectIDs {
            try muteBackend.unmute(processObjectID: processObjectID)
        }

        let mutedProcessObjectIDs = Set(
            activeSessions
                .filter { mutedSessionIDs.contains($0.id) }
                .flatMap(\.processObjectIDs)
        )

        for processObjectID in currentProcessObjectIDs {
            if mutedProcessObjectIDs.contains(processObjectID) {
                try muteBackend.mute(processObjectID: processObjectID)
            } else {
                try muteBackend.unmute(processObjectID: processObjectID)
            }
        }

        previousMuteProcessObjectIDs = currentProcessObjectIDs
    }

    private func reconcilePerAppGainState(with activeSessions: inout [AudioSession]) throws {
        guard shouldApplyPerAppGain else {
            deactivatePerAppControlPathIfNeeded()
            return
        }

        let currentProcessObjectIDs = Set(activeSessions.flatMap(\.processObjectIDs))
        let removedProcessObjectIDs = previousGainProcessObjectIDs.subtracting(currentProcessObjectIDs)

        for processObjectID in removedProcessObjectIDs {
            try? processControlBackend.remove(processObjectID: processObjectID)
        }

        var firstError: Error?
        for index in activeSessions.indices {
            let session = activeSessions[index]
            for processObjectID in session.processObjectIDs {
                do {
                    try processControlBackend.apply(
                        processObjectID: processObjectID,
                        muted: false,
                        gain: session.appGain
                    )
                } catch let error as AudioMonitorError where error == .appGainUnavailable {
                    activeSessions[index].isAppGainAvailable = false
                    if firstError == nil {
                        firstError = error
                    }
                } catch let error as AudioMonitorError where error == .audioCapturePermissionRequired {
                    _ = error
                    audioCaptureAccessState = .denied
                    persistAccessState(.denied)
                    isPerAppGainEnabled = false
                    userDefaults.set(false, forKey: Self.perAppGainEnabledKey)
                    perAppControlsState = .inactive
                    deactivatePerAppControlPathIfNeeded()
                    errorMessage = nil
                    return
                } catch {
                    if firstError == nil {
                        firstError = error
                    }
                }
            }
        }

        previousGainProcessObjectIDs = currentProcessObjectIDs

        if let firstError {
            throw firstError
        }
    }

    private func applyPerAppGainForSession(sessionID: String) {
        guard shouldApplyPerAppGain else { return }
        guard let session = sessions.first(where: { $0.id == sessionID }) else { return }

        for processObjectID in session.processObjectIDs {
            do {
                try processControlBackend.apply(
                    processObjectID: processObjectID,
                    muted: false,
                    gain: session.appGain
                )
                previousGainProcessObjectIDs.insert(processObjectID)
            } catch let error as AudioMonitorError where error == .appGainUnavailable {
                if let index = sessions.firstIndex(where: { $0.id == sessionID }) {
                    sessions[index].isAppGainAvailable = false
                }
            } catch let error as AudioMonitorError where error == .audioCapturePermissionRequired {
                _ = error
                audioCaptureAccessState = .denied
                persistAccessState(.denied)
                isPerAppGainEnabled = false
                userDefaults.set(false, forKey: Self.perAppGainEnabledKey)
                perAppControlsState = .inactive
                deactivatePerAppControlPathIfNeeded()
                errorMessage = nil
                return
            } catch {
                errorMessage = "No se pudo aplicar App Gain: \(error.localizedDescription)"
            }
        }
    }

    private func deactivatePerAppControlPathIfNeeded() {
        if previousGainProcessObjectIDs.isEmpty {
            processControlBackend.cleanup()
            return
        }

        for processObjectID in previousGainProcessObjectIDs {
            try? processControlBackend.remove(processObjectID: processObjectID)
        }
        processControlBackend.cleanup()
        previousGainProcessObjectIDs.removeAll()
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

    private var shouldApplyPerAppGain: Bool {
        isPerAppGainEnabled && perAppControlsState == .active
    }

    private func resolvedGain(for sessionID: String, bundleID: String?) -> Float {
        if let existing = sessionGainByID[sessionID] {
            return clampGain(existing)
        }

        if let bundleID, let persisted = appGainStore.gain(for: bundleID) {
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

    private func persistAccessState(_ state: AudioCaptureAccessState) {
        let rawValue: String
        switch state {
        case .unknown:
            rawValue = "unknown"
        case .granted:
            rawValue = "granted"
        case .denied:
            rawValue = "denied"
        }
        userDefaults.set(rawValue, forKey: Self.audioCaptureAccessStateKey)
    }

    private static func loadAccessState(from userDefaults: UserDefaults) -> AudioCaptureAccessState {
        guard let rawValue = userDefaults.string(forKey: audioCaptureAccessStateKey) else {
            return .unknown
        }
        switch rawValue {
        case "granted":
            return .granted
        case "denied":
            return .denied
        default:
            return .unknown
        }
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

    private func permissionProbeCandidates() -> [AudioObjectID] {
        let ownBundleID = Bundle.main.bundleIdentifier ?? "com.zickox.codexaudiomonitor"
        let internalBundlePrefix = "com.zickox.codexaudiomonitor"
        let ownPID = ProcessInfo.processInfo.processIdentifier

        var preferred = [AudioObjectID]()
        var seen = Set<AudioObjectID>()

        for session in sessions {
            if session.pids.contains(ownPID) {
                continue
            }
            if let bundleID = session.bundleID,
               bundleID == ownBundleID || bundleID.hasPrefix(internalBundlePrefix) {
                continue
            }
            if session.displayName.localizedCaseInsensitiveContains("codexaudio") {
                continue
            }
            let hasInternalPID = session.pids.contains { pid in
                guard let app = NSRunningApplication(processIdentifier: pid),
                      let bundleID = app.bundleIdentifier
                else {
                    return false
                }
                return bundleID == ownBundleID || bundleID.hasPrefix(internalBundlePrefix)
            }
            if hasInternalPID {
                continue
            }
            for processObjectID in session.processObjectIDs {
                guard seen.insert(processObjectID).inserted else { continue }
                preferred.append(processObjectID)
            }
        }

        return preferred
    }
}

protocol AudioCaptureAccessAuthorizing {
    func preflightScreenAndSystemAudioCaptureAccess() -> Bool
    func requestScreenAndSystemAudioCaptureAccess() -> Bool
}

struct ScreenAndSystemAudioCaptureAuthorizer: AudioCaptureAccessAuthorizing {
    func preflightScreenAndSystemAudioCaptureAccess() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    func requestScreenAndSystemAudioCaptureAccess() -> Bool {
        CGRequestScreenCaptureAccess()
    }
}
