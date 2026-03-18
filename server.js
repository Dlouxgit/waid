import http from "node:http";
import { createReadStream } from "node:fs";
import { access } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { UsageStore } from "./src/store.js";
import { TrackerService } from "./src/tracker.js";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const publicDir = path.join(__dirname, "public");
const dataFilePath = path.join(__dirname, "data", "usage-data.json");
const host = "127.0.0.1";
const port = Number.parseInt(process.env.PORT ?? "4312", 10);

const store = new UsageStore(dataFilePath);
const tracker = new TrackerService({ rootDir: __dirname, store });
const clients = new Set();

function sendJson(response, statusCode, payload) {
  response.writeHead(statusCode, {
    "Content-Type": "application/json; charset=utf-8",
    "Cache-Control": "no-store",
  });
  response.end(`${JSON.stringify(payload)}\n`);
}

function contentTypeFor(filePath) {
  if (filePath.endsWith(".css")) {
    return "text/css; charset=utf-8";
  }
  if (filePath.endsWith(".js")) {
    return "application/javascript; charset=utf-8";
  }
  if (filePath.endsWith(".html")) {
    return "text/html; charset=utf-8";
  }
  if (filePath.endsWith(".png")) {
    return "image/png";
  }
  if (filePath.endsWith(".webp")) {
    return "image/webp";
  }
  return "application/octet-stream";
}

async function serveStatic(response, targetPath) {
  try {
    await access(targetPath);
  } catch {
    response.writeHead(404);
    response.end("Not found");
    return;
  }

  response.writeHead(200, {
    "Content-Type": contentTypeFor(targetPath),
    "Cache-Control": "no-store",
  });
  createReadStream(targetPath).pipe(response);
}

function writeSse(response, payload) {
  response.write(`data: ${JSON.stringify(payload)}\n\n`);
}

function broadcastSnapshot() {
  if (clients.size === 0) {
    return;
  }

  const payload = tracker.snapshot();

  for (const client of clients) {
    writeSse(client, payload);
  }
}

const server = http.createServer(async (request, response) => {
  const url = new URL(request.url ?? "/", `http://${request.headers.host ?? `${host}:${port}`}`);

  if (request.method === "GET" && url.pathname === "/api/dashboard") {
    sendJson(response, 200, tracker.snapshot());
    return;
  }

  if (request.method === "GET" && url.pathname === "/events") {
    response.writeHead(200, {
      "Content-Type": "text/event-stream; charset=utf-8",
      "Cache-Control": "no-store",
      Connection: "keep-alive",
    });
    response.write("retry: 1000\n\n");
    clients.add(response);
    writeSse(response, tracker.snapshot());

    request.on("close", () => {
      clients.delete(response);
    });
    return;
  }

  if (request.method !== "GET") {
    response.writeHead(405);
    response.end("Method not allowed");
    return;
  }

  const relativePath =
    url.pathname === "/" ? "index.html" : url.pathname.replace(/^\/+/, "");
  const targetPath = path.join(publicDir, relativePath);

  if (!targetPath.startsWith(publicDir)) {
    response.writeHead(404);
    response.end("Not found");
    return;
  }

  await serveStatic(response, targetPath);
});

server.on("error", (error) => {
  console.error(error);
  process.exit(1);
});

tracker.on("update", () => {
  broadcastSnapshot();
});

async function shutdown() {
  for (const client of clients) {
    client.end();
  }

  await tracker.stop();
  server.close(() => {
    process.exit(0);
  });
}

process.on("SIGINT", shutdown);
process.on("SIGTERM", shutdown);

await tracker.start();

server.listen(port, host, () => {
  console.log(`Waid is running at http://${host}:${port}`);
});
