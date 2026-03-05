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
    private let muteBackend: AudioMuteBackend
    private let outputVolumeController: AudioOutputVolumeControlling
    private let pollInterval: Duration

    private var mutedSessionIDs = Set<String>()
    private var sessionLastSeenByID: [String: Date] = [:]
    private var previousProcessObjectIDs = Set<AudioObjectID>()
    private var refreshTask: Task<Void, Never>?

    public init(pollInterval: Duration = .seconds(1)) {
        self.snapshotProvider = CoreAudioProcessSnapshotProvider()
        self.muteBackend = CoreAudioTapMuteBackend()
        self.outputVolumeController = CoreAudioOutputVolumeController()
        self.pollInterval = pollInterval
        refreshOutputVolume()
    }

    init(
        snapshotProvider: AudioProcessSnapshotProviding = CoreAudioProcessSnapshotProvider(),
        muteBackend: AudioMuteBackend = CoreAudioTapMuteBackend(),
        outputVolumeController: AudioOutputVolumeControlling = CoreAudioOutputVolumeController(),
        pollInterval: Duration = .seconds(1)
    ) {
        self.snapshotProvider = snapshotProvider
        self.muteBackend = muteBackend
        self.outputVolumeController = outputVolumeController
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
    }

    public func refresh() {
        refreshOutputVolume()

        do {
            let snapshots = try snapshotProvider.snapshots()
            let activeSessions = buildSessions(from: snapshots)
            try reconcileMuteState(with: activeSessions)
            sessions = activeSessions
            lastRefresh = Date()
            errorMessage = nil
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

        sessionLastSeenByID = sessionLastSeenByID.filter { activeIDs.contains($0.key) }

        return byID.values
            .map { value in
                AudioSession(
                    id: value.id,
                    displayName: value.displayName,
                    bundleID: value.bundleID,
                    pids: value.pids.sorted(),
                    processObjectIDs: value.processObjectIDs.sorted(),
                    isMuted: mutedSessionIDs.contains(value.id),
                    lastSeenAt: sessionLastSeenByID[value.id] ?? now
                )
            }
            .sorted { lhs, rhs in
                lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
    }

    private func reconcileMuteState(with activeSessions: [AudioSession]) throws {
        let currentProcessObjectIDs = Set(activeSessions.flatMap(\.processObjectIDs))
        let removedProcessObjectIDs = previousProcessObjectIDs.subtracting(currentProcessObjectIDs)

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

        previousProcessObjectIDs = currentProcessObjectIDs
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
}
