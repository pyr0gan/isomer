defmodule Isomer.Db.Params do
  @moduledoc "DEFINE PARAM statements for the playbook."

  @content_source "repo"

  @corpus_tables ~w(domain framework requirement mapping_set ruleset rubric question_set template)
  @relation_tables ~w(maps_to)
  @requirement_types ~w(control clause obligation practice)
  @authorities ~w(certifiable legal advisory internal)
  @maturity_levels ~w(L0 L1 L2 L3 L4)
  @ai_roles ~w(all provider deployer developer importer distributor product-manufacturer user)
  @framework_types ~w(standard regulation framework pseudo-framework custom)
  @mapping_relations ~w(satisfied_by partially_satisfied_by supports related conflicts)
  @satisfaction_relations ~w(satisfied_by partially_satisfied_by)

  def content_source, do: @content_source

  def ensure!(db) do
    surql = """
    DEFINE PARAM OVERWRITE $isomer_content_source VALUE #{json(@content_source)} COMMENT "Marker on records managed by the repo corpus sync" PERMISSIONS FULL;
    DEFINE PARAM OVERWRITE $isomer_corpus_tables VALUE #{json(@corpus_tables)} COMMENT "Tables upserted/pruned by mix isomer.db.sync" PERMISSIONS FULL;
    DEFINE PARAM OVERWRITE $isomer_requirement_types VALUE #{json(@requirement_types)} COMMENT "Valid requirement.type values" PERMISSIONS FULL;
    DEFINE PARAM OVERWRITE $isomer_authorities VALUE #{json(@authorities)} COMMENT "Valid authority values" PERMISSIONS FULL;
    DEFINE PARAM OVERWRITE $isomer_maturity_levels VALUE #{json(@maturity_levels)} COMMENT "Valid applicability.min_maturity values" PERMISSIONS FULL;
    DEFINE PARAM OVERWRITE $isomer_ai_roles VALUE #{json(@ai_roles)} COMMENT "Valid applicability.ai_roles values" PERMISSIONS FULL;
    DEFINE PARAM OVERWRITE $isomer_framework_types VALUE #{json(@framework_types)} COMMENT "Valid framework.type values" PERMISSIONS FULL;
    DEFINE PARAM OVERWRITE $isomer_mapping_relations VALUE #{json(@mapping_relations)} COMMENT "Valid mapping.relation values" PERMISSIONS FULL;
    DEFINE PARAM OVERWRITE $isomer_satisfaction_relations VALUE #{json(@satisfaction_relations)} COMMENT "Relations used by fn::isomer::satisfiers" PERMISSIONS FULL;
    DEFINE PARAM OVERWRITE $isomer_corpus_relation_tables VALUE #{json(@relation_tables)} COMMENT "Graph edge tables upserted/pruned by sync" PERMISSIONS FULL;
    """

    {:ok, _} = SurrealDB.query(db, surql)
    :ok
  end

  defp json(term), do: Jason.encode!(term)
end
