import Foundation

struct ProcessResult: Sendable {
    let stdout: String
    let stderr: String
    let exitCode: Int32
}

enum ProcessRunner {
    static func run(
        executable: String,
        arguments: [String],
        timeout: Duration,
        environment: [String: String]? = nil
    ) async throws -> ProcessResult {
        try await withThrowingTaskGroup(of: ProcessResult.self) { group in
            group.addTask {
                try await runWithoutTimeout(
                    executable: executable,
                    arguments: arguments,
                    environment: environment
                )
            }

            group.addTask {
                try await Task.sleep(for: timeout)
                throw CodexIntegrationError.timeout(command: ([executable] + arguments).joined(separator: " "))
            }

            guard let result = try await group.next() else {
                throw CodexIntegrationError.timeout(command: ([executable] + arguments).joined(separator: " "))
            }
            group.cancelAll()
            return result
        }
    }

    private static func runWithoutTimeout(
        executable: String,
        arguments: [String],
        environment: [String: String]? = nil
    ) async throws -> ProcessResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()

                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                if let environment {
                    process.environment = environment
                }
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                    return
                }

                process.waitUntilExit()

                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

                let result = ProcessResult(
                    stdout: String(decoding: stdoutData, as: UTF8.self),
                    stderr: String(decoding: stderrData, as: UTF8.self),
                    exitCode: process.terminationStatus
                )
                continuation.resume(returning: result)
            }
        }
    }
}
