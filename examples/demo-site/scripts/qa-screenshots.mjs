#!/usr/bin/env node
/**
 * Visual QA for the bundled demo site.
 * Uses Playwright Chromium. First run may download the browser.
 */
import { spawnSync } from "node:child_process";
import { createServer } from "node:http";
import { readFileSync, mkdirSync, existsSync, writeFileSync } from "node:fs";
import { dirname, join, extname } from "node:path";
import { fileURLToPath } from "node:url";
import { createRequire } from "node:module";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const dist = join(root, "dist");
const outDir = join(root, "qa-screenshots");
const require = createRequire(import.meta.url);

if (!existsSync(join(dist, "index.html"))) {
  console.error("dist/ missing — run npm run build first");
  process.exit(1);
}

function loadPlaywright() {
  try {
    return require("playwright");
  } catch {
    console.error("playwright not installed — run npm install in examples/demo-site");
    process.exit(1);
  }
}

const mime = {
  ".html": "text/html; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".json": "application/json",
  ".png": "image/png",
  ".svg": "image/svg+xml",
};

function serveDist(port) {
  return new Promise((resolve) => {
    const server = createServer((req, res) => {
      const url = new URL(req.url || "/", `http://127.0.0.1:${port}`);
      const path = url.pathname === "/" ? "/index.html" : url.pathname;
      const file = join(dist, path);
      if (!file.startsWith(dist) || !existsSync(file)) {
        res.writeHead(404);
        res.end("not found");
        return;
      }
      res.writeHead(200, { "Content-Type": mime[extname(file)] || "application/octet-stream" });
      res.end(readFileSync(file));
    });
    server.listen(port, "127.0.0.1", () => resolve(server));
  });
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function main() {
  const { chromium } = loadPlaywright();
  mkdirSync(outDir, { recursive: true });

  let browser;
  try {
    browser = await chromium.launch({ headless: true });
  } catch {
    console.log("Chromium missing — installing via playwright…");
    const r = spawnSync("npx", ["playwright", "install", "chromium"], {
      cwd: root,
      stdio: "inherit",
      shell: process.platform === "win32",
    });
    if (r.status !== 0) process.exit(r.status || 1);
    browser = await chromium.launch({ headless: true });
  }

  const port = 4177;
  const server = await serveDist(port);
  const page = await browser.newPage({ viewport: { width: 1280, height: 800 } });
  await page.goto(`http://127.0.0.1:${port}/`, { waitUntil: "networkidle" });
  await sleep(400);
  await page.screenshot({ path: join(outDir, "01-home-desktop.png"), fullPage: true });

  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto(`http://127.0.0.1:${port}/`, { waitUntil: "networkidle" });
  await sleep(300);
  await page.screenshot({ path: join(outDir, "02-home-mobile.png"), fullPage: true });

  writeFileSync(
    join(outDir, "manifest.json"),
    JSON.stringify(
      {
        capturedAt: new Date().toISOString(),
        shots: ["01-home-desktop.png", "02-home-mobile.png"],
      },
      null,
      2,
    ) + "\n",
  );

  await browser.close();
  server.close();
  console.log(`qa screenshots → ${outDir}`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
