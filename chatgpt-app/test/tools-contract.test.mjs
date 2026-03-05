import test from "node:test";
import assert from "node:assert/strict";

import {
  listAudioSessionsInputSchema,
  setSessionMuteInputSchema,
  renderAudioWidgetInputSchema,
  toStructuredAudioPayload,
  buildListToolResponse,
  buildSetToolResponse,
} from "../server/mcp-server.mjs";

test("list_audio_sessions schema enforces range and defaults", () => {
  const parsedDefault = listAudioSessionsInputSchema.parse({});
  assert.equal(parsedDefault.limit, 20);

  const parsedValid = listAudioSessionsInputSchema.parse({ limit: 50 });
  assert.equal(parsedValid.limit, 50);

  assert.throws(() => listAudioSessionsInputSchema.parse({ limit: 0 }));
  assert.throws(() => listAudioSessionsInputSchema.parse({ limit: 51 }));
});

test("set_session_mute schema requires sessionID and muted", () => {
  const parsed = setSessionMuteInputSchema.parse({ sessionID: "bundle:com.spotify.client", muted: true });
  assert.equal(parsed.sessionID, "bundle:com.spotify.client");
  assert.equal(parsed.muted, true);

  assert.throws(() => setSessionMuteInputSchema.parse({ muted: true }));
  assert.throws(() => setSessionMuteInputSchema.parse({ sessionID: "bundle:com.spotify.client" }));
});

test("render_audio_widget schema accepts expected payload", () => {
  const payload = {
    sessions: [
      {
        id: "bundle:com.spotify.client",
        displayName: "Spotify",
        bundleID: "com.spotify.client",
        pids: [123],
        isMuted: false,
        lastSeenAt: "2026-03-03T21:00:00.000Z",
      },
    ],
    total: 1,
    mutedCount: 0,
    generatedAt: "2026-03-03T21:00:00.000Z",
  };

  const parsed = renderAudioWidgetInputSchema.parse(payload);
  assert.equal(parsed.total, 1);
  assert.equal(parsed.sessions.length, 1);
});

test("tool response builders keep contract shape", () => {
  const bridgeResult = {
    sessions: [
      {
        id: "bundle:com.spotify.client",
        displayName: "Spotify",
        bundleID: "com.spotify.client",
        pids: [123],
        isMuted: true,
        lastSeenAt: "2026-03-03T21:00:01.000Z",
      },
    ],
    total: 1,
    mutedCount: 1,
    generatedAt: "2026-03-03T21:00:01.000Z",
    changed: true,
    changedSessionID: "bundle:com.spotify.client",
  };

  const structured = toStructuredAudioPayload(bridgeResult);
  assert.equal(structured.total, 1);
  assert.equal(structured.mutedCount, 1);

  const listResponse = buildListToolResponse(bridgeResult, "running");
  assert.equal(listResponse.structuredContent.total, 1);
  assert.equal(listResponse._meta.backendState, "running");

  const setResponse = buildSetToolResponse(bridgeResult, "bundle:com.spotify.client", true, "running");
  assert.equal(setResponse.structuredContent.changed, true);
  assert.equal(setResponse.structuredContent.changedSessionID, "bundle:com.spotify.client");
});
