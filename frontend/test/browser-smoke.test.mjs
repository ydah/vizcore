import assert from "node:assert/strict";
import fs from "node:fs/promises";
import http from "node:http";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

let chromium = null;
try {
  ({ chromium } = await import("playwright"));
} catch {
  test("browser smoke renders the frontend canvas", { skip: "Install Playwright to run browser smoke tests." }, () => {});
}

if (chromium) {
  test("browser smoke renders the frontend canvas", async (t) => {
    const server = await startStaticServer();
    const browser = await chromium.launch({ headless: true });
    t.after(async () => {
      await browser.close();
      await stopServer(server.instance);
    });

    const page = await browser.newPage({ viewport: { width: 960, height: 540 } });
    const pageErrors = [];
    page.on("pageerror", (error) => pageErrors.push(error.message));

    await page.goto(server.url, { waitUntil: "domcontentloaded" });
    await page.waitForSelector("#vizcore-canvas");
    const canvasBox = await page.locator("#vizcore-canvas").boundingBox();

    assert.ok(canvasBox.width >= 300);
    assert.ok(canvasBox.height >= 200);
    await page.waitForFunction(() => {
      const canvas = document.querySelector("#vizcore-canvas");
      if (!canvas?.width || !canvas?.height) return false;
      const gl = canvas.getContext("webgl2");
      if (!gl) return false;
      const pixels = new Uint8Array(4);
      gl.readPixels(
        Math.floor(canvas.width / 2),
        Math.floor(canvas.height / 2),
        1,
        1,
        gl.RGBA,
        gl.UNSIGNED_BYTE,
        pixels,
      );
      return pixels[3] > 0 && pixels[0] + pixels[1] + pixels[2] > 0;
    });
    assert.deepEqual(pageErrors, []);
  });
}

const frontendRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");

const startStaticServer = async () => {
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

const stopServer = (server) => new Promise((resolve, reject) => {
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
