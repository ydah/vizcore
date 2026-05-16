import fs from "node:fs/promises";
import http from "node:http";
import path from "node:path";
import { fileURLToPath } from "node:url";

const frontendRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");

export const loadChromiumOrSkip = async (test, name) => {
  try {
    const { chromium } = await import("playwright");
    return chromium;
  } catch {
    if (process.env.VIZCORE_BROWSER_TEST_REQUIRED === "1") {
      throw new Error("Playwright is required for browser tests.");
    }
    test(name, { skip: "Install Playwright to run browser tests." }, () => {});
    return null;
  }
};

export const startStaticServer = async ({ runtime = {} } = {}) => {
  const instance = http.createServer(async (request, response) => {
    const url = new URL(request.url || "/", "http://127.0.0.1");
    if (url.pathname === "/runtime") {
      const body = JSON.stringify({
        status: "ok",
        audio_source: "dummy",
        scene_names: ["basic"],
        key_mappings: [],
        control_preset: {},
        projector_mode: false,
        ...runtime,
      });
      response.writeHead(200, {
        "content-type": "application/json; charset=utf-8",
        "content-length": Buffer.byteLength(body),
      });
      response.end(body);
      return;
    }

    const filePath = resolveStaticPath(url.pathname);
    if (!filePath) {
      response.writeHead(404, { "content-type": "text/plain; charset=utf-8" });
      response.end("Not Found");
      return;
    }

    try {
      const body = await fs.readFile(filePath);
      response.writeHead(200, { "content-type": contentType(filePath) });
      response.end(body);
    } catch {
      response.writeHead(404, { "content-type": "text/plain; charset=utf-8" });
      response.end("Not Found");
    }
  });

  await new Promise((resolve) => instance.listen(0, "127.0.0.1", resolve));
  const address = instance.address();
  return {
    instance,
    url: `http://127.0.0.1:${address.port}/`,
  };
};

export const stopServer = (server) => new Promise((resolve, reject) => {
  server.close((error) => (error ? reject(error) : resolve()));
});

const resolveStaticPath = (pathname) => {
  const relativePath = pathname === "/" ? "index.html" : pathname.slice(1);
  const filePath = path.resolve(frontendRoot, relativePath);
  return filePath.startsWith(frontendRoot) ? filePath : null;
};

const contentType = (filePath) => {
  if (filePath.endsWith(".html")) return "text/html; charset=utf-8";
  if (filePath.endsWith(".js")) return "text/javascript; charset=utf-8";
  if (filePath.endsWith(".css")) return "text/css; charset=utf-8";
  return "application/octet-stream";
};
