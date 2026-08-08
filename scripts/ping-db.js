#!/usr/bin/env node
/**
 * Smoke-test SurrealDB connectivity using a Vault-backed password.
 *
 *   cp .env.example .env   # fill from 1Password
 *   npm install
 *   npm run db:ping
 *
 * Or with unresolved op:// strings in .env:
 *   npm run db:ping:op
 */

import { pingSurreal } from "../src/db/connect.js";

try {
  const summary = await pingSurreal();
  console.log("SurrealDB ping OK");
  console.log(
    JSON.stringify(
      {
        url: summary.url,
        namespace: summary.namespace,
        database: summary.database,
        result: summary.result,
      },
      null,
      2,
    ),
  );
  process.exit(0);
} catch (err) {
  console.error("SurrealDB ping FAILED");
  console.error(err?.stack || err?.message || err);
  process.exit(1);
}
