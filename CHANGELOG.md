# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Added

- `CodexAudioBridge` executable with stdio JSON contract (`health`, `list_sessions`, `set_session_mute`).
- Shared bridge protocol and handlers in `Core/Bridge`.
- Swift tests for bridge codec and behavior (`BridgeHandlersTests`).
- Swift tests for Codex OAuth credential parsing (`CodexOAuthCredentialsTests`).
- Node bridge client with health-check, request timeouts, and restart backoff.
- Node tests for bridge client and ChatGPT tool contract (`node:test`).
- CI smoke job for MCP initialize + list/mute tool calls through the real bridge.
- Native app project `CodexAudioMonitor.xcodeproj` with app and bridge schemes.
- Regeneration script `scripts/generate_xcodeproj.rb`.

### Changed

- `chatgpt-app` now reads real audio sessions from `CodexAudioBridge` (no in-memory hardcoded sessions).
- GitFlow docs updated to `codex/feature|release|hotfix` branch prefixes.
- Validation runbook/report updated for XcodeBuildMCP + SPM workspace flow.
- CoreAudio mute backend now activates taps through private aggregate devices + IOProc lifecycle to make per-app mute effective on background audio.
- Codex auth now uses the same OAuth source model as CodexBar (reads local Codex credentials) and login now runs `codex login` with a resilient runner/timeout.
- Menu bar UI refreshed to a denser card-based style inspired by CodexBar, with compact sections and improved visual hierarchy.
- Menu sessions section now includes ConflictMonitor-inspired filter chips with counts (`All`, `Active`, `Muted`) and expandable rows for on-demand detail.
- Added bulk mute control (`Mute All` / `Unmute All`) via explicit monitor APIs (`setMuted`, `setAllMuted`).
- Bridge mute command now uses explicit `setMuted` semantics for deterministic `set_session_mute` behavior.
- Added animated audio-level indicator in the header to reflect active playback.
- Added system output volume controls (slider + step buttons) backed by CoreAudio output device volume APIs.
- Added a compact "Codex Chat" panel in the Codex card to control UI actions with natural-language commands (mute/unmute, volume, refresh, status, login/RPC actions).

## [0.1.0] - 2026-03-03

### Added

- Menu bar audio monitor MVP with per-app mute/unmute.
- macOS 15+ glass strategy with native Liquid Glass path for macOS 26+.
- Optional Codex auth/app-server integration module.
- Unit tests for monitor behavior and Codex auth parsing.
- OSS governance docs and CI/release workflows.
