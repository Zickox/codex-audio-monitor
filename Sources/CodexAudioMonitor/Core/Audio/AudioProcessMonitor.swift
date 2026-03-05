import AppKit
import CoreAudio
import Foundation
import Observation

@MainActor
@Observable
public final class AudioProcessMonitor: AudioMonitoringService {
    public private(set) var sessions: [AudioSession] = []
    public private(set) var errorMessage: String?
    public private(set) var lastRefresh = Date.distantPast
    public private(set) var outputVolume: Float = 0.5
    public private(set) var canControlOutputVolume = false
    public private(set) var outputDeviceName = "System Output"

    private let snapshotProvider: AudioProcessSnapshotProviding
    private let processControlBackend: AudioProcessControlBackend
    private let outputVolumeController: AudioOutputVolumeControlling
    private let appGainStore: AppGainStore
    private let pollInterval: Duration

    private var mutedSessionIDs = Set<String>()
    private var sessionGainByID: [String: Float] = [:]
    private var sessionLastSeenByID: [String: Date] = [:]
    private var previousProcessObjectIDs = Set<AudioObjectID>()
    private var refreshTask: Task<Void, Never>?

    public init(pollInterval: Duration = .seconds(1)) {
        self.snapshotProvider = CoreAudioProcessSnapshotProvider()
        self.processControlBackend = CoreAudioTapProcessControlBackend()
        self.outputVolumeController = CoreAudioOutputVolumeController()
        self.appGainStore = AppGainStore()
        self.pollInterval = pollInterval
        refreshOutputVolume()
    }

    init(
        snapshotProvider: AudioProcessSnapshotProviding = CoreAudioProcessSnapshotProvider(),
        processControlBackend: AudioProcessControlBackend = CoreAudioTapProcessControlBackend(),
        outputVolumeController: AudioOutputVolumeControlling = CoreAudioOutputVolumeController(),
        appGainStore: AppGainStore = AppGainStore(),
        pollInterval: Duration = .seconds(1)
    ) {
        self.snapshotProvider = snapshotProvider
        self.processControlBackend = processControlBackend
        self.outputVolumeController = outputVolumeController
        self.appGainStore = appGainStore
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
        processControlBackend.cleanup()
    }

    public func refresh() {
        refreshOutputVolume()

        do {
            let snapshots = try snapshotProvider.snapshots()
            var activeSessions = buildSessions(from: snapshots)
            sessions = activeSessions
            lastRefresh = Date()

            do {
                try reconcileProcessControl(with: &activeSessions)
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
        if mutedSessionIDs.contains(sessionID) {
            mutedSessionIDs.remove(sessionID)
        } else {
            mutedSessionIDs.insert(sessionID)
        }
        refresh()
    }

    public func setMuted(sessionID: String, muted: Bool) {
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

        return byID.values
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
            .sorted { lhs, rhs in
                lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
    }

    private func reconcileProcessControl(with activeSessions: inout [AudioSession]) throws {
        let currentProcessObjectIDs = Set(activeSessions.flatMap(\.processObjectIDs))
        let removedProcessObjectIDs = previousProcessObjectIDs.subtracting(currentProcessObjectIDs)

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
            let isMuted: Bool
            let gain: Float
        }

        let desiredStateByProcessObjectID = Dictionary(
            uniqueKeysWithValues: activeSessions
                .flatMap { session in
                    session.processObjectIDs.map { processObjectID in
                        (processObjectID, ProcessState(sessionID: session.id, isMuted: session.isMuted, gain: session.appGain))
                    }
                }
        )

        for (processObjectID, state) in desiredStateByProcessObjectID {
            do {
                try processControlBackend.apply(
                    processObjectID: processObjectID,
                    muted: state.isMuted,
                    gain: state.gain
                )
            } catch let error as AudioMonitorError where error == .appGainUnavailable || error == .audioCapturePermissionRequired {
                if let index = activeSessions.firstIndex(where: { $0.id == state.sessionID }) {
                    activeSessions[index].isAppGainAvailable = false
                    activeSessions[index].appGain = 1.0
                    sessionGainByID[state.sessionID] = 1.0
                    if let bundleID = activeSessions[index].bundleID {
                        appGainStore.removeGain(for: bundleID)
                    }
                }

                if error == .audioCapturePermissionRequired, firstError == nil {
                    firstError = error
                }

                do {
                    try processControlBackend.apply(
                        processObjectID: processObjectID,
                        muted: state.isMuted,
                        gain: 1.0
                    )
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

        previousProcessObjectIDs = currentProcessObjectIDs

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

    private func applyProcessControlForSession(at index: Int) {
        guard sessions.indices.contains(index) else { return }

        let session = sessions[index]
        var firstError: Error?

        for processObjectID in session.processObjectIDs {
            do {
                try processControlBackend.apply(
                    processObjectID: processObjectID,
                    muted: session.isMuted,
                    gain: session.appGain
                )
            } catch AudioMonitorError.appGainUnavailable {
                sessions[index].isAppGainAvailable = false
                sessions[index].appGain = 1.0
                sessionGainByID[session.id] = 1.0
                if let bundleID = session.bundleID {
                    appGainStore.removeGain(for: bundleID)
                }

                do {
                    try processControlBackend.apply(
                        processObjectID: processObjectID,
                        muted: session.isMuted,
                        gain: 1.0
                    )
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

        if let firstError {
            errorMessage = "No se pudo aplicar App Gain: \(firstError.localizedDescription)"
        } else {
            errorMessage = nil
        }
    }
}
