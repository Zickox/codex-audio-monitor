# Contributing

## Branching model

We use GitFlow with:

- `main` for stable releases.
- `develop` for integration.
- `codex/feature/*` for feature work.
- `codex/release/*` for release hardening.
- `codex/hotfix/*` for production fixes.

## Commit convention

Use Conventional Commits, for example:

- `feat(audio): add process mute backend`
- `fix(ui): prevent row clipping on small menu heights`
- `test(codex): cover login status parsing`

## Local checks

Run before opening a PR:

```bash
xcodebuild -project CodexAudioMonitor.xcodeproj -scheme CodexAudioMonitorApp -destination 'platform=macOS' build
```

## Pull requests

- Target `develop` unless it is a hotfix.
- Include test evidence.
- Keep scope focused.
