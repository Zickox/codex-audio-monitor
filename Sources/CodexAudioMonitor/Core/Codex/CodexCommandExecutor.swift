import Foundation

protocol CodexCommandExecuting: Sendable {
    func run(
        executable: String,
        arguments: [String],
        timeout: Duration
    ) async throws -> ProcessResult
}

struct SystemCodexCommandExecutor: CodexCommandExecuting {
    func run(
        executable: String,
        arguments: [String],
        timeout: Duration
    ) async throws -> ProcessResult {
        try await ProcessRunner.run(
            executable: executable,
            arguments: arguments,
            timeout: timeout,
            environment: commandEnvironment()
        )
    }

    private func commandEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment

        let requiredPaths = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ]

        let existingPaths = (env["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)

        var merged = existingPaths
        for path in requiredPaths where !merged.contains(path) {
            merged.append(path)
        }

        env["PATH"] = merged.joined(separator: ":")
        return env
    }
}
