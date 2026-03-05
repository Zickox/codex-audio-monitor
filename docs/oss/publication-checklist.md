# OSS Publication Checklist

Use this checklist before publishing or tagging a public release.

## Repository hygiene

- [ ] No local absolute paths in public docs (`README.md`, `docs/**`, `CHANGELOG.md`).
- [ ] No secrets, tokens, or private credentials committed.
- [ ] `.gitignore` includes local auth/env/log/artifact patterns.
- [ ] Public-facing docs are consistent with current branch model and release flow.

## Build and test gates

- [ ] `swift test`
- [ ] `xcodebuild -project CodexAudioMonitor.xcodeproj -scheme CodexAudioMonitorApp -destination 'platform=macOS' build`
- [ ] `xcodebuild -project CodexAudioMonitor.xcodeproj -scheme CodexAudioBridge -destination 'platform=macOS' build`
- [ ] `chatgpt-app`: `npm run check`
- [ ] `chatgpt-app`: `npm run test`

## Smoke gates

- [ ] Bridge smoke (`health`, `list_sessions`, `set_session_mute`).
- [ ] MCP smoke (`initialize`, `list_audio_sessions`, `set_session_mute`).
- [ ] Menubar launch smoke via `./run-menubar.sh`.

## Security and CI

- [ ] CI (`.github/workflows/ci.yml`) passing.
- [ ] Secret scan (`.github/workflows/security.yml`) passing.
- [ ] Release workflow (`.github/workflows/release.yml`) validated on tag.

## Release and branch policy

- [ ] `main` and `develop` branch protections enabled.
- [ ] Tag format follows `vX.Y.Z`.
- [ ] Release notes and checksum artifacts published.
- [ ] `docs/quality/validation-report.md` updated with latest run evidence.
