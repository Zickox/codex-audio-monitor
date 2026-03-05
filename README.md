# Codex Audio Monitor

Small macOS menu bar app to detect apps producing audio and mute/unmute them per app.

## Requirements

- macOS 15+
- Xcode 26+
- Swift 6+
- Node 24+ (only for `chatgpt-app`)

## Run

```bash
# 1) Test core package
swift test

# 2) Build native macOS app scheme
xcodebuild -project CodexAudioMonitor.xcodeproj -scheme CodexAudioMonitorApp -destination 'platform=macOS' build

# 3) Launch menubar app (canonical local launcher)
./run-menubar.sh
```

## Architecture

- `Sources/CodexAudioMonitor/Core/Audio`: process detection, mute backend, output volume control.
- `Sources/CodexAudioMonitor/UI`: menu bar UI, compact list, chat card, glass styling strategy.
- `Sources/CodexAudioMonitor/Core/Codex`: optional Codex auth/app-server integration.
- `Sources/CodexAudioMonitor/Core/Bridge`: stdio bridge protocol + handlers.
- `Sources/CodexAudioBridge`: executable bridge entrypoint.
- `chatgpt-app/`: MCP server + widget that talks to the real bridge backend.

## Optional Codex integration

Codex support is optional. The audio monitor works without Codex login.

When enabled, the app uses local Codex credentials (managed by `codex login`) and can control runtime features through the embedded chat commands.

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
