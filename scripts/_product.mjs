#!/usr/bin/env node
// Read config/products.json. With no args: print product keys (one per line).
// With <product>: print shell assignments P_<FIELD>='value' for eval in bash.
// With <product> <field>: print just that field's value.
import { existsSync, readFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const [, , product, field] = process.argv;
const configDir = join(dirname(fileURLToPath(import.meta.url)), "..", "config");
const productsPath = join(configDir, "products.json");

if (!existsSync(productsPath)) {
  console.error("missing config/products.json");
  console.error("copy config/products.example.json to config/products.json and add your products");
  process.exit(1);
}

const validation = spawnSync(
  "python3",
  [join(configDir, "..", "scripts", "validate-products.py"), productsPath],
  { encoding: "utf8" },
);
if (validation.error || validation.status !== 0) {
  const detail = validation.stderr?.trim() || validation.error?.message || "validation failed";
  console.error(detail);
  process.exit(validation.status || 1);
}

const reg = JSON.parse(readFileSync(productsPath, "utf8"));

if (!product) {
  console.log(Object.keys(reg).join("\n"));
  process.exit(0);
}

const p = reg[product];
if (!p) {
  console.error(`unknown product: ${product}`);
  console.error(`known: ${Object.keys(reg).join(", ")}`);
  process.exit(1);
}

if (field) {
  process.stdout.write(String(p[field] ?? ""));
  process.exit(0);
}

const esc = (v) => {
  if (v === null || v === undefined) return "";
  if (typeof v === "object") {
    return JSON.stringify(v).replace(/'/g, "'\\''");
  }
  return String(v).replace(/'/g, "'\\''");
};
for (const [k, v] of Object.entries(p)) {
  console.log(`P_${k.toUpperCase()}='${esc(v)}'`);
}
