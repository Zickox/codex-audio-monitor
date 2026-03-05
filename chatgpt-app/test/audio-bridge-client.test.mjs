import test from "node:test";
import assert from "node:assert/strict";
import { EventEmitter } from "node:events";
import { PassThrough } from "node:stream";

import { AudioBridgeClient } from "../server/audio-bridge-client.mjs";

function createMockSpawn(handler) {
  const children = [];

  const spawnProcess = () => {
    const stdin = new PassThrough();
    const stdout = new PassThrough();
    const stderr = new PassThrough();
    const emitter = new EventEmitter();

    let stdinBuffer = "";

    const child = Object.assign(emitter, {
      stdin,
      stdout,
      stderr,
      killed: false,
      kill() {
        if (child.killed) {
          return;
        }

        child.killed = true;
        process.nextTick(() => {
          emitter.emit("exit", 0, null);
        });
      },
    });

    stdin.on("data", (chunk) => {
      stdinBuffer += String(chunk);
      let boundary = stdinBuffer.indexOf("\n");
      while (boundary >= 0) {
        const line = stdinBuffer.slice(0, boundary).trim();
        stdinBuffer = stdinBuffer.slice(boundary + 1);

        if (line) {
          const request = JSON.parse(line);
          const response = handler(request, child, children.length);
          if (response) {
            stdout.write(`${JSON.stringify(response)}\n`);
          }
        }

        boundary = stdinBuffer.indexOf("\n");
      }
    });

    children.push(child);
    return child;
  };

  return { spawnProcess, children };
}

test("AudioBridgeClient performs health/list/set flow", async () => {
  const { spawnProcess } = createMockSpawn((request) => {
    if (request.method === "health") {
      return { id: request.id, result: { status: "ok" } };
    }

    if (request.method === "list_sessions") {
      return {
        id: request.id,
        result: {
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
        },
      };
    }

    if (request.method === "set_session_mute") {
      return {
        id: request.id,
        result: {
          sessions: [
            {
              id: request.params.sessionID,
              displayName: "Spotify",
              bundleID: "com.spotify.client",
              pids: [123],
              isMuted: request.params.muted,
              lastSeenAt: "2026-03-03T21:00:01.000Z",
            },
          ],
          total: 1,
          mutedCount: request.params.muted ? 1 : 0,
          generatedAt: "2026-03-03T21:00:01.000Z",
          changed: true,
          changedSessionID: request.params.sessionID,
        },
      };
    }

    return { id: request.id, error: { code: "method_not_found", message: "unknown" } };
  });

  const client = new AudioBridgeClient({
    bin: "mock",
    args: [],
    spawnProcess,
    requestTimeoutMs: 200,
    healthTimeoutMs: 200,
    restartDelaysMs: [10, 20, 40],
    maxRestartAttempts: 3,
    logger: { warn() {}, error() {}, info() {} },
  });

  await client.start();

  const listed = await client.listSessions(20);
  assert.equal(listed.total, 1);
  assert.equal(listed.sessions[0].id, "bundle:com.spotify.client");

  const updated = await client.setSessionMute("bundle:com.spotify.client", true);
  assert.equal(updated.mutedCount, 1);
  assert.equal(updated.changed, true);
  assert.equal(updated.changedSessionID, "bundle:com.spotify.client");

  await client.stop();
});

test("AudioBridgeClient restarts after unexpected process exit", async () => {
  const { spawnProcess, children } = createMockSpawn((request) => {
    if (request.method === "health") {
      return { id: request.id, result: { status: "ok" } };
    }

    return {
      id: request.id,
      result: {
        sessions: [],
        total: 0,
        mutedCount: 0,
        generatedAt: "2026-03-03T21:00:00.000Z",
      },
    };
  });

  const client = new AudioBridgeClient({
    bin: "mock",
    args: [],
    spawnProcess,
    requestTimeoutMs: 200,
    healthTimeoutMs: 200,
    restartDelaysMs: [10, 10, 10],
    maxRestartAttempts: 3,
    logger: { warn() {}, error() {}, info() {} },
  });

  await client.start();
  assert.equal(children.length, 1);

  children[0].emit("exit", 1, null);
  await new Promise((resolve) => setTimeout(resolve, 40));

  await client.listSessions(10);
  assert.ok(children.length >= 2);
  assert.equal(client.getState(), "running");

  await client.stop();
});
