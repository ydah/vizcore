import fs from "node:fs/promises";
import { createRequire } from "node:module";
import path from "node:path";
import { fileURLToPath } from "node:url";

const frontendRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../frontend");
const requireFromFrontend = createRequire(path.join(frontendRoot, "package.json"));

const options = parseArgs(process.argv.slice(2));

if (!options.url) {
  console.error("Usage: node scripts/browser_capture.mjs URL --out browser-capture.png [--selector #vizcore-canvas] [--wait 1000] [--wait-for-frame]");
  process.exit(1);
}

let chromium;
try {
  ({ chromium } = requireFromFrontend("playwright"));
} catch {
  console.error("Playwright is required for browser capture. Install it with `npm install --prefix frontend`.");
  process.exit(2);
}

const browser = await chromium.launch({ headless: true });
try {
  const page = await browser.newPage({ viewport: { width: options.width, height: options.height } });
  await page.goto(options.url, { waitUntil: "domcontentloaded" });
  if (options.wait > 0) {
    await page.waitForTimeout(options.wait);
  }

  const element = await resolveCaptureLocator(page, options.selector);
  await element.waitFor({ state: "visible", timeout: 10000 });
  if (options.waitForFrame) {
    await waitForVizcoreFrame(page, options.frameTimeout);
  }
  await fs.mkdir(path.dirname(options.out), { recursive: true });
  await element.screenshot({ path: options.out });
  console.log(`Browser capture written: ${options.out}`);
} finally {
  await browser.close();
}

async function resolveCaptureLocator(page, selector) {
  const candidates = [...new Set([selector, "#vizcore-canvas", "canvas"].filter(Boolean))];
  for (const candidate of candidates) {
    const locator = page.locator(candidate).first();
    if (await locator.count().catch(() => 0) > 0) {
      return locator;
    }
  }
  return page.locator(selector).first();
}

async function waitForVizcoreFrame(page, timeout) {
  await page.waitForFunction(
    () => Number(document.body?.dataset?.vizcoreFrameCount || 0) > 0,
    null,
    { timeout }
  );
}

function parseArgs(args) {
  const parsed = {
    url: null,
    out: "browser-capture.png",
    selector: "#vizcore-canvas",
    wait: 1000,
    width: 1280,
    height: 720,
    waitForFrame: false,
    frameTimeout: 10000,
  };

  for (let index = 0; index < args.length; index += 1) {
    const value = args[index];
    if (value === "--out") {
      parsed.out = String(args[index + 1] || parsed.out);
      index += 1;
    } else if (value === "--selector") {
      parsed.selector = String(args[index + 1] || parsed.selector);
      index += 1;
    } else if (value === "--wait") {
      parsed.wait = finiteNumber(args[index + 1], parsed.wait);
      index += 1;
    } else if (value === "--width") {
      parsed.width = finiteNumber(args[index + 1], parsed.width);
      index += 1;
    } else if (value === "--height") {
      parsed.height = finiteNumber(args[index + 1], parsed.height);
      index += 1;
    } else if (value === "--wait-for-frame") {
      parsed.waitForFrame = true;
    } else if (value === "--frame-timeout") {
      parsed.frameTimeout = finiteNumber(args[index + 1], parsed.frameTimeout);
      index += 1;
    } else if (!parsed.url) {
      parsed.url = value;
    }
  }

  parsed.out = path.resolve(parsed.out);
  return parsed;
}

function finiteNumber(value, fallback) {
  const numeric = Number(value);
  return Number.isFinite(numeric) ? numeric : fallback;
}
