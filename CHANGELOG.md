# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Added

- App-only project shape with a single macOS app scheme (`CodexAudioMonitorApp`).
- Menubar tabs (`Audio`, `Chat`) with smooth transitions and dynamic height behavior.
- Codex chat action planner using real `codex exec` + JSON schema output.
- Regeneration script `scripts/generate_xcodeproj.rb`.

### Changed

- GitFlow docs updated to `codex/feature|release|hotfix` branch prefixes.
- Validation runbook/report updated for app-only Xcode flow.
- CoreAudio mute backend now activates taps through private aggregate devices + IOProc lifecycle to make per-app mute effective on background audio.
- Codex auth now uses local OAuth credentials and login runs `codex login --device-auth` with a resilient runner/timeout.
- Menu bar UI simplified to a minimal two-tab layout, prioritizing session list and chat.
- Menu sessions section now includes ConflictMonitor-inspired filter chips with counts (`All`, `Active`, `Muted`) and expandable rows for on-demand detail.
- Added bulk mute control (`Mute All` / `Unmute All`) via explicit monitor APIs (`setMuted`, `setAllMuted`).
- Added animated audio-level indicator in the header to reflect active playback.
- Added system output volume controls (slider + step buttons) backed by CoreAudio output device volume APIs.
- Removed `chatgpt-app`, bridge executable/contract layers, and SPM package layout to reduce architecture overhead.

## [0.1.0] - 2026-03-03

### Added

- Menu bar audio monitor MVP with per-app mute/unmute.
- macOS 15+ glass strategy with native Liquid Glass path for macOS 26+.
- Optional Codex auth/app-server integration module.
- Unit tests for monitor behavior and Codex auth parsing.
- OSS governance docs and CI/release workflows.
