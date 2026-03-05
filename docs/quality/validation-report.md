# Validation Report

## Context

- Date: 2026-03-05 (America/Santiago)
- Project: Codex Audio Monitor
- Toolchain: Xcode 26.3 / Swift 6.2 / codex-cli 0.106.0
- Scope: App Gain por sesión + Codex control + validación formal con XcodeBuildMCP

## XcodeBuildMCP bootstrap

Executed runbook bootstrap:

- `session-show-defaults` ✅
- `doctor(enabled: true)` ✅
- `manage-workflows(enable: true, ...)` ✅
- `discover_projs(workspaceRoot: <repo-root>)` ✅ (`CodexAudioMonitor.xcodeproj`)
- `list_schemes` ✅ (`CodexAudioMonitorApp`)
- `session-set-defaults(...)` ✅
- `show_build_settings` ✅

### MCP runtime note

In this runtime, direct `build_macos` / `test_macos` actions are not exposed in the active wrapper. Per runbook policy, build/test gates were executed with `xcodebuild` CLI fallback.

## Build and test gates

- `xcodebuild -project CodexAudioMonitor.xcodeproj -scheme CodexAudioMonitorApp -configuration Debug -destination 'platform=macOS' test` ✅
  - `CodexAudioMonitorTests`: 21 executed, 3 skipped (live opt-in), 0 failed
  - Includes new App Gain coverage:
    - `AppGainStoreTests`
    - `AudioProcessMonitorGainTests`
    - `CodexRuntimeControllerTests` (`set_session_gain` and `hola` non-destructive)
    - `CodexCLIIntegrationServiceTests` (`set_session_gain` schema/normalization)
- `xcodebuild -project CodexAudioMonitor.xcodeproj -scheme CodexAudioMonitorApp -configuration Release -destination 'platform=macOS' build` ✅

## Live Codex checks

- Direct Codex roundtrip (no UI) ✅
  - Command: `codex exec "Responde exactamente: hola desde codex"`
  - Result: `hola desde codex`
- Live XCTest suite (opt-in) executed with marker file:
  - `echo "1" > /tmp/codex-live-tests`
  - `xcodebuild ... -only-testing:CodexAudioMonitorTests/CodexConnectivityLiveTests/...`
  - Result: live tests entered opt-in path, but skipped due connectivity issue under xctest runtime (`@openai/codex-darwin-arm64` optional dependency missing for the CLI wrapper). Non-blocking by design. ✅

## Risks and follow-up

- Open risk: live XCTest depends on local `codex` runtime packaging in test-host architecture.
- Recommended local fix:
  - `npm install -g @openai/codex@latest`
  - rerun opt-in live suite and record a full pass.

## Notes

- Live test suite is opt-in and non-blocking by default:
  - marker file content must be `1`: `/tmp/codex-live-tests`
  - strict marker file content must be `1`: `/tmp/codex-live-tests-required`
- Codex integration remains optional and isolated from core audio monitoring.
