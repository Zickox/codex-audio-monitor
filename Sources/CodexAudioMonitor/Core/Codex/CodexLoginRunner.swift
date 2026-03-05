import Darwin
import Foundation

enum CodexLoginRunner {
    struct Result {
        enum Outcome {
            case success
            case timedOut
            case failed(status: Int32)
            case missingBinary
            case launchFailed(String)
        }

        let outcome: Outcome
        let output: String
    }

    static func run(timeout: TimeInterval = 120, useDeviceAuth: Bool = true) async -> Result {
        await Task(priority: .userInitiated) {
            let env = ProcessInfo.processInfo.environment
            guard let executable = CodexBinaryLocator.resolveCodexBinary(env: env) else {
                return Result(outcome: .missingBinary, output: "")
            }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = useDeviceAuth ? ["login", "--device-auth"] : ["login"]
            process.environment = env

            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr

            var processGroup: pid_t?
            do {
                try process.run()
                processGroup = attachProcessGroup(process)
            } catch {
                return Result(outcome: .launchFailed(error.localizedDescription), output: "")
            }

            let timedOut = await wait(for: process, timeout: timeout)
            if timedOut {
                terminate(process, processGroup: processGroup)
            }

            let output = await combinedOutput(stdout: stdout, stderr: stderr)
            if timedOut {
                return Result(outcome: .timedOut, output: output)
            }

            if process.terminationStatus == 0 {
                return Result(outcome: .success, output: output)
            }
            return Result(outcome: .failed(status: process.terminationStatus), output: output)
        }.value
    }

    private static func wait(for process: Process, timeout: TimeInterval) async -> Bool {
        await withTaskGroup(of: Bool.self) { group -> Bool in
            group.addTask {
                process.waitUntilExit()
                return false
            }
            group.addTask {
                let nanos = UInt64(max(0, timeout) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanos)
                return true
            }

            let timedOut = await group.next() ?? false
            group.cancelAll()
            return timedOut
        }
    }

    private static func terminate(_ process: Process, processGroup: pid_t?) {
        if let processGroup {
            kill(-processGroup, SIGTERM)
        }
        if process.isRunning {
            process.terminate()
        }

        let deadline = Date().addingTimeInterval(2.0)
        while process.isRunning, Date() < deadline {
            usleep(100_000)
        }

        if process.isRunning {
            if let processGroup {
                kill(-processGroup, SIGKILL)
            }
            kill(process.processIdentifier, SIGKILL)
        }
    }

    private static func attachProcessGroup(_ process: Process) -> pid_t? {
        let pid = process.processIdentifier
        return setpgid(pid, pid) == 0 ? pid : nil
    }

    private static func combinedOutput(stdout: Pipe, stderr: Pipe) async -> String {
        async let stdoutText = readToEnd(stdout)
        async let stderrText = readToEnd(stderr)

        let merged = [await stdoutText, await stderrText]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if merged.isEmpty {
            return "No output captured."
        }
        return String(merged.prefix(4_000))
    }

    private static func readToEnd(_ pipe: Pipe) async -> String {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: String(decoding: data, as: UTF8.self))
            }
        }
    }
}
