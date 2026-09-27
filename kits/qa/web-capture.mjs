#!/usr/bin/env node
/**
 * Shared Playwright visual-QA capture for LaunchPilot marketing sites.
 *
 * Playwright is loaded from --root/node_modules (the product site), not from
 * LaunchPilot — so this file can live in kits/qa without its own deps.
 *
 * Usage:
 *   node web-capture.mjs --root /path/to/site [--out qa-screenshots]
 *     [--routes /, /privacy, /terms]
 *     [--port 4174]
 */
import { createServer } from "node:http";
import {
  existsSync,
  mkdirSync,
  readFileSync,
  statSync,
  writeFileSync,
} from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";
import { pathToFileURL } from "node:url";

function parseArgs(argv) {
  const out = {
    root: process.cwd(),
    outDir: "qa-screenshots",
    routes: ["/", "/privacy", "/terms"],
    port: 4174,
    scrollStep: 900,
  };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--root") out.root = path.resolve(argv[++i]);
    else if (a === "--out") out.outDir = argv[++i];
    else if (a === "--port") out.port = Number(argv[++i]);
    else if (a === "--scroll-step") out.scrollStep = Number(argv[++i]);
    else if (a === "--routes") {
      const list = [];
      while (argv[i + 1] && !argv[i + 1].startsWith("--")) {
        list.push(argv[++i]);
      }
      if (list.length) out.routes = list;
    } else if (a === "-h" || a === "--help") {
      console.log(
        `Usage: node web-capture.mjs --root DIR [--routes / /privacy] [--out qa-screenshots]`,
      );
      process.exit(0);
    }
  }
  return out;
}

const MIME = {
  ".html": "text/html",
  ".js": "text/javascript",
  ".css": "text/css",
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".jpeg": "image/jpeg",
  ".svg": "image/svg+xml",
  ".webp": "image/webp",
  ".txt": "text/plain",
  ".json": "application/json",
  ".woff": "font/woff",
  ".woff2": "font/woff2",
};

function slugRoute(route) {
  if (route === "/" || route === "") return "home";
  return route.replace(/^\/+|\/+$/g, "").replace(/[^\w.-]+/g, "-") || "home";
}

function loadPlaywright(root) {
  const pkg = path.join(root, "package.json");
  if (!existsSync(pkg)) {
    throw new Error(`No package.json under --root ${root}`);
  }
  const require = createRequire(pkg);
  try {
    return require("playwright");
  } catch {
    throw new Error(
      `playwright not found in ${root}/node_modules — run npm install in the site repo`,
    );
  }
}

async function main() {
  const opts = parseArgs(process.argv.slice(2));
  const dist = path.join(opts.root, "dist");
  const out = path.isAbsolute(opts.outDir)
    ? opts.outDir
    : path.join(opts.root, opts.outDir);

  if (!existsSync(dist)) {
    console.error("Missing dist/. Run npm run build first.");
    process.exit(1);
  }
  mkdirSync(out, { recursive: true });

  const { chromium } = loadPlaywright(opts.root);

  const server = createServer((req, res) => {
    const urlPath = decodeURIComponent((req.url ?? "/").split("?")[0]);
    let filePath = path.join(dist, urlPath === "/" ? "index.html" : urlPath);
    if (!existsSync(filePath) || statSync(filePath).isDirectory()) {
      const asHtml = path.join(dist, `${urlPath.replace(/^\//, "")}.html`);
      if (existsSync(asHtml)) filePath = asHtml;
      else filePath = path.join(dist, "index.html");
    }
    const ext = path.extname(filePath);
    res.writeHead(200, { "Content-Type": MIME[ext] ?? "application/octet-stream" });
    res.end(readFileSync(filePath));
  });

  await new Promise((resolve) => server.listen(opts.port, "127.0.0.1", resolve));
  const base = `http://127.0.0.1:${opts.port}`;

  const browser = await chromium.launch();
  const captured = [];

  const viewports = [
    { name: "desktop", width: 1280, height: 900 },
    { name: "mobile", width: 390, height: 844 },
  ];

  for (const route of opts.routes) {
    const slug = slugRoute(route);
    for (const vp of viewports) {
      const page = await browser.newPage({
        viewport: { width: vp.width, height: vp.height },
      });
      const url = `${base}${route.startsWith("/") ? route : `/${route}`}`;
      const resp = await page.goto(url, { waitUntil: "networkidle", timeout: 60000 });
      const status = resp?.status() ?? 0;
      if (status >= 400) {
        console.warn(`skip ${url} (HTTP ${status})`);
        await page.close();
        continue;
      }
      await page.waitForTimeout(400);
      const hero = path.join(out, `web-${slug}-${vp.name}-hero.png`);
      await page.screenshot({ path: hero });
      captured.push(path.basename(hero));

      if (vp.name === "desktop") {
        const totalHeight = await page.evaluate(() => document.body.scrollHeight);
        const positions = [];
        for (let y = 0; y < totalHeight; y += opts.scrollStep) positions.push(y);
        if (positions.at(-1) !== totalHeight) positions.push(totalHeight);
        for (let i = 0; i < positions.length; i++) {
          await page.evaluate((y) => window.scrollTo(0, y), positions[i]);
          await page.waitForTimeout(350);
          const label = String(i + 1).padStart(2, "0");
          const scrollPath = path.join(
            out,
            `web-${slug}-desktop-scroll-${label}.png`,
          );
          await page.screenshot({ path: scrollPath });
          captured.push(path.basename(scrollPath));
        }
        await page.evaluate(() => window.scrollTo(0, 0));
        await page.waitForTimeout(200);
        const full = path.join(out, `web-${slug}-desktop-fullpage.png`);
        await page.screenshot({ path: full, fullPage: true });
        captured.push(path.basename(full));
      }
      await page.close();
    }
  }

  await browser.close();
  server.close();

  const manifest = {
    kind: "web-visual-qa",
    root: opts.root,
    out,
    routes: opts.routes,
    files: captured,
    captured_at: new Date().toISOString(),
  };
  writeFileSync(path.join(out, "qa-manifest.json"), JSON.stringify(manifest, null, 2));
  console.log(`Saved ${captured.length} screenshot(s) to ${out}`);
}

export { main as captureWebQa };

if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((e) => {
    console.error(e);
    process.exit(1);
  });
}
