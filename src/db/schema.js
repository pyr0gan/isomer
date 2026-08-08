/**
 * Ensure Surreal tables used by the corpus sync exist.
 * SCHEMALESS for the initial implementation phase; tighten later.
 */
export async function ensureCorpusSchema(db) {
  await db.query(`
    DEFINE TABLE IF NOT EXISTS domain SCHEMALESS;
    DEFINE TABLE IF NOT EXISTS framework SCHEMALESS;
    DEFINE TABLE IF NOT EXISTS requirement SCHEMALESS;
    DEFINE TABLE IF NOT EXISTS mapping_set SCHEMALESS;
    DEFINE TABLE IF NOT EXISTS ruleset SCHEMALESS;
    DEFINE TABLE IF NOT EXISTS sync_run SCHEMALESS;

    DEFINE INDEX IF NOT EXISTS requirement_corpus_id ON requirement FIELDS corpus_id UNIQUE;
    DEFINE INDEX IF NOT EXISTS framework_corpus_key ON framework FIELDS corpus_key UNIQUE;
    DEFINE INDEX IF NOT EXISTS mapping_set_corpus_id ON mapping_set FIELDS corpus_id UNIQUE;
    DEFINE INDEX IF NOT EXISTS ruleset_corpus_id ON ruleset FIELDS corpus_id UNIQUE;
  `);
}
