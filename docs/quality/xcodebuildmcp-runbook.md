# XcodeBuildMCP Validation Runbook

## Standard bootstrap

1. `session-show-defaults`
2. `doctor(enabled: true)`
3. `manage-workflows(enable: true, workflowNames: ["project-discovery","macos","logging","ui-automation","session-management","doctor","swift-package"])`
4. `discover_projs(workspaceRoot: <repo>)`
5. `list_schemes`
6. `session-set-defaults(projectPath: <repo>/CodexAudioMonitor.xcodeproj, scheme: "CodexAudioMonitorApp", platform: "macOS", configuration: "Debug")`
7. `show_build_settings`

## Policy for this repository (Xcode app + SPM support)

Primary validation path is now Xcode project for app runtime, with SPM kept for package-level checks and bridge tooling.

Equivalent gates to execute on every cycle:

- `xcodebuild -project CodexAudioMonitor.xcodeproj -scheme CodexAudioMonitorApp -destination 'platform=macOS' build`
- `xcodebuild -project CodexAudioMonitor.xcodeproj -scheme CodexAudioBridge -destination 'platform=macOS' build`
- `swift build`
- `swift test`
- `swift run CodexAudioBridge` smoke (stdio health/list/mute contract)
- `chatgpt-app`: `npm run check` + `npm run test`
- MCP smoke over HTTP `/mcp`: `initialize` + `tools/call list_audio_sessions` + `tools/call set_session_mute`

## Quality gates

### Fast gate (PR -> develop)

- Debug build (`swift build`)
- Unit tests (`swift test` + `npm run test`)
- Smoke launch (`CodexAudioMonitor` and `chatgpt-app` MCP smoke)

### Integration gate (before main)

- Release build (`swift build -c release`)
- Full test suite (Swift + Node)
- Audio functional checks (detect/mute/unmute/cleanup)

### Release gate (release branches or tags)

- Reproducible build
- Manual menubar UX review
- Unsigned artifact + checksum generation

## XcodeBuildMCP fallback policy

If this runtime cannot resolve the project/scheme for any reason, execute equivalent SPM/Node gates and record the limitation in `docs/quality/validation-report.md`.

No release should be closed without equivalent build/test/smoke evidence.
