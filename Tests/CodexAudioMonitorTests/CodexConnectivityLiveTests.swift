import XCTest
@testable import CodexAudioMonitor

final class CodexConnectivityLiveTests: XCTestCase {
    func testLiveConnectivityChecks() async throws {
        let mode = liveMode()
        guard mode.enabled else {
            throw XCTSkip("Set CODEX_LIVE_TESTS=1 to run live Codex tests")
        }

        let service = CodexCLIIntegrationService()
        let report = await service.runConnectivityChecks()

        if case .loggedOut = report.authState {
            if mode.required {
                XCTFail("Live tests required but Codex auth is logged out")
            } else {
                throw XCTSkip("Codex auth is logged out")
            }
            return
        }

        guard report.isConnected else {
            let details = report.errorMessage ?? "unknown error"
            if mode.required {
                XCTFail("Live tests required but connectivity check failed: \(details)")
            } else {
                throw XCTSkip("Connectivity check failed: \(details)")
            }
            return
        }

        XCTAssertTrue(report.binaryFound)
        XCTAssertTrue(report.pingOK)
        XCTAssertTrue(report.structuredProbeOK)
        XCTAssertNotNil(report.roundTripMs)
    }

    func testLiveHelloRequestReturnsNonDestructivePlan() async throws {
        let mode = liveMode()
        guard mode.enabled else {
            throw XCTSkip("Set CODEX_LIVE_TESTS=1 to run live Codex tests")
        }

        let service = CodexCLIIntegrationService()
        let report = await service.runConnectivityChecks()
        guard report.isConnected else {
            if mode.required {
                XCTFail("Live tests required but connectivity check failed: \(report.errorMessage ?? "unknown error")")
            } else {
                throw XCTSkip("Skipping live hello test due to failed connectivity check")
            }
            return
        }

        let plan = try await service.generateActionPlan(
            message: "hola",
            context: CodexChatContext(
                sessions: [],
                outputVolumePercent: 50,
                outputDeviceName: "System Output"
            )
        )

        XCTAssertFalse(plan.assistantMessage.isEmpty)

        let hasDestructiveActions = plan.actions.contains { action in
            switch action.type {
            case .muteAll, .unmuteAll, .muteSession, .unmuteSession, .setVolume, .setSessionGain:
                return true
            case .none, .refresh, .status:
                return false
            }
        }
        XCTAssertFalse(hasDestructiveActions)
    }

    func testLiveSessionGainRequestReturnsStructuredSessionAction() async throws {
        let mode = liveMode()
        guard mode.enabled else {
            throw XCTSkip("Set CODEX_LIVE_TESTS=1 to run live Codex tests")
        }

        let service = CodexCLIIntegrationService()
        let report = await service.runConnectivityChecks()
        guard report.isConnected else {
            if mode.required {
                XCTFail("Live tests required but connectivity check failed: \(report.errorMessage ?? "unknown error")")
            } else {
                throw XCTSkip("Skipping live session gain test due to failed connectivity check")
            }
            return
        }

        let plan = try await service.generateActionPlan(
            message: "spotify 30%",
            context: CodexChatContext(
                sessions: [
                    CodexSessionContext(
                        id: "bundle:com.spotify.client",
                        displayName: "Spotify",
                        bundleID: "com.spotify.client",
                        isMuted: false
                    )
                ],
                outputVolumePercent: 60,
                outputDeviceName: "System Output"
            )
        )

        let gainActions = plan.actions.filter { $0.type == .setSessionGain }
        XCTAssertFalse(gainActions.isEmpty)
        XCTAssertEqual(gainActions.first?.sessionID, "bundle:com.spotify.client")
        if let gain = gainActions.first?.gainPercent {
            XCTAssertGreaterThanOrEqual(gain, 0)
            XCTAssertLessThanOrEqual(gain, 100)
        } else {
            XCTFail("set_session_gain action should include gainPercent")
        }
    }

    private func liveMode() -> (enabled: Bool, required: Bool) {
        let env = ProcessInfo.processInfo.environment
        let markerEnabled = markerValue(at: "/tmp/codex-live-tests") == "1"
        let markerRequired = markerValue(at: "/tmp/codex-live-tests-required") == "1"
        return (
            enabled: env["CODEX_LIVE_TESTS"] == "1" || markerEnabled,
            required: env["CODEX_LIVE_TESTS_REQUIRED"] == "1" || markerRequired
        )
    }

    private func markerValue(at path: String) -> String? {
        guard let value = try? String(contentsOfFile: path, encoding: .utf8) else {
            return nil
        }

        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
