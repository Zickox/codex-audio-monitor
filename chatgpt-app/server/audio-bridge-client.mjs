import { spawn } from "node:child_process";
import { createInterface } from "node:readline";

const DEFAULT_REQUEST_TIMEOUT_MS = 10_000;
const DEFAULT_HEALTH_TIMEOUT_MS = 20_000;
const DEFAULT_RESTART_DELAYS_MS = [1_000, 2_000, 4_000];

function sanitizeErrorMessage(input) {
  const value = String(input ?? "")
    .replace(/\s+/g, " ")
    .trim();

  return value || "Audio bridge request failed";
}

export function parseBridgeArgs(rawValue) {
  if (!rawValue || !rawValue.trim()) {
    return null;
  }

  const trimmed = rawValue.trim();
  if (trimmed.startsWith("[") && trimmed.endsWith("]")) {
    try {
      const parsed = JSON.parse(trimmed);
      if (Array.isArray(parsed) && parsed.every((item) => typeof item === "string")) {
        return parsed;
      }
    } catch {
      // Ignore and fallback to whitespace splitting.
    }
  }

  return trimmed.split(/\s+/g).filter(Boolean);
}

export class AudioBridgeClient {
  constructor(options = {}) {
    this.bin = options.bin;
    this.args = options.args ?? [];
    this.cwd = options.cwd;
    this.env = options.env;

    this.requestTimeoutMs = options.requestTimeoutMs ?? DEFAULT_REQUEST_TIMEOUT_MS;
    this.healthTimeoutMs = options.healthTimeoutMs ?? DEFAULT_HEALTH_TIMEOUT_MS;
    this.restartDelaysMs = options.restartDelaysMs ?? DEFAULT_RESTART_DELAYS_MS;
    this.maxRestartAttempts = options.maxRestartAttempts ?? this.restartDelaysMs.length;

    this.spawnProcess = options.spawnProcess ?? spawn;
    this.logger = options.logger ?? console;

    this.child = null;
    this.readline = null;
    this.pending = new Map();
    this.nextID = 0;
    this.startPromise = null;
    this.restartTimer = null;
    this.restartAttempts = 0;
    this.intentionalStop = false;
    this.state = "stopped";
  }

  async start() {
    await this.ensureStarted();
  }

  async stop() {
    this.intentionalStop = true;

    if (this.restartTimer) {
      clearTimeout(this.restartTimer);
      this.restartTimer = null;
    }

    this.rejectAllPending(new Error("Audio bridge stopped"));

    if (this.readline) {
      this.readline.close();
      this.readline = null;
    }

    if (this.child) {
      this.child.kill();
      this.child = null;
    }

    this.state = "stopped";
    this.startPromise = null;
  }

  getState() {
    return this.state;
  }

  async listSessions(limit = 20) {
    const result = await this.call("list_sessions", { limit });
    return normalizeBridgeResult(result);
  }

  async setSessionMute(sessionID, muted) {
    const result = await this.call("set_session_mute", { sessionID, muted });
    return normalizeBridgeResult(result);
  }

  async health() {
    return this.call("health", {});
  }

  async call(method, params = {}, timeoutOverrideMs) {
    await this.ensureStarted();

    return this.requestInternal(method, params, timeoutOverrideMs);
  }

  requestInternal(method, params = {}, timeoutOverrideMs) {
    if (!this.child?.stdin || this.child.killed) {
      throw new Error("Audio bridge is not running");
    }

    const id = String(++this.nextID);
    const payload = JSON.stringify({ id, method, params });
    const timeoutMs = timeoutOverrideMs ?? this.requestTimeoutMs;

    return new Promise((resolve, reject) => {
      const timeout = setTimeout(() => {
        this.pending.delete(id);
        reject(new Error(`Audio bridge timeout for '${method}'`));
      }, timeoutMs);

      this.pending.set(id, {
        resolve,
        reject,
        timeout,
        method,
      });

      this.child.stdin.write(`${payload}\n`, "utf8", (error) => {
        if (error) {
          clearTimeout(timeout);
          this.pending.delete(id);
          reject(new Error(`Failed to write request '${method}': ${sanitizeErrorMessage(error.message)}`));
        }
      });
    });
  }

  async ensureStarted() {
    if (this.child && !this.child.killed && this.state === "running") {
      return;
    }

    if (this.startPromise) {
      await this.startPromise;
      return;
    }

    this.intentionalStop = false;
    this.startPromise = this.spawnAndHandshake();

    try {
      await this.startPromise;
    } finally {
      this.startPromise = null;
    }
  }

  async spawnAndHandshake() {
    if (!this.bin) {
      throw new Error("AUDIO_BRIDGE_BIN is not configured");
    }

    this.state = "starting";

    const child = this.spawnProcess(this.bin, this.args, {
      cwd: this.cwd,
      env: this.env,
      stdio: ["pipe", "pipe", "pipe"],
    });

    this.child = child;

    this.readline = createInterface({ input: child.stdout });
    this.readline.on("line", (line) => this.onStdoutLine(line));

    child.stderr?.on("data", (chunk) => {
      const text = String(chunk ?? "").trim();
      if (text) {
        this.logger.warn?.(`[audio-bridge] ${text}`);
      }
    });

    child.on("exit", (code, signal) => {
      this.onProcessExit(code, signal);
    });

    child.on("error", (error) => {
      this.logger.error?.(`[audio-bridge] process error: ${sanitizeErrorMessage(error.message)}`);
    });

    try {
      await this.requestInternal("health", {}, this.healthTimeoutMs);
      this.state = "running";
      this.restartAttempts = 0;
    } catch (error) {
      this.state = "failed";
      this.child.kill();
      this.child = null;
      throw error;
    }
  }

  onStdoutLine(line) {
    let message;
    try {
      message = JSON.parse(line);
    } catch {
      this.logger.warn?.("[audio-bridge] non-json stdout line received");
      return;
    }

    if (!message?.id) {
      return;
    }

    const pending = this.pending.get(String(message.id));
    if (!pending) {
      return;
    }

    clearTimeout(pending.timeout);
    this.pending.delete(String(message.id));

    if (message.error) {
      const code = message.error.code ?? "internal_error";
      const text = sanitizeErrorMessage(message.error.message);
      pending.reject(new Error(`[${code}] ${text}`));
      return;
    }

    pending.resolve(message.result ?? {});
  }

  onProcessExit(code, signal) {
    if (this.readline) {
      this.readline.close();
      this.readline = null;
    }

    this.child = null;
    this.state = this.intentionalStop ? "stopped" : "failed";

    this.rejectAllPending(new Error("Audio bridge process exited"));

    if (this.intentionalStop) {
      return;
    }

    const nextAttempt = this.restartAttempts + 1;
    if (nextAttempt > this.maxRestartAttempts) {
      this.logger.error?.("[audio-bridge] max restart attempts reached");
      return;
    }

    this.restartAttempts = nextAttempt;
    const delay = this.restartDelaysMs[Math.min(nextAttempt - 1, this.restartDelaysMs.length - 1)];
    this.state = "restarting";

    this.logger.warn?.(
      `[audio-bridge] exited (code=${code ?? "n/a"}, signal=${signal ?? "n/a"}), restarting in ${delay}ms (attempt ${nextAttempt}/${this.maxRestartAttempts})`
    );

    if (this.restartTimer) {
      clearTimeout(this.restartTimer);
    }

    this.restartTimer = setTimeout(async () => {
      this.restartTimer = null;
      if (this.intentionalStop) {
        return;
      }

      try {
        await this.ensureStarted();
      } catch (error) {
        this.logger.error?.(`[audio-bridge] restart failed: ${sanitizeErrorMessage(error.message)}`);
      }
    }, delay);
  }

  rejectAllPending(error) {
    for (const [id, pending] of this.pending.entries()) {
      clearTimeout(pending.timeout);
      pending.reject(error);
      this.pending.delete(id);
    }
  }
}

export function normalizeBridgeResult(result) {
  const sessions = Array.isArray(result?.sessions) ? result.sessions : [];
  const total = typeof result?.total === "number" ? result.total : sessions.length;
  const mutedCount = typeof result?.mutedCount === "number"
    ? result.mutedCount
    : sessions.filter((item) => item?.isMuted).length;

  return {
    sessions,
    total,
    mutedCount,
    generatedAt: result?.generatedAt ?? new Date().toISOString(),
    changed: typeof result?.changed === "boolean" ? result.changed : undefined,
    changedSessionID: result?.changedSessionID,
  };
}
