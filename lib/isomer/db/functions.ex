defmodule Isomer.Db.Functions do
  @moduledoc "DEFINE FUNCTION statements for the playbook (`fn::isomer::*`)."

  def ensure!(db) do
    surql = """
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

    DEFINE FUNCTION OVERWRITE fn::isomer::framework_key($id: string, $version: string) -> string
    {
      RETURN $id + ":" + $version;
    }
    COMMENT "Framework Surreal record key matching corpus sync"
    PERMISSIONS FULL;

    DEFINE FUNCTION OVERWRITE fn::isomer::maturity_rank($level: string) -> option<number>
    {
      LET $idx = array::find_index($isomer_maturity_levels, $level);
      RETURN IF $idx = NONE { NONE } ELSE { $idx };
    }
    COMMENT "Index of a maturity level in $isomer_maturity_levels"
    PERMISSIONS FULL;

    DEFINE FUNCTION OVERWRITE fn::isomer::meets_maturity($min: string, $actual: string) -> bool
    {
      LET $min_rank = fn::isomer::maturity_rank($min);
      LET $actual_rank = fn::isomer::maturity_rank($actual);
      RETURN $min_rank != NONE AND $actual_rank != NONE AND $actual_rank >= $min_rank;
    }
    COMMENT "Compare maturity levels using $isomer_maturity_levels order"
    PERMISSIONS FULL;

    DEFINE FUNCTION OVERWRITE fn::isomer::covers_ai_role($roles: option<array>, $role: string) -> bool
    {
      RETURN $roles = NONE OR array::len($roles) = 0 OR "all" IN $roles OR $role IN $roles;
    }
    COMMENT "Whether applicability.ai_roles covers the given AI role"
    PERMISSIONS FULL;

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

    DEFINE FUNCTION OVERWRITE fn::isomer::corpus_stats() -> object
    {
      RETURN {
        domains: (SELECT count() FROM domain WHERE content_source = $isomer_content_source GROUP ALL)[0].count OR 0,
        frameworks: (SELECT count() FROM framework WHERE content_source = $isomer_content_source GROUP ALL)[0].count OR 0,
        requirements: (SELECT count() FROM requirement WHERE content_source = $isomer_content_source GROUP ALL)[0].count OR 0,
        mapping_sets: (SELECT count() FROM mapping_set WHERE content_source = $isomer_content_source GROUP ALL)[0].count OR 0,
        maps_to: (SELECT count() FROM maps_to WHERE content_source = $isomer_content_source GROUP ALL)[0].count OR 0,
        rulesets: (SELECT count() FROM ruleset WHERE content_source = $isomer_content_source GROUP ALL)[0].count OR 0,
        rubrics: (SELECT count() FROM rubric WHERE content_source = $isomer_content_source GROUP ALL)[0].count OR 0,
        question_sets: (SELECT count() FROM question_set WHERE content_source = $isomer_content_source GROUP ALL)[0].count OR 0,
        templates: (SELECT count() FROM template WHERE content_source = $isomer_content_source GROUP ALL)[0].count OR 0
      };
    }
    COMMENT "Counts of content_source=$isomer_content_source records/edges"
    PERMISSIONS FULL;

    DEFINE FUNCTION OVERWRITE fn::isomer::maps_to(
      $corpus_id: string,
      $relations: option<array>
    ) -> array
    {
      LET $rid = type::record("requirement", $corpus_id);
      RETURN (
        SELECT
          id,
          edge_key,
          relation,
          strength,
          note,
          reviewed,
          reviewer,
          mapping_set,
          out AS target,
          out.corpus_id AS target_corpus_id,
          out.title AS target_title,
          out.framework AS target_framework
        FROM maps_to
        WHERE in = $rid
          AND content_source = $isomer_content_source
          AND ($relations = NONE OR relation IN $relations)
        ORDER BY edge_key ASC
      );
    }
    COMMENT "Outgoing maps_to edges from a requirement (graph coverage)"
    PERMISSIONS FULL;

    DEFINE FUNCTION OVERWRITE fn::isomer::mapped_from(
      $corpus_id: string,
      $relations: option<array>
    ) -> array
    {
      LET $rid = type::record("requirement", $corpus_id);
      RETURN (
        SELECT
          id,
          edge_key,
          relation,
          strength,
          note,
          reviewed,
          reviewer,
          mapping_set,
          in AS source,
          in.corpus_id AS source_corpus_id,
          in.title AS source_title,
          in.framework AS source_framework
        FROM maps_to
        WHERE out = $rid
          AND content_source = $isomer_content_source
          AND ($relations = NONE OR relation IN $relations)
        ORDER BY edge_key ASC
      );
    }
    COMMENT "Incoming maps_to edges to a requirement"
    PERMISSIONS FULL;

    DEFINE FUNCTION OVERWRITE fn::isomer::satisfiers($corpus_id: string) -> array
    {
      RETURN fn::isomer::maps_to($corpus_id, $isomer_satisfaction_relations);
    }
    COMMENT "Show everything satisfying a requirement via maps_to"
    PERMISSIONS FULL;

    DEFINE FUNCTION OVERWRITE fn::isomer::rubric($domain: string) -> option<object>
    {
      RETURN (
        SELECT * FROM ONLY rubric
        WHERE domain = $domain
          AND content_source = $isomer_content_source
        LIMIT 1
      );
    }
    COMMENT "Repo-synced maturity rubric for a domain"
    PERMISSIONS FULL;

    DEFINE FUNCTION OVERWRITE fn::isomer::rubric_level(
      $domain: string,
      $level: string
    ) -> option<object>
    {
      LET $rub = fn::isomer::rubric($domain);
      RETURN IF $rub = NONE {
        NONE
      } ELSE {
        array::find($rub.levels, |$l| $l.level = $level)
      };
    }
    COMMENT "Single maturity level entry from a domain rubric"
    PERMISSIONS FULL;
    """

    {:ok, _} = SurrealDB.query(db, surql)
    :ok
  end
end
