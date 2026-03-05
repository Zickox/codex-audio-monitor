import Foundation

@MainActor
public protocol BridgeAudioControlling: AnyObject {
    var sessions: [AudioSession] { get }
    var errorMessage: String? { get }

    func refresh()
    func toggleMute(sessionID: String)
    func setMuted(sessionID: String, muted: Bool)
}

extension AudioProcessMonitor: BridgeAudioControlling {}

@MainActor
public struct BridgeHandlers {
    private let monitor: any BridgeAudioControlling
    private let timestampProvider: () -> Date

    public init(
        monitor: any BridgeAudioControlling,
        timestampProvider: @escaping () -> Date = Date.init
    ) {
        self.monitor = monitor
        self.timestampProvider = timestampProvider
    }

    public func handle(request: BridgeRequest) -> BridgeResponse {
        switch request.method {
        case "health":
            return .success(
                id: request.id,
                result: BridgeResult(
                    status: "ok",
                    generatedAt: Self.iso8601(timestampProvider())
                )
            )

        case "list_sessions":
            if let limit = request.params?.limit, limit <= 0 {
                return .failure(
                    id: request.id,
                    code: .invalidRequest,
                    message: "'limit' must be greater than zero"
                )
            }

            return listSessionsResponse(id: request.id, limit: request.params?.limit)

        case "set_session_mute":
            guard let sessionID = request.params?.sessionID,
                  let muted = request.params?.muted
            else {
                return .failure(
                    id: request.id,
                    code: .invalidRequest,
                    message: "'sessionID' and 'muted' are required"
                )
            }

            return setSessionMuteResponse(id: request.id, sessionID: sessionID, muted: muted)

        default:
            return .failure(
                id: request.id,
                code: .methodNotFound,
                message: "Unknown method: \(request.method)"
            )
        }
    }

    private func listSessionsResponse(id: String, limit: Int?) -> BridgeResponse {
        if let errorResponse = refreshSessions(id: id) {
            return errorResponse
        }

        return .success(
            id: id,
            result: makeListResult(from: monitor.sessions, limit: limit)
        )
    }

    private func setSessionMuteResponse(id: String, sessionID: String, muted: Bool) -> BridgeResponse {
        if let errorResponse = refreshSessions(id: id) {
            return errorResponse
        }

        let currentSessions = monitor.sessions
        guard let target = currentSessions.first(where: { $0.id == sessionID }) else {
            return .success(
                id: id,
                result: makeListResult(
                    from: currentSessions,
                    limit: nil,
                    changed: false,
                    changedSessionID: sessionID
                )
            )
        }

        let changed = target.isMuted != muted
        if changed {
            monitor.setMuted(sessionID: sessionID, muted: muted)
        }

        return .success(
            id: id,
            result: makeListResult(
                from: monitor.sessions,
                limit: nil,
                changed: changed,
                changedSessionID: sessionID
            )
        )
    }

    private func refreshSessions(id: String) -> BridgeResponse? {
        monitor.refresh()

        if let errorMessage = monitor.errorMessage {
            return .failure(
                id: id,
                code: .internalError,
                message: sanitizeErrorMessage(errorMessage)
            )
        }

        return nil
    }

    private func makeListResult(
        from allSessions: [AudioSession],
        limit: Int?,
        changed: Bool? = nil,
        changedSessionID: String? = nil
    ) -> BridgeResult {
        let limitedSessions: [AudioSession]
        if let limit {
            limitedSessions = Array(allSessions.prefix(limit))
        } else {
            limitedSessions = allSessions
        }

        let mappedSessions = limitedSessions.map { session in
            BridgeAudioSessionDTO(
                id: session.id,
                displayName: session.displayName,
                bundleID: session.bundleID,
                pids: session.pids.map { Int32($0) },
                isMuted: session.isMuted,
                lastSeenAt: Self.iso8601(session.lastSeenAt)
            )
        }

        return BridgeResult(
            sessions: mappedSessions,
            total: allSessions.count,
            mutedCount: allSessions.filter(\.isMuted).count,
            generatedAt: Self.iso8601(timestampProvider()),
            changed: changed,
            changedSessionID: changedSessionID
        )
    }

    private func sanitizeErrorMessage(_ value: String) -> String {
        let collapsed = value
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if collapsed.isEmpty {
            return "Audio monitor operation failed"
        }

        return collapsed
    }

    private static func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
