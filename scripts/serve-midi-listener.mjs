import { createServer } from "node:http";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, extname, join, normalize, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";
import { analyzeMidiCapabilities, formatCapabilityReportMarkdown } from "../src/midi/capability-analysis.js";
import { validateCapabilityInventory } from "../src/midi/capability-schema.js";
import { OUTPUT_LAB_KIND, validateOutputLabLog } from "../src/midi/output-lab.js";

const scriptDirectory = dirname(fileURLToPath(import.meta.url));
const repositoryRoot = resolve(scriptDirectory, "..");
const staticRoot = join(repositoryRoot, "src");
const port = parsePort(process.argv);
const host = "127.0.0.1";
const maxBodyBytes = 64 * 1024 * 1024;

const mimeTypes = {
  ".css": "text/css; charset=utf-8",
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".json": "application/json; charset=utf-8"
};

const server = createServer(async (request, response) => {
  try {
    setSecurityHeaders(response, port);
    const requestUrl = new URL(request.url || "/", `http://${host}:${port}`);

    if (request.method === "POST" && requestUrl.pathname === "/api/save-inventory") {
      await saveInventory(request, response, port);
      return;
    }

    if (request.method !== "GET" && request.method !== "HEAD") {
      sendJson(response, 405, { error: "Method not allowed" });
      return;
    }

    if (requestUrl.pathname === "/") {
      response.writeHead(302, { Location: "/midi-listener/" });
      response.end();
      return;
    }

    await serveStaticFile(requestUrl.pathname, request.method === "HEAD", response);
  } catch (error) {
    sendJson(response, 500, { error: "Local listener server error" });
    console.error(error);
  }
});

server.listen(port, host, () => {
  console.log(`MIDI listener ready at http://${host}:${port}/midi-listener/`);
});

function parsePort(argumentsList) {
  const index = argumentsList.indexOf("--port");
  const raw = index >= 0 ? argumentsList[index + 1] : "8765";
  const parsed = Number(raw);
  if (!Number.isInteger(parsed) || parsed < 1024 || parsed > 65535) {
    throw new Error(`Invalid port: ${raw}`);
  }
  return parsed;
}

async function serveStaticFile(urlPath, headOnly, response) {
  let decodedPath;
  try {
    decodedPath = decodeURIComponent(urlPath);
  } catch {
    sendJson(response, 400, { error: "Invalid URL encoding" });
    return;
  }

  const relativePath = decodedPath.endsWith("/")
    ? `${decodedPath.slice(1)}index.html`
    : decodedPath.slice(1);
  const requestedPath = resolve(staticRoot, normalize(relativePath));
  if (requestedPath !== staticRoot && !requestedPath.startsWith(`${staticRoot}${sep}`)) {
    sendJson(response, 403, { error: "Forbidden" });
    return;
  }

  try {
    const data = await readFile(requestedPath);
    response.writeHead(200, {
      "Content-Type": mimeTypes[extname(requestedPath).toLowerCase()] || "application/octet-stream",
      "Cache-Control": "no-store"
    });
    response.end(headOnly ? undefined : data);
  } catch (error) {
    if (error.code === "ENOENT" || error.code === "EISDIR") {
      sendJson(response, 404, { error: "Not found" });
      return;
    }
    throw error;
  }
}

async function saveInventory(request, response, listenerPort) {
  const allowedOrigins = new Set([
    `http://127.0.0.1:${listenerPort}`,
    `http://localhost:${listenerPort}`
  ]);
  const origin = request.headers.origin;
  if (origin && !allowedOrigins.has(origin)) {
    sendJson(response, 403, { error: "Origin not allowed" });
    return;
  }
  if (!(request.headers["content-type"] || "").startsWith("application/json")) {
    sendJson(response, 415, { error: "Expected application/json" });
    return;
  }

  const chunks = [];
  let bytes = 0;
  for await (const chunk of request) {
    bytes += chunk.length;
    if (bytes > maxBodyBytes) {
      sendJson(response, 413, { error: "Inventory is too large" });
      request.destroy();
      return;
    }
    chunks.push(chunk);
  }

  let inventory;
  try {
    inventory = JSON.parse(Buffer.concat(chunks).toString("utf8"));
  } catch {
    sendJson(response, 400, { error: "Invalid JSON" });
    return;
  }
  if (!inventory || typeof inventory !== "object" || Array.isArray(inventory)) {
    sendJson(response, 400, { error: "Inventory must be a JSON object" });
    return;
  }
  const isOutputLab = inventory.kind === OUTPUT_LAB_KIND;
  if (isOutputLab) {
    const validationError = validateOutputLabLog(inventory);
    if (validationError) {
      sendJson(response, 422, { error: validationError });
      return;
    }
  } else if (inventory.schemaVersion === 2) {
    const validationError = validateCapabilityInventory(inventory);
    if (validationError) {
      sendJson(response, 422, { error: validationError });
      return;
    }
  } else if (inventory.schemaVersion !== 1) {
    sendJson(response, 422, { error: "Unsupported inventory schemaVersion" });
    return;
  }

  const outputDirectory = join(repositoryRoot, "private", "midi");
  await mkdir(outputDirectory, { recursive: true });
  const timestamp = new Date().toISOString().replaceAll(":", "-").replaceAll(".", "-");
  const prefix = isOutputLab
    ? "output-lab"
    : inventory.schemaVersion === 2 ? "capability-census" : "control-inventory";
  const fileName = `${prefix}-${timestamp}.json`;
  const outputPath = join(outputDirectory, fileName);
  const stored = {
    ...inventory,
    storedAt: new Date().toISOString(),
    privacy: "Local MIDI inventory. Keep private and out of Git."
  };
  await writeFile(outputPath, `${JSON.stringify(stored, null, 2)}\n`, "utf8");

  let reportRelativePath = null;
  let reportError = null;
  if (!isOutputLab && inventory.schemaVersion === 2) {
    try {
      const reportName = fileName.replace(/\.json$/i, "-analysis.md");
      const reportPath = join(outputDirectory, reportName);
      const report = formatCapabilityReportMarkdown(analyzeMidiCapabilities(stored));
      await writeFile(reportPath, report, "utf8");
      reportRelativePath = relative(repositoryRoot, reportPath).split(sep).join("/");
    } catch (error) {
      reportError = String(error.message || error);
      console.error("Could not generate MIDI capability analysis", error);
    }
  }

  sendJson(response, 201, {
    saved: true,
    relativePath: relative(repositoryRoot, outputPath).split(sep).join("/"),
    reportRelativePath,
    reportError
  });
}

function setSecurityHeaders(response, listenerPort) {
  response.setHeader("Content-Security-Policy", "default-src 'self'; script-src 'self'; style-src 'self'; connect-src 'self'; img-src 'self' data:; object-src 'none'; base-uri 'none'; frame-ancestors 'none'");
  response.setHeader("Permissions-Policy", "midi=(self)");
  response.setHeader("X-Content-Type-Options", "nosniff");
  response.setHeader("Referrer-Policy", "no-referrer");
  response.setHeader("Cross-Origin-Resource-Policy", "same-origin");
  response.setHeader("Access-Control-Allow-Origin", `http://127.0.0.1:${listenerPort}`);
}

function sendJson(response, statusCode, value) {
  if (response.headersSent) return;
  response.writeHead(statusCode, {
    "Content-Type": "application/json; charset=utf-8",
    "Cache-Control": "no-store"
  });
  response.end(`${JSON.stringify(value)}\n`);
}
