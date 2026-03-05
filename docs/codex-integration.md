# Codex Integration Notes

This project uses an optional local Codex integration module based on:

- Local Codex credentials managed by `codex login`
- `codex login`
- `codex app-server --listen stdio://`

## Why this shape

- The audio monitor must keep working even when Codex is unavailable.
- Reading local credential state avoids brittle parsing of CLI status output.
- Login runner uses timeout + process-group cleanup to prevent hanging sessions.
- The app-server process is treated as optional runtime infrastructure with restart attempts.

## Official references

- https://developers.openai.com/codex/auth/
- https://developers.openai.com/apps-sdk/build/mcp-server/
- https://developers.openai.com/apps-sdk/reference/
