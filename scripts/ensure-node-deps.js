#!/usr/bin/env node
/**
 * Ensure Node packages required by lint:js / tooling are installed.
 *
 * Runs `npm install` when eslint (or node_modules) is missing. Safe to run
 * repeatedly (no-op when deps are already present).
 */
import { spawnSync } from "node:child_process";
import { existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const eslintBin = join(root, "node_modules", "eslint", "bin", "eslint.js");

function main() {
  if (existsSync(eslintBin)) {
    process.exit(0);
  }

  console.error(
    "Missing Node deps (eslint). Running npm install …",
  );
  const result = spawnSync("npm", ["install"], {
    cwd: root,
    stdio: "inherit",
    shell: process.platform === "win32",
  });
  if (result.status !== 0) {
    console.error("npm install failed; install deps manually with: npm install");
    process.exit(result.status ?? 1);
  }
  if (!existsSync(eslintBin)) {
    console.error(
      `npm install finished but ${eslintBin} is still missing. Check package.json devDependencies.`,
    );
    process.exit(1);
  }
  process.exit(0);
}

main();
