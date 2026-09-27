#!/usr/bin/env node
import { cpSync, mkdirSync, rmSync, existsSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const dist = join(root, "dist");

if (existsSync(dist)) rmSync(dist, { recursive: true, force: true });
mkdirSync(dist, { recursive: true });

for (const file of ["index.html", "styles.css"]) {
  cpSync(join(root, file), join(dist, file));
}

writeFileSync(
  join(dist, "build.json"),
  JSON.stringify({ builtAt: new Date().toISOString(), product: "northline-demo" }, null, 2) + "\n",
);

console.log("built dist/ (index.html, styles.css, build.json)");
