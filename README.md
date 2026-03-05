# Codex Audio Monitor

Minimal macOS menu bar app to detect apps producing audio and mute/unmute them per app.

## Requirements

- macOS 15+
- Xcode 26+
- Swift 6+
- Codex CLI (`codex`) only if you want the optional chat tab with real OAuth

## Run

```bash
# 1) Build native macOS app scheme
xcodebuild -project CodexAudioMonitor.xcodeproj -scheme CodexAudioMonitorApp -destination 'platform=macOS' build

# 2) Launch menubar app
./run-menubar.sh
```

## Test

```bash
# Unit/integration tests (live Codex checks remain opt-in)
xcodebuild -project CodexAudioMonitor.xcodeproj -scheme CodexAudioMonitorApp -destination 'platform=macOS' test

# Optional live Codex checks
echo "1" > /tmp/codex-live-tests
xcodebuild -project CodexAudioMonitor.xcodeproj -scheme CodexAudioMonitorApp -destination 'platform=macOS' test -only-testing:CodexAudioMonitorTests/CodexConnectivityLiveTests
rm -f /tmp/codex-live-tests /tmp/codex-live-tests-required
```

## Architecture

- Single macOS app project (`CodexAudioMonitor.xcodeproj`).
- `Sources/CodexAudioMonitor/Core/Audio`: process detection, per-app mute backend, output volume control.
- `Sources/CodexAudioMonitor/Core/Codex`: optional Codex OAuth + real `codex exec` action planning.
- `Sources/CodexAudioMonitor/UI`: menubar UI with 2 tabs (`Audio`, `Chat`) and glass styling.

## Optional Codex integration

Codex support is optional. The audio monitor works without login.

When enabled, the chat tab uses real Codex credentials (managed by `codex login --device-auth`) and executes actions through `codex exec`.
The chat tab also includes a built-in diagnostic panel (`Check connection`) that runs ping + structured probe checks and reports connection state/latency.

## Advanced docs

- [GitFlow guide](docs/gitflow.md)
- [Codex integration notes](docs/codex-integration.md)
- [XcodeBuildMCP runbook](docs/quality/xcodebuildmcp-runbook.md)
- [Validation report](docs/quality/validation-report.md)
- [OSS publication checklist](docs/oss/publication-checklist.md)

## Open-source policy

- License: [MIT](LICENSE)
- Contribution guide: [CONTRIBUTING.md](CONTRIBUTING.md)
- Security: [SECURITY.md](SECURITY.md)
- Support: [SUPPORT.md](SUPPORT.md)
- Governance: [GOVERNANCE.md](GOVERNANCE.md)
