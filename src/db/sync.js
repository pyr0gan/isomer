import { RecordId } from "surrealdb";
import {
  loadCorpus,
  domainKey,
  frameworkKey,
  requirementKey,
  mappingSetKey,
  rulesetKey,
  rubricKey,
  flattenMappingEdges,
} from "../corpus/load.js";
import { connectSurreal } from "./connect.js";
import { CONTENT_SOURCE_REPO } from "./params.js";
import { ensureCorpusSchema } from "./schema.js";

function syncMeta({ sourcePath, syncSha, syncedAt }) {
  return {
    // Value matches DEFINE PARAM $isomer_content_source
    content_source: CONTENT_SOURCE_REPO,
    source_path: sourcePath,
    sync_sha: syncSha,
    synced_at: syncedAt,
  };
}

async function upsertRecord(db, table, key, content) {
  const rid = new RecordId(table, key);
  return db.upsert(rid).content(content);
}

async function listCorpusManagedIds(db, table) {
  // $isomer_content_source is a database DEFINE PARAM (not a bind var).
  const result = await db.query(
    `SELECT id FROM type::table($table) WHERE content_source = $isomer_content_source;`,
    { table },
  );
  const rows = result?.[0] ?? [];
  return rows
    .map((row) => {
      const id = row.id;
      if (id == null) return null;
      // RecordId stringifies like table:⟨key⟩ or table:key
      if (typeof id === "object" && id.id != null) return String(id.id);
      const s = String(id);
      const idx = s.indexOf(":");
      if (idx === -1) return s;
      let key = s.slice(idx + 1);
      if (key.startsWith("⟨") && key.endsWith("⟩")) key = key.slice(1, -1);
      return key;
    })
    .filter(Boolean);
}

async function deleteMissing(db, table, keepKeys) {
  const existing = await listCorpusManagedIds(db, table);
  const keep = new Set(keepKeys);
  const toDelete = existing.filter((k) => !keep.has(k));
  for (const key of toDelete) {
    await db.delete(new RecordId(table, key));
  }
  return toDelete;
}

/**
 * Sync the on-disk corpus into SurrealDB.
 *
 * @param {object} [options]
 * @param {boolean} [options.dryRun=false] Load + report only; do not write
 * @param {boolean} [options.prune=true] Delete repo-managed records absent from disk
 * @param {string} [options.root]
 * @param {string} [options.syncSha]
 */
export async function syncCorpus(options = {}) {
  const dryRun = Boolean(options.dryRun);
  const prune = options.prune !== false;
  const syncSha =
    options.syncSha ||
    process.env.GITHUB_SHA ||
    process.env.SYNC_SHA ||
    "local";
  const syncedAt = new Date().toISOString();

  const corpus = loadCorpus(options.root);
  const mappingEdges = flattenMappingEdges(corpus.mappingSets);
  const plan = {
    dryRun,
    prune,
    syncSha,
    syncedAt,
    counts: {
      ...corpus.counts,
      maps_to: mappingEdges.length,
    },
    upserts: {
      domain: corpus.domains.map(domainKey),
      framework: corpus.frameworks.map(frameworkKey),
      requirement: corpus.requirements.map(requirementKey),
      mapping_set: corpus.mappingSets.map(mappingSetKey),
      ruleset: corpus.rulesets.map(rulesetKey),
      rubric: corpus.rubrics.map(rubricKey),
      maps_to: mappingEdges.map((e) => e.key),
    },
    deleted: {
      domain: [],
      framework: [],
      requirement: [],
      mapping_set: [],
      ruleset: [],
      rubric: [],
      maps_to: [],
    },
  };

  if (dryRun) {
    return { ok: true, ...plan, written: false };
  }

  const db = await connectSurreal();
  try {
    await ensureCorpusSchema(db);

    for (const doc of corpus.domains) {
      const key = domainKey(doc);
      // Omit YAML `id` — Surreal reserves `id` for the record id.
      const { source_path, id: _id, ...fields } = doc;
      await upsertRecord(db, "domain", key, {
        ...fields,
        corpus_id: key,
        ...syncMeta({ sourcePath: source_path, syncSha, syncedAt }),
      });
    }

    for (const doc of corpus.frameworks) {
      const key = frameworkKey(doc);
      const { source_path, id: frameworkId, ...fields } = doc;
      await upsertRecord(db, "framework", key, {
        ...fields,
        framework_id: frameworkId,
        corpus_key: key,
        corpus_id: frameworkId,
        ...syncMeta({ sourcePath: source_path, syncSha, syncedAt }),
      });
    }

    for (const doc of corpus.requirements) {
      const key = requirementKey(doc);
      const { source_path, id: _id, ...fields } = doc;
      await upsertRecord(db, "requirement", key, {
        ...fields,
        corpus_id: key,
        ...syncMeta({ sourcePath: source_path, syncSha, syncedAt }),
      });
    }

    for (const doc of corpus.mappingSets) {
      const key = mappingSetKey(doc);
      const { source_path, id: _id, mappings: _mappings, ...fields } = doc;
      await upsertRecord(db, "mapping_set", key, {
        ...fields,
        corpus_id: key,
        mapping_count: (doc.mappings || []).length,
        ...syncMeta({ sourcePath: source_path, syncSha, syncedAt }),
      });
    }

    // Graph edges: requirement:⟨from⟩ -> maps_to -> requirement:⟨to⟩
    // RELATION tables require RELATE / INSERT RELATION (not UPSERT CONTENT).
    for (const edge of mappingEdges) {
      await db.query(
        `
        DELETE type::record("maps_to", $edge_key);
        INSERT RELATION INTO maps_to {
          id: type::record("maps_to", $edge_key),
          in: type::record("requirement", $from),
          out: type::record("requirement", $to),
          edge_key: $edge_key,
          relation: $relation,
          strength: $strength,
          note: $note,
          reviewed: $reviewed,
          reviewer: $reviewer,
          mapping_set: $mapping_set,
          from_framework: $from_framework,
          to_framework: $to_framework,
          set_status: $set_status,
          content_source: $content_source,
          source_path: $source_path,
          sync_sha: $sync_sha,
          synced_at: $synced_at
        };
        `,
        {
          edge_key: edge.key,
          from: edge.from,
          to: edge.to,
          relation: edge.relation,
          strength: edge.strength,
          note: edge.note,
          reviewed: edge.reviewed,
          reviewer: edge.reviewer,
          mapping_set: edge.mappingSetId,
          from_framework: edge.from_framework,
          to_framework: edge.to_framework,
          set_status: edge.set_status,
          content_source: CONTENT_SOURCE_REPO,
          source_path: edge.source_path,
          sync_sha: syncSha,
          synced_at: syncedAt,
        },
      );
    }

    for (const doc of corpus.rulesets) {
      const key = rulesetKey(doc);
      const { source_path, ...fields } = doc;
      await upsertRecord(db, "ruleset", key, {
        ...fields,
        corpus_id: key,
        ...syncMeta({ sourcePath: source_path, syncSha, syncedAt }),
      });
    }

    for (const doc of corpus.rubrics) {
      const key = rubricKey(doc);
      const { source_path, ...fields } = doc;
      await upsertRecord(db, "rubric", key, {
        ...fields,
        corpus_id: key,
        ...syncMeta({ sourcePath: source_path, syncSha, syncedAt }),
      });
    }

    if (prune) {
      plan.deleted.domain = await deleteMissing(db, "domain", plan.upserts.domain);
      plan.deleted.framework = await deleteMissing(
        db,
        "framework",
        plan.upserts.framework,
      );
      plan.deleted.requirement = await deleteMissing(
        db,
        "requirement",
        plan.upserts.requirement,
      );
      plan.deleted.mapping_set = await deleteMissing(
        db,
        "mapping_set",
        plan.upserts.mapping_set,
      );
      plan.deleted.ruleset = await deleteMissing(
        db,
        "ruleset",
        plan.upserts.ruleset,
      );
      plan.deleted.rubric = await deleteMissing(
        db,
        "rubric",
        plan.upserts.rubric,
      );
      plan.deleted.maps_to = await deleteMissing(
        db,
        "maps_to",
        plan.upserts.maps_to,
      );
    }

    const runId = `${syncSha}-${syncedAt}`;
    await upsertRecord(db, "sync_run", runId, {
      sync_sha: syncSha,
      synced_at: syncedAt,
      counts: corpus.counts,
      deleted_counts: Object.fromEntries(
        Object.entries(plan.deleted).map(([k, v]) => [k, v.length]),
      ),
      content_source: CONTENT_SOURCE_REPO,
    });

    return { ok: true, ...plan, written: true, sync_run: runId };
  } finally {
    await db.close();
  }
}
