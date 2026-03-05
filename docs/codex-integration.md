# Codex Integration Notes

This project uses an optional local Codex integration module based on:

- Local Codex credentials managed by `codex login`
- `codex login --device-auth`
- `codex exec` with structured output for UI actions
- Connectivity probes (`ping` + structured schema check)

## Why this shape

- The audio monitor must keep working even when Codex is unavailable.
- Reading local credential state avoids brittle parsing of CLI status output.
- Login runner uses timeout + process-group cleanup to prevent hanging sessions.
- Chat commands are interpreted by real Codex and then applied to local UI actions (mute/unmute/volume/refresh/status).
- Chat UI includes a diagnostic card (`Check connection`) with:
  - status (`Not checked`, `Checking`, `Connected`, `Auth required`, `Error`)
  - ping/structured probe result
  - latency in ms

## Live test strategy

- Unit tests are deterministic and run on every PR.
- Live Codex checks are opt-in and non-blocking by default:
  - marker (file content `1`): `/tmp/codex-live-tests`
  - strict marker (file content `1`): `/tmp/codex-live-tests-required`
- When strict marker is present, live connectivity failures fail the test run.

## Official references

- https://developers.openai.com/codex/auth/
