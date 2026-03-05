# XcodeBuildMCP Validation Runbook

## Standard bootstrap

1. `session-show-defaults`
2. `doctor(enabled: true)`
3. `manage-workflows(enable: true, workflowNames: ["project-discovery","macos","logging","ui-automation","session-management","doctor"])`
4. `discover_projs(workspaceRoot: <repo-root>)`
5. `list_schemes`
6. `session-set-defaults(projectPath: <repo-root>/CodexAudioMonitor.xcodeproj, scheme: "CodexAudioMonitorApp", platform: "macOS", configuration: "Debug")`
7. `show_build_settings`

## Repository policy (app-only)

Primary validation path is the Xcode project.

Required gates on every cycle:

- `xcodebuild -project CodexAudioMonitor.xcodeproj -scheme CodexAudioMonitorApp -destination 'platform=macOS' build`
- `xcodebuild -project CodexAudioMonitor.xcodeproj -scheme CodexAudioMonitorApp -configuration Release -destination 'platform=macOS' build`
- `xcodebuild -project CodexAudioMonitor.xcodeproj -scheme CodexAudioMonitorApp -destination 'platform=macOS' test`
- menubar smoke with `./run-menubar.sh`
- Codex chat smoke (`login codex`, `mutea todo`, `volumen 40`, `estado`)

## Live Codex checks (opt-in)

Live checks are non-blocking by default and can be run in two modes:

- Optional live mode:
  - `echo "1" > /tmp/codex-live-tests`
  - `xcodebuild -project CodexAudioMonitor.xcodeproj -scheme CodexAudioMonitorApp -destination 'platform=macOS' test -only-testing:CodexAudioMonitorTests/CodexConnectivityLiveTests`
- Required live mode (fail when Codex is not reachable):
  - `echo "1" > /tmp/codex-live-tests`
  - `echo "1" > /tmp/codex-live-tests-required`
  - `xcodebuild -project CodexAudioMonitor.xcodeproj -scheme CodexAudioMonitorApp -destination 'platform=macOS' test -only-testing:CodexAudioMonitorTests/CodexConnectivityLiveTests`

Cleanup markers after execution:

- `rm -f /tmp/codex-live-tests /tmp/codex-live-tests-required`

## Quality gates

### Fast gate (PR -> develop)

- Debug build
- Unit tests (`xcodebuild ... test`)

### Integration gate (before main)

- Release build
- Manual audio checks (detect/mute/unmute/volume)
- Manual Codex chat checks

### Release gate (release branches or tags)

- Reproducible release build
- Unit tests
- Manual menubar UX review
- Unsigned artifact + checksum generation

## XcodeBuildMCP fallback policy

If this runtime cannot execute `build_macos` / `test_macos` directly, run equivalent `xcodebuild` CLI commands and record the limitation in `docs/quality/validation-report.md`.
