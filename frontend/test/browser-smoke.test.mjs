import assert from "node:assert/strict";
import test from "node:test";
import {
  loadChromiumOrSkip,
  startStaticServer,
  stopServer,
} from "./support/static-vizcore-server.mjs";

const testName = "browser smoke renders the frontend canvas";
const chromium = await loadChromiumOrSkip(test, testName);

if (chromium) {
  test(testName, async (t) => {
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
