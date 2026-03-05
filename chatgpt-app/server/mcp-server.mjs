import { createServer } from "node:http";
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StreamableHTTPServerTransport } from "@modelcontextprotocol/sdk/server/streamableHttp.js";
import {
  RESOURCE_MIME_TYPE,
  registerAppResource,
  registerAppTool,
} from "@modelcontextprotocol/ext-apps/server";
import { z } from "zod";

import { AudioBridgeClient, parseBridgeArgs } from "./audio-bridge-client.mjs";

const __dirname = fileURLToPath(new URL(".", import.meta.url));
const packageRoot = join(__dirname, "..", "..");
const WIDGET_PATH = join(__dirname, "..", "public", "audio-widget.html");

const TEMPLATE_URI = "ui://widget/audio-sessions-v1.html";
const MCP_PATH = "/mcp";

const widgetHtml = readFileSync(WIDGET_PATH, "utf8");

export const listAudioSessionsInputSchema = z
  .object({
    limit: z.number().int().min(1).max(50).default(20),
  })
  .default({ limit: 20 });

export const setSessionMuteInputSchema = z.object({
  sessionID: z.string().min(1),
  muted: z.boolean(),
});

export const renderAudioWidgetInputSchema = z.object({
  sessions: z.array(
    z.object({
      id: z.string(),
      displayName: z.string(),
      bundleID: z.string().nullable().optional(),
      pids: z.array(z.number().int()),
      isMuted: z.boolean(),
      lastSeenAt: z.string(),
    })
  ),
  total: z.number().int(),
  mutedCount: z.number().int(),
  generatedAt: z.string(),
});

function sanitizeErrorMessage(error) {
  const value = String(error?.message ?? error ?? "")
    .replace(/\s+/g, " ")
    .trim();

  return value || "Audio backend unavailable";
}

export function toStructuredAudioPayload(result) {
  return {
    sessions: Array.isArray(result?.sessions) ? result.sessions : [],
    total: typeof result?.total === "number" ? result.total : 0,
    mutedCount: typeof result?.mutedCount === "number" ? result.mutedCount : 0,
    generatedAt: result?.generatedAt ?? new Date().toISOString(),
  };
}

export function makeBackendErrorPayload(error, changedSessionID) {
  const message = sanitizeErrorMessage(error);
  return {
    structuredContent: {
      sessions: [],
      total: 0,
      mutedCount: 0,
      generatedAt: new Date().toISOString(),
      changed: false,
      changedSessionID,
    },
    content: [
      {
        type: "text",
        text: `Audio backend unavailable: ${message}`,
      },
    ],
    _meta: {
      backendError: message,
    },
  };
}

export function buildListToolResponse(result, bridgeState) {
  const payload = toStructuredAudioPayload(result);
  return {
    structuredContent: payload,
    content: [
      {
        type: "text",
        text: `Found ${payload.total} session(s), ${payload.mutedCount} muted.`,
      },
    ],
    _meta: {
      backendState: bridgeState,
    },
  };
}

export function buildSetToolResponse(result, sessionID, muted, bridgeState) {
  const payload = toStructuredAudioPayload(result);
  const changed = typeof result.changed === "boolean" ? result.changed : false;
  const message = changed
    ? `Session ${sessionID} is now ${muted ? "muted" : "active"}.`
    : `Session ${sessionID} was not found or already in the requested state.`;

  return {
    structuredContent: {
      ...payload,
      changed,
      changedSessionID: result.changedSessionID ?? sessionID,
    },
    content: [
      {
        type: "text",
        text: message,
      },
    ],
    _meta: {
      backendState: bridgeState,
    },
  };
}

function buildBridgeClient(config = {}) {
  const localBridgeBinary = join(packageRoot, ".build", "debug", "CodexAudioBridge");
  const hasLocalBridgeBinary = existsSync(localBridgeBinary);

  const fallbackBin = hasLocalBridgeBinary ? localBridgeBinary : "swift";
  const fallbackArgs = hasLocalBridgeBinary
    ? []
    : ["run", "--package-path", packageRoot, "CodexAudioBridge"];

  const bridgeBin = config.bridgeBin ?? process.env.AUDIO_BRIDGE_BIN ?? fallbackBin;
  const bridgeArgs = config.bridgeArgs ?? parseBridgeArgs(process.env.AUDIO_BRIDGE_ARGS) ?? fallbackArgs;

  return new AudioBridgeClient({
    bin: bridgeBin,
    args: bridgeArgs,
    cwd: config.bridgeCwd ?? packageRoot,
    requestTimeoutMs: config.requestTimeoutMs ?? 20_000,
    healthTimeoutMs: config.healthTimeoutMs ?? 60_000,
    restartDelaysMs: config.restartDelaysMs,
    maxRestartAttempts: config.maxRestartAttempts,
  });
}

export function createAudioServer(bridgeClient) {
  const server = new McpServer({ name: "codex-audio-monitor-app", version: "0.2.0" });

  registerAppResource(server, "audio-widget", TEMPLATE_URI, {}, async () => ({
    contents: [
      {
        uri: TEMPLATE_URI,
        mimeType: RESOURCE_MIME_TYPE,
        text: widgetHtml,
        _meta: {
          ui: {
            prefersBorder: true,
            domain: "https://codex-audio-monitor.example.com",
            csp: {
              connectDomains: [],
              resourceDomains: ["https://persistent.oaistatic.com"],
            },
          },
          "openai/widgetDescription": "Interactive panel for audio sessions and mute state.",
        },
      },
    ],
  }));

  registerAppTool(
    server,
    "list_audio_sessions",
    {
      title: "List audio sessions",
      description: "Use this when you need current app sessions with output audio and mute state.",
      inputSchema: listAudioSessionsInputSchema,
      annotations: {
        readOnlyHint: true,
        destructiveHint: false,
        openWorldHint: false,
        idempotentHint: true,
      },
      _meta: {
        "openai/toolInvocation/invoking": "Reading sessions…",
        "openai/toolInvocation/invoked": "Sessions ready",
      },
    },
    async ({ limit = 20 }) => {
      try {
        const result = await bridgeClient.listSessions(limit);
        return buildListToolResponse(result, bridgeClient.getState());
      } catch (error) {
        return makeBackendErrorPayload(error);
      }
    }
  );

  registerAppTool(
    server,
    "set_session_mute",
    {
      title: "Set session mute",
      description: "Use this when you need to mute or unmute one specific audio session by id.",
      inputSchema: setSessionMuteInputSchema,
      annotations: {
        readOnlyHint: false,
        destructiveHint: false,
        openWorldHint: false,
        idempotentHint: true,
      },
      _meta: {
        "openai/toolInvocation/invoking": "Updating mute…",
        "openai/toolInvocation/invoked": "Mute updated",
      },
    },
    async ({ sessionID, muted }) => {
      try {
        const result = await bridgeClient.setSessionMute(sessionID, muted);
        return buildSetToolResponse(result, sessionID, muted, bridgeClient.getState());
      } catch (error) {
        return makeBackendErrorPayload(error, sessionID);
      }
    }
  );

  registerAppTool(
    server,
    "render_audio_widget",
    {
      title: "Render audio widget",
      description:
        "Use this when you need the interactive widget view for the latest audio sessions. Call list_audio_sessions first.",
      inputSchema: renderAudioWidgetInputSchema,
      annotations: {
        readOnlyHint: true,
        destructiveHint: false,
        openWorldHint: false,
        idempotentHint: true,
      },
      _meta: {
        ui: {
          resourceUri: TEMPLATE_URI,
          visibility: ["model", "app"],
        },
        "openai/outputTemplate": TEMPLATE_URI,
        "openai/toolInvocation/invoking": "Rendering widget…",
        "openai/toolInvocation/invoked": "Widget ready",
      },
    },
    async ({ sessions, total, mutedCount, generatedAt }) => ({
      structuredContent: {
        sessions,
        total,
        mutedCount,
        generatedAt,
      },
      content: [
        {
          type: "text",
          text: `Rendering ${total} sessions in the audio widget.`,
        },
      ],
      _meta: {
        widgetVersion: "v1",
      },
    })
  );

  return server;
}

function withCorsHeaders(res) {
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Expose-Headers", "Mcp-Session-Id");
}

export function createAudioMcpHttpServer(config = {}) {
  const bridgeClient = config.bridgeClient ?? buildBridgeClient(config);
  const port = Number(config.port ?? process.env.PORT ?? 8787);

  const httpServer = createServer(async (req, res) => {
    if (!req.url) {
      res.writeHead(400).end("Missing URL");
      return;
    }

    const url = new URL(req.url, `http://${req.headers.host ?? "localhost"}`);

    if (req.method === "GET" && url.pathname === "/") {
      withCorsHeaders(res);
      res.writeHead(200, { "content-type": "application/json" });
      res.end(
        JSON.stringify({
          status: "ok",
          service: "codex-audio-monitor-chatgpt-app",
          bridgeState: bridgeClient.getState(),
        })
      );
      return;
    }

    if (req.method === "OPTIONS" && url.pathname === MCP_PATH) {
      withCorsHeaders(res);
      res.writeHead(204, {
        "Access-Control-Allow-Methods": "POST, GET, DELETE, OPTIONS",
        "Access-Control-Allow-Headers": "content-type, mcp-session-id",
      });
      res.end();
      return;
    }

    const MCP_METHODS = new Set(["POST", "GET", "DELETE"]);
    if (url.pathname === MCP_PATH && req.method && MCP_METHODS.has(req.method)) {
      withCorsHeaders(res);

      const server = createAudioServer(bridgeClient);
      const transport = new StreamableHTTPServerTransport({
        sessionIdGenerator: undefined,
        enableJsonResponse: true,
      });

      res.on("close", () => {
        transport.close();
        server.close();
      });

      try {
        await bridgeClient.start();
        await server.connect(transport);
        await transport.handleRequest(req, res);
      } catch (error) {
        if (!res.headersSent) {
          res.writeHead(500).end("Internal server error");
        }
      }
      return;
    }

    if (["/.well-known/oauth-authorization-server", "/.well-known/openid-configuration"].includes(url.pathname)) {
      res.writeHead(404).end("Not Found");
      return;
    }

    res.writeHead(404).end("Not Found");
  });

  const shutdown = async () => {
    await bridgeClient.stop();
  };

  return {
    port,
    bridgeClient,
    httpServer,
    start() {
      return new Promise((resolve) => {
        httpServer.listen(port, () => {
          resolve();
        });
      });
    },
    async stop() {
      await shutdown();
      await new Promise((resolve, reject) => {
        httpServer.close((error) => {
          if (error) {
            reject(error);
            return;
          }
          resolve();
        });
      });
    },
  };
}
