import Foundation

enum CodexBinaryLocator {
    static func resolveCodexBinary(
        env: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> String? {
        if let override = env["CODEX_CLI_PATH"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty,
           fileManager.isExecutableFile(atPath: override)
        {
            return override
        }

        if let path = env["PATH"],
           let hit = findBinary(named: "codex", in: path.split(separator: ":").map(String.init), fileManager: fileManager)
        {
            return hit
        }

        if let shellHit = commandV(tool: "codex", env: env, fileManager: fileManager) {
            return shellHit
        }

        let fallbacks = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ]
        return findBinary(named: "codex", in: fallbacks, fileManager: fileManager)
    }

    private static func findBinary(
        named binary: String,
        in paths: [String],
        fileManager: FileManager
    ) -> String? {
        for path in paths where !path.isEmpty {
            let prefix = path.hasSuffix("/") ? String(path.dropLast()) : path
            let candidate = "\(prefix)/\(binary)"
            if fileManager.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    private static func commandV(
        tool: String,
        env: [String: String],
        fileManager: FileManager
    ) -> String? {
        let shellPath = env["SHELL"]?.isEmpty == false ? env["SHELL"]! : "/bin/zsh"
        let process = Process()
        let stdout = Pipe()
        process.executableURL = URL(fileURLWithPath: shellPath)
        process.arguments = ["-l", "-i", "-c", "command -v \(tool)"]
        process.environment = env
        process.standardOutput = stdout
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }

        let deadline = Date().addingTimeInterval(2.0)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }

        if process.isRunning {
            process.terminate()
            return nil
        }

        let output = String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard output.hasPrefix("/"), fileManager.isExecutableFile(atPath: output) else {
            return nil
        }

        return output
    }
}
