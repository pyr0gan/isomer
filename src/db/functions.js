/**
 * Database-wide Surreal custom functions for the isomer playbook.
 *
 * Defined via DEFINE FUNCTION so every client can call fn::isomer::* in SurQL.
 * Prefer these over repeating ad-hoc SELECT/filter logic in application code.
 *
 * @see https://surrealdb.com/docs/reference/query-language/statements/define/function
 */

/**
 * Ensure playbook functions exist (OVERWRITE so schema sync is idempotent).
 */
export async function ensureCorpusFunctions(db) {
  await db.query(`
    -- Split a corpus requirement id "<framework>/<version>/<ref>" into parts.
    DEFINE FUNCTION OVERWRITE fn::isomer::parse_corpus_id($corpus_id: string) -> object
    {
      LET $parts = string::split($corpus_id, "/");
      RETURN {
        framework: $parts[0] OR NONE,
        version: $parts[1] OR NONE,
        ref: array::join($parts[2..], "/") OR NONE,
        valid: array::len($parts) >= 3
      };
    }
    COMMENT "Parse requirement corpus_id into framework / version / ref"
    PERMISSIONS FULL;

    -- Build the framework record key used by sync ("<id>:<version>").
    DEFINE FUNCTION OVERWRITE fn::isomer::framework_key($id: string, $version: string) -> string
    {
      RETURN $id + ":" + $version;
    }
    COMMENT "Framework Surreal record key matching corpus sync"
    PERMISSIONS FULL;

    -- Numeric rank for maturity levels (L0..L4); NONE if unknown.
    DEFINE FUNCTION OVERWRITE fn::isomer::maturity_rank($level: string) -> option<number>
    {
      LET $idx = array::find_index($isomer_maturity_levels, $level);
      RETURN IF $idx = NONE { NONE } ELSE { $idx };
    }
    COMMENT "Index of a maturity level in $isomer_maturity_levels"
    PERMISSIONS FULL;

    -- True when $actual meets or exceeds $min (e.g. L2 meets L1).
    DEFINE FUNCTION OVERWRITE fn::isomer::meets_maturity($min: string, $actual: string) -> bool
    {
      LET $min_rank = fn::isomer::maturity_rank($min);
      LET $actual_rank = fn::isomer::maturity_rank($actual);
      RETURN $min_rank != NONE AND $actual_rank != NONE AND $actual_rank >= $min_rank;
    }
    COMMENT "Compare maturity levels using $isomer_maturity_levels order"
    PERMISSIONS FULL;

    -- True when a role is covered by requirement applicability.ai_roles.
    DEFINE FUNCTION OVERWRITE fn::isomer::covers_ai_role($roles: option<array>, $role: string) -> bool
    {
      RETURN $roles = NONE OR array::len($roles) = 0 OR "all" IN $roles OR $role IN $roles;
    }
    COMMENT "Whether applicability.ai_roles covers the given AI role"
    PERMISSIONS FULL;

    -- Fetch a single repo-managed requirement by corpus_id.
    DEFINE FUNCTION OVERWRITE fn::isomer::requirement($corpus_id: string) -> option<object>
    {
      RETURN (
        SELECT * FROM ONLY requirement
        WHERE corpus_id = $corpus_id
          AND content_source = $isomer_content_source
        LIMIT 1
      );
    }
    COMMENT "Repo-synced requirement by corpus_id"
    PERMISSIONS FULL;

    -- Requirements in a maturity domain (repo-synced only).
    DEFINE FUNCTION OVERWRITE fn::isomer::requirements_by_domain($domain: string) -> array
    {
      RETURN (
        SELECT * FROM requirement
        WHERE content_source = $isomer_content_source
          AND $domain IN domains
        ORDER BY corpus_id ASC
      );
    }
    COMMENT "Repo-synced requirements claiming a domain id"
    PERMISSIONS FULL;

    -- Requirements for a framework id, optionally filtered by version.
    DEFINE FUNCTION OVERWRITE fn::isomer::requirements_by_framework(
      $framework: string,
      $version: option<string>
    ) -> array
    {
      RETURN (
        SELECT * FROM requirement
        WHERE content_source = $isomer_content_source
          AND framework = $framework
          AND ($version = NONE OR framework_version = $version)
        ORDER BY corpus_id ASC
      );
    }
    COMMENT "Repo-synced requirements for a framework[/version]"
    PERMISSIONS FULL;

    -- Requirements applicable at a maturity level and AI role.
    DEFINE FUNCTION OVERWRITE fn::isomer::applicable_requirements(
      $maturity: string,
      $role: string
    ) -> array
    {
      RETURN (
        SELECT * FROM requirement
        WHERE content_source = $isomer_content_source
          AND fn::isomer::meets_maturity(
            applicability.min_maturity OR "L0",
            $maturity
          )
          AND fn::isomer::covers_ai_role(applicability.ai_roles, $role)
        ORDER BY corpus_id ASC
      );
    }
    COMMENT "Filter repo-synced requirements by maturity + AI role"
    PERMISSIONS FULL;

    -- Counts of repo-managed corpus tables (uses $isomer_content_source).
    DEFINE FUNCTION OVERWRITE fn::isomer::corpus_stats() -> object
    {
      RETURN {
        domains: (SELECT count() FROM domain WHERE content_source = $isomer_content_source GROUP ALL)[0].count OR 0,
        frameworks: (SELECT count() FROM framework WHERE content_source = $isomer_content_source GROUP ALL)[0].count OR 0,
        requirements: (SELECT count() FROM requirement WHERE content_source = $isomer_content_source GROUP ALL)[0].count OR 0,
        mapping_sets: (SELECT count() FROM mapping_set WHERE content_source = $isomer_content_source GROUP ALL)[0].count OR 0,
        rulesets: (SELECT count() FROM ruleset WHERE content_source = $isomer_content_source GROUP ALL)[0].count OR 0
      };
    }
    COMMENT "Counts of content_source=$isomer_content_source records"
    PERMISSIONS FULL;
  `);
}
