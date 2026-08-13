defmodule Isomer.Db.Schema do
  @moduledoc "Ensure Surreal tables, indexes, params, and functions for the corpus."

  alias Isomer.Db.{Functions, Params}

  def ensure!(db) do
    {:ok, _} =
      SurrealDB.query(db, """
      DEFINE TABLE IF NOT EXISTS domain SCHEMALESS;
      DEFINE TABLE IF NOT EXISTS framework SCHEMALESS;
      DEFINE TABLE IF NOT EXISTS requirement SCHEMALESS;
      DEFINE TABLE IF NOT EXISTS mapping_set SCHEMALESS;
      DEFINE TABLE IF NOT EXISTS ruleset SCHEMALESS;
      DEFINE TABLE IF NOT EXISTS rubric SCHEMALESS;
      DEFINE TABLE IF NOT EXISTS question_set SCHEMALESS;
      DEFINE TABLE IF NOT EXISTS template SCHEMALESS;
      DEFINE TABLE IF NOT EXISTS sync_run SCHEMALESS;
      DEFINE TABLE IF NOT EXISTS sbom SCHEMALESS
        COMMENT "CycloneDX SBoM for Mix tooling; current record sbom:isomer_tooling";

      DEFINE TABLE OVERWRITE maps_to
        TYPE RELATION IN requirement OUT requirement ENFORCED
        SCHEMALESS
        COMMENT "Corpus mapping edges (relation/strength/note/reviewed on the edge)";

      DEFINE INDEX IF NOT EXISTS requirement_corpus_id ON requirement FIELDS corpus_id UNIQUE;
      DEFINE INDEX IF NOT EXISTS framework_corpus_key ON framework FIELDS corpus_key UNIQUE;
      DEFINE INDEX IF NOT EXISTS mapping_set_corpus_id ON mapping_set FIELDS corpus_id UNIQUE;
      DEFINE INDEX IF NOT EXISTS ruleset_corpus_id ON ruleset FIELDS corpus_id UNIQUE;
      DEFINE INDEX IF NOT EXISTS rubric_domain ON rubric FIELDS domain UNIQUE;
      DEFINE INDEX IF NOT EXISTS question_set_domain ON question_set FIELDS domain UNIQUE;
      DEFINE INDEX IF NOT EXISTS template_corpus_id ON template FIELDS corpus_id UNIQUE;
      DEFINE INDEX IF NOT EXISTS maps_to_edge_key ON maps_to FIELDS edge_key UNIQUE;
      """)

    :ok = Params.ensure!(db)
    :ok = Functions.ensure!(db)
    :ok
  end
end
