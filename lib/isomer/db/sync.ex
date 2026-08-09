defmodule Isomer.Db.Sync do
  @moduledoc "Sync the on-disk corpus into SurrealDB."

  alias Isomer.Corpus.Load
  alias Isomer.Db.{Connect, Params, Schema}

  def sync!(opts \\ []) do
    dry_run? = Keyword.get(opts, :dry_run, false)
    prune? = Keyword.get(opts, :prune, true)

    sync_sha =
      Keyword.get(opts, :sync_sha) ||
        System.get_env("GITHUB_SHA") ||
        System.get_env("SYNC_SHA") ||
        "local"

    synced_at = DateTime.utc_now() |> DateTime.to_iso8601()
    root = Keyword.get(opts, :root, Isomer.root())

    corpus = Load.load(root)
    mapping_edges = Load.flatten_mapping_edges(corpus.mapping_sets)

    plan = %{
      dry_run: dry_run?,
      prune: prune?,
      sync_sha: sync_sha,
      synced_at: synced_at,
      counts: Map.put(corpus.counts, :maps_to, length(mapping_edges)),
      upserts: %{
        domain: Enum.map(corpus.domains, &Load.domain_key/1),
        framework: Enum.map(corpus.frameworks, &Load.framework_key/1),
        requirement: Enum.map(corpus.requirements, &Load.requirement_key/1),
        mapping_set: Enum.map(corpus.mapping_sets, &Load.mapping_set_key/1),
        ruleset: Enum.map(corpus.rulesets, &Load.ruleset_key/1),
        rubric: Enum.map(corpus.rubrics, &Load.rubric_key/1),
        question_set: Enum.map(corpus.question_sets, &Load.question_set_key/1),
        template: Enum.map(corpus.templates, &Load.template_key/1),
        maps_to: Enum.map(mapping_edges, & &1.key)
      },
      deleted: %{
        domain: [],
        framework: [],
        requirement: [],
        mapping_set: [],
        ruleset: [],
        rubric: [],
        question_set: [],
        template: [],
        maps_to: []
      }
    }

    if dry_run? do
      Map.merge(plan, %{ok: true, written: false})
    else
      db = Connect.connect!()

      try do
        Schema.ensure!(db)
        write_domains!(db, corpus.domains, sync_sha, synced_at)
        write_frameworks!(db, corpus.frameworks, sync_sha, synced_at)
        write_requirements!(db, corpus.requirements, sync_sha, synced_at)
        write_mapping_sets!(db, corpus.mapping_sets, sync_sha, synced_at)
        write_maps_to!(db, mapping_edges, sync_sha, synced_at)
        write_rulesets!(db, corpus.rulesets, sync_sha, synced_at)
        write_rubrics!(db, corpus.rubrics, sync_sha, synced_at)
        write_question_sets!(db, corpus.question_sets, sync_sha, synced_at)
        write_templates!(db, corpus.templates, sync_sha, synced_at)

        deleted =
          if prune? do
            %{
              domain: delete_missing!(db, "domain", plan.upserts.domain),
              framework: delete_missing!(db, "framework", plan.upserts.framework),
              requirement: delete_missing!(db, "requirement", plan.upserts.requirement),
              mapping_set: delete_missing!(db, "mapping_set", plan.upserts.mapping_set),
              ruleset: delete_missing!(db, "ruleset", plan.upserts.ruleset),
              rubric: delete_missing!(db, "rubric", plan.upserts.rubric),
              question_set: delete_missing!(db, "question_set", plan.upserts.question_set),
              template: delete_missing!(db, "template", plan.upserts.template),
              maps_to: delete_missing!(db, "maps_to", plan.upserts.maps_to)
            }
          else
            plan.deleted
          end

        run_id = "#{sync_sha}-#{synced_at}"

        upsert!(db, "sync_run", run_id, %{
          "sync_sha" => sync_sha,
          "synced_at" => synced_at,
          "counts" => atomize_keys_to_string(corpus.counts),
          "deleted_counts" => Map.new(deleted, fn {k, v} -> {to_string(k), length(v)} end),
          "content_source" => Params.content_source()
        })

        Map.merge(plan, %{ok: true, written: true, deleted: deleted, sync_run: run_id})
      after
        SurrealDB.close(db)
      end
    end
  end

  defp write_domains!(db, docs, sync_sha, synced_at) do
    Enum.each(docs, fn doc ->
      key = Load.domain_key(doc)
      fields = drop_keys(doc, ["source_path", "id"])

      upsert!(
        db,
        "domain",
        key,
        fields
        |> Map.put("corpus_id", key)
        |> Map.merge(sync_meta(doc["source_path"], sync_sha, synced_at))
      )
    end)
  end

  defp write_frameworks!(db, docs, sync_sha, synced_at) do
    Enum.each(docs, fn doc ->
      key = Load.framework_key(doc)
      framework_id = doc["id"]
      fields = drop_keys(doc, ["source_path", "id"])

      upsert!(
        db,
        "framework",
        key,
        fields
        |> Map.put("framework_id", framework_id)
        |> Map.put("corpus_key", key)
        |> Map.put("corpus_id", framework_id)
        |> Map.merge(sync_meta(doc["source_path"], sync_sha, synced_at))
      )
    end)
  end

  defp write_requirements!(db, docs, sync_sha, synced_at) do
    Enum.each(docs, fn doc ->
      key = Load.requirement_key(doc)
      fields = drop_keys(doc, ["source_path", "id"])

      upsert!(
        db,
        "requirement",
        key,
        fields
        |> Map.put("corpus_id", key)
        |> Map.merge(sync_meta(doc["source_path"], sync_sha, synced_at))
      )
    end)
  end

  defp write_mapping_sets!(db, docs, sync_sha, synced_at) do
    Enum.each(docs, fn doc ->
      key = Load.mapping_set_key(doc)
      fields = drop_keys(doc, ["source_path", "id", "mappings"])

      upsert!(
        db,
        "mapping_set",
        key,
        fields
        |> Map.put("corpus_id", key)
        |> Map.put("mapping_count", length(doc["mappings"] || []))
        |> Map.merge(sync_meta(doc["source_path"], sync_sha, synced_at))
      )
    end)
  end

  defp write_maps_to!(db, edges, sync_sha, synced_at) do
    Enum.each(edges, fn edge ->
      {:ok, _} =
        SurrealDB.query(
          db,
          """
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
          """,
          %{
            "edge_key" => edge.key,
            "from" => edge.from,
            "to" => edge.to,
            "relation" => edge.relation,
            "strength" => edge.strength,
            "note" => edge.note,
            "reviewed" => edge.reviewed,
            "reviewer" => edge.reviewer,
            "mapping_set" => edge.mapping_set_id,
            "from_framework" => edge.from_framework,
            "to_framework" => edge.to_framework,
            "set_status" => edge.set_status,
            "content_source" => Params.content_source(),
            "source_path" => edge.source_path,
            "sync_sha" => sync_sha,
            "synced_at" => synced_at
          }
        )
    end)
  end

  defp write_rulesets!(db, docs, sync_sha, synced_at) do
    Enum.each(docs, fn doc ->
      key = Load.ruleset_key(doc)
      fields = drop_keys(doc, ["source_path"])

      upsert!(
        db,
        "ruleset",
        key,
        fields
        |> Map.put("corpus_id", key)
        |> Map.merge(sync_meta(doc["source_path"], sync_sha, synced_at))
      )
    end)
  end

  defp write_rubrics!(db, docs, sync_sha, synced_at) do
    Enum.each(docs, fn doc ->
      key = Load.rubric_key(doc)
      fields = drop_keys(doc, ["source_path"])

      upsert!(
        db,
        "rubric",
        key,
        fields
        |> Map.put("corpus_id", key)
        |> Map.merge(sync_meta(doc["source_path"], sync_sha, synced_at))
      )
    end)
  end

  defp write_question_sets!(db, docs, sync_sha, synced_at) do
    Enum.each(docs, fn doc ->
      key = Load.question_set_key(doc)
      fields = drop_keys(doc, ["source_path"])

      upsert!(
        db,
        "question_set",
        key,
        fields
        |> Map.put("corpus_id", key)
        |> Map.put("question_count", length(doc["questions"] || []))
        |> Map.merge(sync_meta(doc["source_path"], sync_sha, synced_at))
      )
    end)
  end

  defp write_templates!(db, docs, sync_sha, synced_at) do
    Enum.each(docs, fn doc ->
      key = Load.template_key(doc)
      fields = drop_keys(doc, ["source_path", "id"])

      upsert!(
        db,
        "template",
        key,
        fields
        |> Map.put("corpus_id", key)
        |> Map.merge(sync_meta(doc["source_path"], sync_sha, synced_at))
      )
    end)
  end

  defp sync_meta(source_path, sync_sha, synced_at) do
    %{
      "content_source" => Params.content_source(),
      "source_path" => source_path,
      "sync_sha" => sync_sha,
      "synced_at" => synced_at
    }
  end

  defp upsert!(db, table, key, content) do
    rid = SurrealDB.RecordId.new(table, key)

    case SurrealDB.upsert(db, rid, content) do
      {:ok, _} -> :ok
      {:error, err} -> raise "upsert #{table}:#{inspect(key)} failed: #{inspect(err)}"
    end
  end

  defp delete_missing!(db, table, keep_keys) do
    existing = list_corpus_managed_ids!(db, table)
    keep = MapSet.new(keep_keys)
    to_delete = Enum.reject(existing, &MapSet.member?(keep, &1))

    Enum.each(to_delete, fn key ->
      rid = SurrealDB.RecordId.new(table, key)

      case SurrealDB.delete(db, rid) do
        {:ok, _} -> :ok
        {:error, err} -> raise "delete #{table}:#{inspect(key)} failed: #{inspect(err)}"
      end
    end)

    to_delete
  end

  defp list_corpus_managed_ids!(db, table) do
    {:ok, [rows]} =
      SurrealDB.query(
        db,
        ~s|SELECT id FROM type::table($table) WHERE content_source = $isomer_content_source;|,
        %{"table" => table}
      )

    rows
    |> List.wrap()
    |> Enum.map(&extract_id_key/1)
    |> Enum.reject(&is_nil/1)
  end

  defp extract_id_key(%{"id" => %SurrealDB.RecordId{id: id}}), do: to_string(id)
  defp extract_id_key(%{"id" => id}) when is_binary(id), do: strip_table_prefix(id)
  defp extract_id_key(%{id: %SurrealDB.RecordId{id: id}}), do: to_string(id)
  defp extract_id_key(%{id: id}) when is_binary(id), do: strip_table_prefix(id)
  defp extract_id_key(_), do: nil

  defp strip_table_prefix(s) do
    case String.split(s, ":", parts: 2) do
      [_table, key] ->
        key
        |> String.trim_leading("⟨")
        |> String.trim_trailing("⟩")
        |> String.trim_leading("`")
        |> String.trim_trailing("`")

      _ ->
        s
    end
  end

  defp drop_keys(map, keys), do: Map.drop(map, keys)

  defp atomize_keys_to_string(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {to_string(k), v}
      {k, v} -> {k, v}
    end)
  end
end
