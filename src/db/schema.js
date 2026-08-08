import { ensureCorpusFunctions } from "./functions.js";
import { ensureCorpusParams } from "./params.js";

/**
 * Ensure Surreal tables, indexes, params, and functions used by the corpus exist.
 * SCHEMALESS tables for the initial implementation phase; tighten later.
 */
export async function ensureCorpusSchema(db) {
  await db.query(`
    DEFINE TABLE IF NOT EXISTS domain SCHEMALESS;
    DEFINE TABLE IF NOT EXISTS framework SCHEMALESS;
    DEFINE TABLE IF NOT EXISTS requirement SCHEMALESS;
    DEFINE TABLE IF NOT EXISTS mapping_set SCHEMALESS;
    DEFINE TABLE IF NOT EXISTS ruleset SCHEMALESS;
    DEFINE TABLE IF NOT EXISTS rubric SCHEMALESS;
    DEFINE TABLE IF NOT EXISTS sync_run SCHEMALESS;

    -- Directed cross-framework mappings as graph edges:
    --   requirement:⟨from⟩ -> maps_to -> requirement:⟨to⟩
    DEFINE TABLE OVERWRITE maps_to
      TYPE RELATION IN requirement OUT requirement ENFORCED
      SCHEMALESS
      COMMENT "Corpus mapping edges (relation/strength/note/reviewed on the edge)";

    DEFINE INDEX IF NOT EXISTS requirement_corpus_id ON requirement FIELDS corpus_id UNIQUE;
    DEFINE INDEX IF NOT EXISTS framework_corpus_key ON framework FIELDS corpus_key UNIQUE;
    DEFINE INDEX IF NOT EXISTS mapping_set_corpus_id ON mapping_set FIELDS corpus_id UNIQUE;
    DEFINE INDEX IF NOT EXISTS ruleset_corpus_id ON ruleset FIELDS corpus_id UNIQUE;
    DEFINE INDEX IF NOT EXISTS rubric_domain ON rubric FIELDS domain UNIQUE;
    DEFINE INDEX IF NOT EXISTS maps_to_edge_key ON maps_to FIELDS edge_key UNIQUE;
  `);

  // Params first — functions reference $isomer_* params.
  await ensureCorpusParams(db);
  await ensureCorpusFunctions(db);
}
