import assert from "node:assert/strict";
import test from "node:test";
import {
  loadChromiumOrSkip,
  startStaticServer,
  stopServer,
} from "./support/static-vizcore-server.mjs";

const testName = "browser regression keeps the WebGL canvas visible and nonblank";
const chromium = await loadChromiumOrSkip(test, testName);

if (chromium) {
  test(testName, async (t) => {
    const server = await startStaticServer();
    const browser = await chromium.launch({ headless: true });
    t.after(async () => {
      await browser.close();
      await stopServer(server.instance);
    });

    const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
    await page.goto(`${server.url}?projector=1`, { waitUntil: "domcontentloaded" });
    await page.waitForSelector("#vizcore-canvas");
    await page.waitForTimeout(250);

    const stats = await page.evaluate(() => {
      const canvas = document.querySelector("#vizcore-canvas");
      const gl = canvas?.getContext("webgl2");
      if (!canvas || !gl) return null;

      const width = Math.min(96, canvas.width);
      const height = Math.min(54, canvas.height);
      const pixels = new Uint8Array(width * height * 4);
      gl.readPixels(0, 0, width, height, gl.RGBA, gl.UNSIGNED_BYTE, pixels);
      let litPixels = 0;
      let totalLuma = 0;
      for (let index = 0; index < pixels.length; index += 4) {
        const luma = pixels[index] + pixels[index + 1] + pixels[index + 2];
        totalLuma += luma;
        if (luma > 10 && pixels[index + 3] > 0) {
          litPixels += 1;
        }
      }
      return { litPixels, averageLuma: totalLuma / (width * height), width, height };
    });

    assert.ok(stats);
    assert.ok(stats.width > 0);
    assert.ok(stats.height > 0);
    assert.ok(stats.litPixels > stats.width * stats.height * 0.8);
    assert.ok(stats.averageLuma > 10);
  });
}
