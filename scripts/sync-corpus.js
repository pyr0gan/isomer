#!/usr/bin/env node
/**
 * Sync the YAML corpus into SurrealDB.
 *
 *   npm run db:sync              # full sync (upsert + prune)
 *   npm run db:sync -- --dry-run # load + report only
 *   npm run db:sync -- --no-prune
 */

import { syncCorpus } from "../src/db/sync.js";

const args = new Set(process.argv.slice(2));
const dryRun = args.has("--dry-run");
const prune = !args.has("--no-prune");

try {
  const result = await syncCorpus({ dryRun, prune });
  console.log(dryRun ? "corpus sync dry-run OK" : "corpus sync OK");
  console.log(
    JSON.stringify(
      {
        written: result.written,
        sync_sha: result.syncSha,
        counts: result.counts,
        deleted_counts: Object.fromEntries(
          Object.entries(result.deleted).map(([k, v]) => [k, v.length]),
        ),
        sync_run: result.sync_run ?? null,
      },
      null,
      2,
    ),
  );
  process.exit(0);
} catch (err) {
  console.error("corpus sync FAILED");
  console.error(err?.message || err);
  if (err?.cause) {
    const c = err.cause;
    console.error(
      "cause:",
      c?.code || c?.name || "",
      c?.message || c,
    );
  }
  if (process.env.DEBUG_SYNC) {
    console.error(err?.stack || err);
  }
  process.exit(1);
}
