# GitFlow Guide

## Branches

- `main`: production-ready code.
- `develop`: integration branch.
- `codex/feature/*`: new features.
- `codex/release/*`: release stabilization.
- `codex/hotfix/*`: urgent fixes from `main`.

## Typical flow

1. Create `codex/feature/<name>` from `develop`.
2. Merge feature to `develop` via PR.
3. Cut `codex/release/x.y.z` from `develop`.
4. Merge release to `main` and back to `develop`.
5. Tag release: `vX.Y.Z`.

## Conventional commits

Use these prefixes in PR history:

- `feat(audio): ...`
- `feat(chatgpt-app): ...`
- `test(...): ...`
- `ci(...): ...`
- `docs(...): ...`

## Recommended delivery sequence

1. `codex/feature/audio-bridge`
2. `codex/feature/chatgpt-real-backend`
3. `codex/feature/quality-gates`
4. `codex/feature/gitflow-hardening`

## Release closeout (`v0.2.0` baseline)

1. Create `codex/release/0.2.0` from `develop`.
2. Run quality gates and update `docs/quality/validation-report.md`.
3. Merge to `main` and create tag `v0.2.0`.
4. Back-merge release branch into `develop`.

## Protections (recommended)

- Require PR checks on `main` and `develop`.
- No direct pushes to protected branches.
- Require review approval for merges.
