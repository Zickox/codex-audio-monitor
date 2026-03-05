@testable import CodexAudioCore
import CoreAudio
import XCTest

@MainActor
private final class MockBridgeMonitor: BridgeAudioControlling {
    var sessions: [AudioSession]
    var errorMessage: String?
    var refreshCalls = 0
    var toggleCalls: [String] = []
    var setMuteCalls: [(String, Bool)] = []

    init(sessions: [AudioSession], errorMessage: String? = nil) {
        self.sessions = sessions
        self.errorMessage = errorMessage
    }

    func refresh() {
        refreshCalls += 1
    }

    func toggleMute(sessionID: String) {
        toggleCalls.append(sessionID)
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else {
            return
        }

        sessions[index].isMuted.toggle()
        sessions[index].lastSeenAt = Date(timeIntervalSince1970: 1_700_000_123)
    }

    func setMuted(sessionID: String, muted: Bool) {
        setMuteCalls.append((sessionID, muted))
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else {
            return
        }

        sessions[index].isMuted = muted
        sessions[index].lastSeenAt = Date(timeIntervalSince1970: 1_700_000_123)
    }
}

@MainActor
final class BridgeHandlersTests: XCTestCase {
    func testBridgeRequestAndResponseCodecRoundTrip() throws {
        let request = BridgeRequest(
            id: "42",
            method: "set_session_mute",
            params: BridgeRequestParams(sessionID: "bundle:com.spotify.client", muted: true)
        )

        let requestData = try JSONEncoder().encode(request)
        let decodedRequest = try JSONDecoder().decode(BridgeRequest.self, from: requestData)
        XCTAssertEqual(decodedRequest, request)

        let response = BridgeResponse.success(
            id: "42",
            result: BridgeResult(
                status: "ok",
                sessions: [
                    BridgeAudioSessionDTO(
                        id: "bundle:com.spotify.client",
                        displayName: "Spotify",
                        bundleID: "com.spotify.client",
                        pids: [1001],
                        isMuted: true,
                        lastSeenAt: "2026-03-03T21:00:00.000Z"
                    )
                ],
                total: 1,
                mutedCount: 1,
                generatedAt: "2026-03-03T21:00:00.000Z",
                changed: true,
                changedSessionID: "bundle:com.spotify.client"
            )
        )

        let responseData = try JSONEncoder().encode(response)
        let decodedResponse = try JSONDecoder().decode(BridgeResponse.self, from: responseData)
        XCTAssertEqual(decodedResponse, response)
    }

    func testListSessionsReturnsEmptyPayload() {
        let monitor = MockBridgeMonitor(sessions: [])
        let handlers = BridgeHandlers(
            monitor: monitor,
            timestampProvider: { Date(timeIntervalSince1970: 1_700_000_000) }
        )

        let response = handlers.handle(
            request: BridgeRequest(id: "1", method: "list_sessions")
        )

        XCTAssertNil(response.error)
        XCTAssertEqual(response.result?.total, 0)
        XCTAssertEqual(response.result?.mutedCount, 0)
        XCTAssertEqual(response.result?.sessions ?? [], [])
        XCTAssertEqual(monitor.refreshCalls, 1)
    }

    func testListSessionsRespectsLimitAndKeepsTotalCounts() {
        let sessions = [
            makeSession(id: "bundle:com.spotify.client", muted: false, pid: 111),
            makeSession(id: "bundle:com.apple.Safari", muted: true, pid: 222)
        ]
        let monitor = MockBridgeMonitor(sessions: sessions)
        let handlers = BridgeHandlers(
            monitor: monitor,
            timestampProvider: { Date(timeIntervalSince1970: 1_700_000_000) }
        )

        let response = handlers.handle(
            request: BridgeRequest(
                id: "2",
                method: "list_sessions",
                params: BridgeRequestParams(limit: 1)
            )
        )

        XCTAssertNil(response.error)
        XCTAssertEqual(response.result?.total, 2)
        XCTAssertEqual(response.result?.mutedCount, 1)
        XCTAssertEqual(response.result?.sessions?.count, 1)
    }

    func testSetSessionMuteChangesStateWhenSessionExists() {
        let monitor = MockBridgeMonitor(
            sessions: [makeSession(id: "bundle:com.spotify.client", muted: false, pid: 111)]
        )
        let handlers = BridgeHandlers(
            monitor: monitor,
            timestampProvider: { Date(timeIntervalSince1970: 1_700_000_000) }
        )

        let response = handlers.handle(
            request: BridgeRequest(
                id: "3",
                method: "set_session_mute",
                params: BridgeRequestParams(sessionID: "bundle:com.spotify.client", muted: true)
            )
        )

        XCTAssertNil(response.error)
        XCTAssertEqual(response.result?.changed, true)
        XCTAssertEqual(response.result?.changedSessionID, "bundle:com.spotify.client")
        XCTAssertEqual(response.result?.mutedCount, 1)
        XCTAssertEqual(monitor.setMuteCalls.count, 1)
        XCTAssertEqual(monitor.setMuteCalls.first?.0, "bundle:com.spotify.client")
        XCTAssertEqual(monitor.setMuteCalls.first?.1, true)
        XCTAssertTrue(monitor.toggleCalls.isEmpty)
    }

    func testSetSessionMuteReturnsChangedFalseWhenSessionDoesNotExist() {
        let monitor = MockBridgeMonitor(sessions: [])
        let handlers = BridgeHandlers(
            monitor: monitor,
            timestampProvider: { Date(timeIntervalSince1970: 1_700_000_000) }
        )

        let response = handlers.handle(
            request: BridgeRequest(
                id: "4",
                method: "set_session_mute",
                params: BridgeRequestParams(sessionID: "bundle:missing", muted: true)
            )
        )

        XCTAssertNil(response.error)
        XCTAssertEqual(response.result?.changed, false)
        XCTAssertEqual(response.result?.changedSessionID, "bundle:missing")
        XCTAssertEqual(response.result?.total, 0)
        XCTAssertTrue(monitor.toggleCalls.isEmpty)
        XCTAssertTrue(monitor.setMuteCalls.isEmpty)
    }

    func testInvalidMethodReturnsMethodNotFoundError() {
        let monitor = MockBridgeMonitor(sessions: [])
        let handlers = BridgeHandlers(monitor: monitor)

        let response = handlers.handle(
            request: BridgeRequest(id: "5", method: "unknown_method")
        )

        XCTAssertNil(response.result)
        XCTAssertEqual(response.error?.code, BridgeErrorCode.methodNotFound.rawValue)
    }

    private func makeSession(id: String, muted: Bool, pid: pid_t) -> AudioSession {
        AudioSession(
            id: id,
            displayName: id,
            bundleID: id.replacingOccurrences(of: "bundle:", with: ""),
            pids: [pid],
            processObjectIDs: [AudioObjectID(pid)],
            isMuted: muted,
            lastSeenAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }
}
