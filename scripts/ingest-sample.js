#!/usr/bin/env node
/**
 * Hello-world ingest: upsert one corpus requirement into SurrealDB and read it back.
 *
 *   npm run db:ingest-sample
 */

import { readFileSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { RecordId } from "surrealdb";
import { connectSurreal } from "../src/db/connect.js";

function parseYaml(text) {
  return JSON.parse(
    execFileSync(
      "python3",
      [
        "-c",
        "import sys,yaml,json; print(json.dumps(yaml.safe_load(sys.stdin.read())))",
      ],
      { input: text, encoding: "utf8" },
    ),
  );
}

const path =
  process.argv[2] ||
  "frameworks/annex-sl-core/1.0/requirements/4.1-context.yaml";

try {
  const doc = parseYaml(readFileSync(path, "utf8"));
  if (!doc?.id) throw new Error(`YAML at ${path} is missing required field id`);

  const db = await connectSurreal();
  try {
    const key = doc.id;
    const rid = new RecordId("requirement", key);
    const content = {
      ...doc,
      source_path: path,
      ingested_at: new Date().toISOString(),
    };

    const written = await db.upsert(rid).content(content);
    const selected = await db.query(
      `SELECT id, title, framework, ref, source_path, domains FROM type::record("requirement", $key);`,
      { key },
    );

    console.log("ingest-sample OK");
    console.log(JSON.stringify({ key, written, selected }, null, 2));
  } finally {
    await db.close();
  }
  process.exit(0);
} catch (err) {
  console.error("ingest-sample FAILED");
  console.error(err?.stack || err?.message || err);
  process.exit(1);
}
