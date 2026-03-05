import Foundation
import XCTest
@testable import CodexAudioMonitor

final class CodexCLIIntegrationServiceTests: XCTestCase {
    func testBinaryLocatorUsesOverridePath() throws {
        let tempDir = try makeTemporaryDirectory()
        let executablePath = try makeExecutable(named: "codex", in: tempDir)

        let resolved = CodexBinaryLocator.resolveCodexBinary(
            env: ["CODEX_CLI_PATH": executablePath, "PATH": ""],
            fileManager: .default,
            allowShellLookup: false
        )

        XCTAssertEqual(resolved, executablePath)
    }

    func testBinaryLocatorUsesPATHExecutable() throws {
        let tempDir = try makeTemporaryDirectory()
        let executablePath = try makeExecutable(named: "codex", in: tempDir)

        let resolved = CodexBinaryLocator.resolveCodexBinary(
            env: ["PATH": tempDir.path],
            fileManager: .default,
            allowShellLookup: false
        )

        XCTAssertEqual(resolved, executablePath)
    }

    func testBinaryLocatorReturnsNilWithoutHitsWhenShellLookupDisabled() {
        let resolved = CodexBinaryLocator.resolveCodexBinary(
            env: ["PATH": "/tmp/non-existent-codex-path"],
            fileManager: .default,
            allowShellLookup: false,
            allowDefaultFallbackPaths: false
        )

        XCTAssertNil(resolved)
    }

    func testGenerateActionPlanDecodesAndNormalizesResponse() async throws {
        let service = CodexCLIIntegrationService(
            commandExecutor: StubCodexCommandExecutor { _, arguments, _ in
                guard let outputFile = Self.argumentValue(after: "--output-last-message", in: arguments) else {
                    XCTFail("Missing --output-last-message argument")
                    return ProcessResult(stdout: "", stderr: "", exitCode: 1)
                }

                let payload = """
                {
                  "assistantMessage": "   hola   codex   ",
                  "actions": [
                    { "type": "set_volume", "volumePercent": 500 }
                  ]
                }
                """
                try payload.write(toFile: outputFile, atomically: true, encoding: .utf8)
                return ProcessResult(stdout: "", stderr: "", exitCode: 0)
            },
            binaryResolver: { "/usr/local/bin/codex" },
            credentialsLoader: {
                CodexOAuthCredentials(
                    accessToken: "token",
                    refreshToken: "refresh",
                    idToken: nil,
                    accountID: nil,
                    lastRefresh: Date()
                )
            }
        )

        let plan = try await service.generateActionPlan(
            message: "volumen 500",
            context: CodexChatContext(
                sessions: [],
                outputVolumePercent: 50,
                outputDeviceName: "System Output"
            )
        )

        XCTAssertEqual(plan.assistantMessage, "hola codex")
        XCTAssertEqual(plan.actions.count, 1)
        XCTAssertEqual(plan.actions.first?.type, .setVolume)
        XCTAssertEqual(plan.actions.first?.volumePercent, 100)
        XCTAssertNil(plan.actions.first?.sessionID)
    }

    func testRunConnectivityChecksReturnsConnectedWhenProbesSucceed() async throws {
        let service = CodexCLIIntegrationService(
            commandExecutor: StubCodexCommandExecutor { _, arguments, _ in
                if arguments.contains("--output-schema") {
                    guard let outputFile = Self.argumentValue(after: "--output-last-message", in: arguments) else {
                        return ProcessResult(stdout: "", stderr: "missing output path", exitCode: 1)
                    }
                    let payload = """
                    {
                      "assistantMessage": "conectado",
                      "actions": [
                        { "type": "status" }
                      ]
                    }
                    """
                    try payload.write(toFile: outputFile, atomically: true, encoding: .utf8)
                    return ProcessResult(stdout: "", stderr: "", exitCode: 0)
                }

                return ProcessResult(stdout: "pong", stderr: "", exitCode: 0)
            },
            binaryResolver: { "/usr/local/bin/codex" },
            credentialsLoader: {
                CodexOAuthCredentials(
                    accessToken: "token",
                    refreshToken: "refresh",
                    idToken: nil,
                    accountID: nil,
                    lastRefresh: Date()
                )
            }
        )

        let report = await service.runConnectivityChecks()

        XCTAssertTrue(report.binaryFound)
        XCTAssertTrue(report.pingOK)
        XCTAssertTrue(report.structuredProbeOK)
        XCTAssertTrue(report.isConnected)
        XCTAssertEqual(report.authState, .loggedIn(provider: "OAuth"))
        XCTAssertNotNil(report.roundTripMs)
        XCTAssertEqual(report.assistantPreview, "conectado")
        XCTAssertNil(report.errorMessage)
    }

    func testRunConnectivityChecksReturnsMissingBinaryError() async {
        let service = CodexCLIIntegrationService(
            commandExecutor: StubCodexCommandExecutor { _, _, _ in
                XCTFail("Command executor should not be called when binary is missing")
                return ProcessResult(stdout: "", stderr: "", exitCode: 1)
            },
            binaryResolver: { nil },
            credentialsLoader: {
                CodexOAuthCredentials(
                    accessToken: "token",
                    refreshToken: "refresh",
                    idToken: nil,
                    accountID: nil,
                    lastRefresh: Date()
                )
            }
        )

        let report = await service.runConnectivityChecks()

        XCTAssertFalse(report.binaryFound)
        XCTAssertFalse(report.pingOK)
        XCTAssertFalse(report.structuredProbeOK)
        XCTAssertNotNil(report.errorMessage)
    }

    func testRunConnectivityChecksReturnsAuthRequiredWhenLoggedOut() async {
        let service = CodexCLIIntegrationService(
            commandExecutor: StubCodexCommandExecutor { _, _, _ in
                XCTFail("Command executor should not be called when auth is missing")
                return ProcessResult(stdout: "", stderr: "", exitCode: 1)
            },
            binaryResolver: { "/usr/local/bin/codex" },
            credentialsLoader: {
                throw CodexOAuthCredentialsError.notFound
            }
        )

        let report = await service.runConnectivityChecks()

        XCTAssertTrue(report.binaryFound)
        XCTAssertEqual(report.authState, .loggedOut)
        XCTAssertFalse(report.pingOK)
        XCTAssertFalse(report.structuredProbeOK)
        XCTAssertNotNil(report.errorMessage)
    }

    private static func argumentValue(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }

    private func makeTemporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory
        let directory = root.appendingPathComponent("codex-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makeExecutable(named name: String, in directory: URL) throws -> String {
        let fileURL = directory.appendingPathComponent(name)
        let contents = "#!/bin/sh\nexit 0\n"
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fileURL.path)
        return fileURL.path
    }
}
