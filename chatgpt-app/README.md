# Codex Audio Monitor - ChatGPT App

This folder contains the ChatGPT Apps SDK app (MCP server + widget) wired to the real macOS audio backend through `CodexAudioBridge`.

## Archetype

- Primary archetype: `interactive-decoupled`
- Why: repeated UI interactions (refresh/mute) without forcing widget remount on each model call.

## Tool plan

- `list_audio_sessions` (data-only, read-only)
- `set_session_mute` (state mutation, non-destructive, closed-world)
- `render_audio_widget` (render-only tool with widget template metadata)

## Runtime architecture

`chatgpt-app` starts an `AudioBridgeClient` that spawns `CodexAudioBridge` over stdio and calls:

- `health`
- `list_sessions`
- `set_session_mute`

`CodexAudioBridge` reuses `AudioProcessMonitor` from Swift core and returns JSON responses.

## Environment variables

- `PORT`: MCP HTTP port (default `8787`)
- `AUDIO_BRIDGE_BIN`: bridge binary path (optional)
- `AUDIO_BRIDGE_ARGS`: bridge args (optional; JSON array or whitespace list)

Default bridge resolution:

1. `../.build/debug/CodexAudioBridge` if present
2. fallback: `swift run --package-path <repo> CodexAudioBridge`

## Local run

```bash
swift build
cd chatgpt-app
npm install
npm run check
npm run test
npm run start
```

Server endpoint:

- `http://localhost:8787/mcp`

Health endpoint:

- `http://localhost:8787/`

## MCP smoke (real backend)

```bash
curl -sS -X POST http://localhost:8787/mcp \
  -H 'content-type: application/json' \
  -H 'Accept: application/json, text/event-stream' \
  -d '{"jsonrpc":"2.0","id":"init-1","method":"initialize","params":{"protocolVersion":"2026-01-26","capabilities":{},"clientInfo":{"name":"smoke","version":"0.1.0"}}}'

curl -sS -X POST http://localhost:8787/mcp \
  -H 'content-type: application/json' \
  -H 'Accept: application/json, text/event-stream' \
  -d '{"jsonrpc":"2.0","id":"call-1","method":"tools/call","params":{"name":"list_audio_sessions","arguments":{"limit":5}}}'

curl -sS -X POST http://localhost:8787/mcp \
  -H 'content-type: application/json' \
  -H 'Accept: application/json, text/event-stream' \
  -d '{"jsonrpc":"2.0","id":"call-2","method":"tools/call","params":{"name":"set_session_mute","arguments":{"sessionID":"bundle:missing","muted":true}}}'
```

## Connect in ChatGPT Developer Mode

1. Enable Developer Mode in ChatGPT: **Settings -> Apps & Connectors -> Advanced settings**.
2. Start local server (`npm run start`).
3. Expose it with tunnel:

```bash
ngrok http 8787
```

4. Create app in ChatGPT with URL `https://<subdomain>.ngrok.app/mcp`.
5. Refresh app after metadata/tool changes.

## Notes

- `_meta.ui.domain` is placeholder (`https://codex-audio-monitor.example.com`) and must be replaced before submission.
- Bridge errors are returned as structured degraded payloads so MCP server stays available.

## Docs used

- https://developers.openai.com/apps-sdk/build/mcp-server/
- https://developers.openai.com/apps-sdk/build/chatgpt-ui/
- https://developers.openai.com/apps-sdk/build/examples/
- https://developers.openai.com/apps-sdk/plan/tools/
- https://developers.openai.com/apps-sdk/reference/
- https://developers.openai.com/apps-sdk/quickstart/
- https://developers.openai.com/apps-sdk/deploy/
- https://developers.openai.com/apps-sdk/deploy/submission/
- https://developers.openai.com/apps-sdk/app-submission-guidelines/
