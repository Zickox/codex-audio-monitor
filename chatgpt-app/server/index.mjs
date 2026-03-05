import { createAudioMcpHttpServer } from "./mcp-server.mjs";

const runtime = createAudioMcpHttpServer();

await runtime.start();
console.log(`Audio MCP server listening on http://localhost:${runtime.port}/mcp`);

function shutdown() {
  runtime
    .stop()
    .catch(() => {
      // Ignore shutdown errors to avoid hanging on process termination.
    })
    .finally(() => {
      process.exit(0);
    });
}

process.on("SIGINT", shutdown);
process.on("SIGTERM", shutdown);
