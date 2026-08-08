/**
 * Database-wide Surreal params for the isomer playbook.
 *
 * Defined via DEFINE PARAM so every client can reference them in SurQL
 * (e.g. WHERE content_source = $isomer_content_source).
 *
 * Keep the JS constants below in sync with ensureCorpusParams() — they are
 * used when writing records from the Node sync tooling.
 *
 * @see https://surrealdb.com/docs/reference/query-language/statements/define/param
 */

/** Marker written on records managed by the repo corpus sync. */
export const CONTENT_SOURCE_REPO = "repo";

/** Requirement.type enum (schemas/requirement.schema.json). */
export const REQUIREMENT_TYPES = ["control", "clause", "obligation", "practice"];

/** Requirement.authority / framework.authority enum. */
export const AUTHORITIES = ["certifiable", "legal", "advisory", "internal"];

/** applicability.min_maturity enum. */
export const MATURITY_LEVELS = ["L0", "L1", "L2", "L3", "L4"];

/** applicability.ai_roles enum. */
export const AI_ROLES = [
  "all",
  "provider",
  "deployer",
  "developer",
  "importer",
  "distributor",
  "product-manufacturer",
  "user",
];

/** Framework.type enum. */
export const FRAMEWORK_TYPES = [
  "standard",
  "regulation",
  "framework",
  "pseudo-framework",
  "custom",
];

/** Mapping relation enum. */
export const MAPPING_RELATIONS = [
  "satisfied_by",
  "partially_satisfied_by",
  "supports",
  "related",
  "conflicts",
];

/** Tables owned by the corpus sync (pruned when absent from disk). */
export const CORPUS_TABLES = [
  "domain",
  "framework",
  "requirement",
  "mapping_set",
  "ruleset",
  "rubric",
];

function surrealStringArray(values) {
  return `[${values.map((v) => JSON.stringify(v)).join(", ")}]`;
}

/**
 * Ensure playbook params exist (OVERWRITE so schema sync is idempotent).
 */
export async function ensureCorpusParams(db) {
  await db.query(`
    DEFINE PARAM OVERWRITE $isomer_content_source
      VALUE ${JSON.stringify(CONTENT_SOURCE_REPO)}
      COMMENT "Marker on records managed by the repo corpus sync"
      PERMISSIONS FULL;

    DEFINE PARAM OVERWRITE $isomer_corpus_tables
      VALUE ${surrealStringArray(CORPUS_TABLES)}
      COMMENT "Tables upserted/pruned by npm run db:sync"
      PERMISSIONS FULL;

    DEFINE PARAM OVERWRITE $isomer_requirement_types
      VALUE ${surrealStringArray(REQUIREMENT_TYPES)}
      COMMENT "Valid requirement.type values"
      PERMISSIONS FULL;

    DEFINE PARAM OVERWRITE $isomer_authorities
      VALUE ${surrealStringArray(AUTHORITIES)}
      COMMENT "Valid authority values (requirement/framework)"
      PERMISSIONS FULL;

    DEFINE PARAM OVERWRITE $isomer_maturity_levels
      VALUE ${surrealStringArray(MATURITY_LEVELS)}
      COMMENT "Valid applicability.min_maturity values"
      PERMISSIONS FULL;

    DEFINE PARAM OVERWRITE $isomer_ai_roles
      VALUE ${surrealStringArray(AI_ROLES)}
      COMMENT "Valid applicability.ai_roles values"
      PERMISSIONS FULL;

    DEFINE PARAM OVERWRITE $isomer_framework_types
      VALUE ${surrealStringArray(FRAMEWORK_TYPES)}
      COMMENT "Valid framework.type values"
      PERMISSIONS FULL;

    DEFINE PARAM OVERWRITE $isomer_mapping_relations
      VALUE ${surrealStringArray(MAPPING_RELATIONS)}
      COMMENT "Valid mapping.relation values"
      PERMISSIONS FULL;
  `);
}
