import Foundation

actor CodexCLIIntegrationService: CodexIntegrationService {
    private var process: Process?
    private var inputHandle: FileHandle?
    private var outputHandle: FileHandle?
    private var state: CodexAppServerState = .stopped

    private var intentionalStop = false
    private var restartAttempts = 0
    private let maxRestartAttempts = 3

    func authState() async -> CodexAuthState {
        do {
            let credentials = try CodexOAuthCredentialsStore.load()
            return .loggedIn(provider: credentials.providerLabel)
        } catch let error as CodexOAuthCredentialsError {
            switch error {
            case .notFound, .missingTokens:
                return .loggedOut
            case let .decodeFailed(message):
                return .error(message)
            }
        } catch {
            return .error(error.localizedDescription)
        }
    }

    func ensureLogin() async -> CodexAuthState {
        let current = await authState()
        if case .loggedIn = current {
            return current
        }

        let result = await CodexLoginRunner.run(timeout: 120)
        switch result.outcome {
        case .success:
            return await authState()
        case .timedOut:
            return .error("codex login timed out. Please try again.")
        case let .failed(status):
            return .error("codex login failed (\(status)): \(result.output)")
        case .missingBinary:
            return .error("No se encontró `codex` en PATH.")
        case let .launchFailed(message):
            return .error("No se pudo abrir `codex login`: \(message)")
        }
    }

    func startAppServer() async throws {
        if process?.isRunning == true {
            state = .running
            return
        }

        intentionalStop = false
        restartAttempts = 0

        try launchAppServer()
    }

    func stopAppServer() async {
        intentionalStop = true
        process?.terminate()
        process = nil
        inputHandle = nil
        outputHandle = nil
        state = .stopped
    }

    func send(request: String) async throws -> String {
        guard process?.isRunning == true else {
            throw CodexIntegrationError.appServerNotRunning
        }
        guard let inputHandle else {
            throw CodexIntegrationError.appServerIOUnavailable
        }

        if let data = (request + "\n").data(using: .utf8) {
            try inputHandle.write(contentsOf: data)
        }

        return "sent"
    }

    func appServerState() async -> CodexAppServerState {
        state
    }

    private func launchAppServer() throws {
        state = .starting

        let env = ProcessInfo.processInfo.environment
        guard let codexBinary = CodexBinaryLocator.resolveCodexBinary(env: env) else {
            state = .failed(CodexIntegrationError.cliUnavailable.localizedDescription)
            throw CodexIntegrationError.cliUnavailable
        }

        let process = Process()
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: codexBinary)
        process.arguments = ["app-server", "--listen", "stdio://"]
        process.environment = env
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        process.terminationHandler = { [weak self] terminatedProcess in
            Task {
                await self?.handleTermination(exitCode: terminatedProcess.terminationStatus)
            }
        }

        do {
            try process.run()
        } catch {
            state = .failed(error.localizedDescription)
            throw error
        }

        self.process = process
        self.inputHandle = stdinPipe.fileHandleForWriting
        self.outputHandle = stdoutPipe.fileHandleForReading

        state = .running
    }

    private func handleTermination(exitCode: Int32) async {
        process = nil
        inputHandle = nil
        outputHandle = nil

        guard !intentionalStop else {
            state = .stopped
            return
        }

        guard restartAttempts < maxRestartAttempts else {
            state = .failed("Exited with code \(exitCode)")
            return
        }

        restartAttempts += 1
        state = .restarting(attempt: restartAttempts)

        let backoffSeconds = pow(2.0, Double(restartAttempts - 1))
        try? await Task.sleep(for: .seconds(backoffSeconds))

        do {
            try launchAppServer()
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
