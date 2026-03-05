import Foundation

actor CodexCLIIntegrationService: CodexIntegrationService {
    typealias BinaryResolver = @Sendable () -> String?
    typealias CredentialsLoader = @Sendable () throws -> CodexOAuthCredentials
    typealias LoginRunner = @Sendable (_ timeout: TimeInterval, _ useDeviceAuth: Bool) async -> CodexLoginRunner.Result

    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    private let commandExecutor: any CodexCommandExecuting
    private let binaryResolver: BinaryResolver
    private let credentialsLoader: CredentialsLoader
    private let loginRunner: LoginRunner

    init(
        commandExecutor: any CodexCommandExecuting = SystemCodexCommandExecutor(),
        binaryResolver: @escaping BinaryResolver = { CodexBinaryLocator.resolveCodexBinary() },
        credentialsLoader: @escaping CredentialsLoader = { try CodexOAuthCredentialsStore.load() },
        loginRunner: @escaping LoginRunner = { timeout, useDeviceAuth in
            await CodexLoginRunner.run(timeout: timeout, useDeviceAuth: useDeviceAuth)
        }
    ) {
        self.commandExecutor = commandExecutor
        self.binaryResolver = binaryResolver
        self.credentialsLoader = credentialsLoader
        self.loginRunner = loginRunner
    }

    func authState() async -> CodexAuthState {
        do {
            let credentials = try credentialsLoader()
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

        let result = await loginRunner(180, true)
        switch result.outcome {
        case .success:
            return await authState()
        case .timedOut:
            return .error("codex login timed out. Please try again.")
        case let .failed(status):
            return .error("codex login failed (\(status)): \(sanitize(result.output))")
        case .missingBinary:
            return .error("No se encontró `codex` en PATH.")
        case let .launchFailed(message):
            return .error("No se pudo abrir `codex login`: \(sanitize(message))")
        }
    }

    func runConnectivityChecks() async -> CodexConnectivityReport {
        let checkedAt = Date()
        let state = await authState()

        guard let codexBinary = binaryResolver() else {
            return CodexConnectivityReport(
                binaryFound: false,
                authState: state,
                pingOK: false,
                structuredProbeOK: false,
                roundTripMs: nil,
                assistantPreview: nil,
                errorMessage: "No se encontró `codex` en PATH.",
                checkedAt: checkedAt
            )
        }

        guard case .loggedIn = state else {
            let message: String
            switch state {
            case .loggedOut:
                message = "Codex requiere login. Ejecuta `codex login --device-auth`."
            case let .error(details):
                message = sanitize(details)
            case .checking:
                message = "Validando sesión Codex..."
            case .loggedIn:
                message = ""
            }

            return CodexConnectivityReport(
                binaryFound: true,
                authState: state,
                pingOK: false,
                structuredProbeOK: false,
                roundTripMs: nil,
                assistantPreview: nil,
                errorMessage: message,
                checkedAt: checkedAt
            )
        }

        let start = Date()

        do {
            let pingOutput = try await runPingProbe(executable: codexBinary)
            let pingOK = pingOutput.localizedCaseInsensitiveContains("pong")
            guard pingOK else {
                return CodexConnectivityReport(
                    binaryFound: true,
                    authState: state,
                    pingOK: false,
                    structuredProbeOK: false,
                    roundTripMs: elapsedMilliseconds(since: start),
                    assistantPreview: String(pingOutput.prefix(120)),
                    errorMessage: "La prueba ping no devolvió `pong`.",
                    checkedAt: checkedAt
                )
            }

            let probePlan = try await generateActionPlan(
                message: "estado de prueba",
                context: CodexChatContext(
                    sessions: [],
                    outputVolumePercent: 50,
                    outputDeviceName: "System Output"
                ),
                codexBinary: codexBinary
            )

            return CodexConnectivityReport(
                binaryFound: true,
                authState: state,
                pingOK: true,
                structuredProbeOK: true,
                roundTripMs: elapsedMilliseconds(since: start),
                assistantPreview: String(probePlan.assistantMessage.prefix(160)),
                errorMessage: nil,
                checkedAt: checkedAt
            )
        } catch {
            return CodexConnectivityReport(
                binaryFound: true,
                authState: state,
                pingOK: false,
                structuredProbeOK: false,
                roundTripMs: elapsedMilliseconds(since: start),
                assistantPreview: nil,
                errorMessage: sanitize(error.localizedDescription),
                checkedAt: checkedAt
            )
        }
    }

    func generateActionPlan(message: String, context: CodexChatContext) async throws -> CodexActionPlan {
        guard let codexBinary = binaryResolver() else {
            throw CodexIntegrationError.cliUnavailable
        }

        return try await generateActionPlan(message: message, context: context, codexBinary: codexBinary)
    }
}

private extension CodexCLIIntegrationService {
    func generateActionPlan(
        message: String,
        context: CodexChatContext,
        codexBinary: String
    ) async throws -> CodexActionPlan {
        let schemaURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-audio-monitor-plan-schema-\(UUID().uuidString).json")
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-audio-monitor-plan-output-\(UUID().uuidString).json")

        defer {
            try? FileManager.default.removeItem(at: schemaURL)
            try? FileManager.default.removeItem(at: outputURL)
        }

        try schemaJSONString.write(to: schemaURL, atomically: true, encoding: .utf8)

        let contextData = try encoder.encode(context)
        let contextString = String(decoding: contextData, as: UTF8.self)
        let prompt = buildPrompt(message: message, contextJSON: contextString)

        let result = try await commandExecutor.run(
            executable: codexBinary,
            arguments: [
                "exec",
                "--skip-git-repo-check",
                "--sandbox", "read-only",
                "--output-schema", schemaURL.path,
                "--output-last-message", outputURL.path,
                prompt
            ],
            timeout: .seconds(90)
        )

        if result.exitCode != 0 {
            let details = sanitize("\(result.stderr)\n\(result.stdout)")
            throw CodexIntegrationError.commandFailed(
                command: "codex exec --output-schema ...",
                exitCode: result.exitCode,
                message: details
            )
        }

        let raw = (try? String(contentsOf: outputURL, encoding: .utf8)) ?? result.stdout
        guard let decoded = decodePlan(raw) else {
            throw CodexIntegrationError.invalidResponse("No se pudo parsear el plan de acción.")
        }

        return normalize(decoded)
    }

    func runPingProbe(executable: String) async throws -> String {
        let result = try await commandExecutor.run(
            executable: executable,
            arguments: [
                "exec",
                "--skip-git-repo-check",
                "--sandbox", "read-only",
                "Reply with exactly: pong"
            ],
            timeout: .seconds(45)
        )

        if result.exitCode != 0 {
            let details = sanitize("\(result.stderr)\n\(result.stdout)")
            throw CodexIntegrationError.commandFailed(
                command: "codex exec ping",
                exitCode: result.exitCode,
                message: details
            )
        }

        return sanitize("\(result.stdout)\n\(result.stderr)")
    }

    var schemaJSONString: String {
        """
        {
          "type": "object",
          "additionalProperties": false,
          "required": ["assistantMessage", "actions"],
          "properties": {
            "assistantMessage": {
              "type": "string"
            },
            "actions": {
              "type": "array",
              "maxItems": 3,
              "items": {
                "anyOf": [
                  {
                    "type": "object",
                    "additionalProperties": false,
                    "required": ["type"],
                    "properties": {
                      "type": {
                        "const": "none"
                      }
                    }
                  },
                  {
                    "type": "object",
                    "additionalProperties": false,
                    "required": ["type"],
                    "properties": {
                      "type": {
                        "enum": ["refresh", "status", "mute_all", "unmute_all"]
                      }
                    }
                  },
                  {
                    "type": "object",
                    "additionalProperties": false,
                    "required": ["type", "sessionID"],
                    "properties": {
                      "type": {
                        "enum": ["mute_session", "unmute_session"]
                      },
                      "sessionID": {
                        "type": "string"
                      }
                    }
                  },
                  {
                    "type": "object",
                    "additionalProperties": false,
                    "required": ["type", "volumePercent"],
                    "properties": {
                      "type": {
                        "const": "set_volume"
                      },
                      "volumePercent": {
                        "type": "integer",
                        "minimum": 0,
                        "maximum": 100
                      }
                    }
                  }
                ]
              }
            }
          }
        }
        """
    }

    func buildPrompt(message: String, contextJSON: String) -> String {
        """
        You are controlling a local macOS audio monitor UI.
        Return a JSON object matching the provided schema.

        Rules:
        - Use actions only when user intent is clear.
        - For greetings and casual conversation, respond with action type "none".
        - For session-specific actions, use a sessionID that exists in context.
        - If no UI action is needed, use type "none".
        - Keep assistantMessage concise and actionable.
        - Never invent session IDs.

        User message:
        \(message)

        Current context (JSON):
        \(contextJSON)
        """
    }

    func decodePlan(_ rawValue: String) -> CodexActionPlan? {
        let raw = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty {
            return nil
        }

        if let data = raw.data(using: .utf8),
           let parsed = try? decoder.decode(CodexActionPlan.self, from: data)
        {
            return parsed
        }

        guard let start = raw.firstIndex(of: "{"),
              let end = raw.lastIndex(of: "}") else {
            return nil
        }

        let jsonSlice = String(raw[start ... end])
        guard let fallbackData = jsonSlice.data(using: .utf8) else {
            return nil
        }
        return try? decoder.decode(CodexActionPlan.self, from: fallbackData)
    }

    func normalize(_ plan: CodexActionPlan) -> CodexActionPlan {
        let actions = plan.actions.prefix(3).map { action in
            if action.type == .setVolume {
                let volume = min(max(action.volumePercent ?? 50, 0), 100)
                return CodexAction(type: .setVolume, sessionID: nil, volumePercent: volume)
            }

            return CodexAction(type: action.type, sessionID: action.sessionID, volumePercent: nil)
        }

        let message = sanitize(plan.assistantMessage)
        return CodexActionPlan(
            assistantMessage: message.isEmpty ? "Listo." : message,
            actions: Array(actions)
        )
    }

    func sanitize(_ value: String) -> String {
        let compact = value
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if compact.count > 280 {
            return String(compact.prefix(280))
        }
        return compact
    }

    func elapsedMilliseconds(since startDate: Date) -> Int {
        max(0, Int((Date().timeIntervalSince(startDate) * 1000).rounded()))
    }
}
