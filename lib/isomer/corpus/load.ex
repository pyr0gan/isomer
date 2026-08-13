defmodule Isomer.Corpus.Load do
  @moduledoc "Load on-disk corpus into maps for sync / evaluation."

  alias Isomer.Paths
  alias Isomer.YAML

  def load(root \\ Isomer.root()) do
    root = Paths.expand_root!(root)
    domains = load_domains(root)
    frameworks = load_frameworks(root)
    requirements = load_requirements(root)
    mapping_sets = load_mapping_sets(root)
    rulesets = load_rulesets(root)
    rubrics = load_rubrics(root)
    question_sets = load_question_sets(root)
    templates = load_templates(root)

    question_count =
      Enum.reduce(question_sets, 0, fn set, n -> n + length(set["questions"] || []) end)

    %{
      root: root,
      domains: domains,
      frameworks: frameworks,
      requirements: requirements,
      mapping_sets: mapping_sets,
      rulesets: rulesets,
      rubrics: rubrics,
      question_sets: question_sets,
      templates: templates,
      counts: %{
        domains: length(domains),
        frameworks: length(frameworks),
        requirements: length(requirements),
        mapping_sets: length(mapping_sets),
        rulesets: length(rulesets),
        rubrics: length(rubrics),
        question_sets: length(question_sets),
        questions: question_count,
        templates: length(templates)
      }
    }
  end

  def requirements_by_id(corpus) do
    Map.new(corpus.requirements, &{&1["id"], &1})
  end

  def domain_key(doc), do: doc["id"]
  def framework_key(doc), do: "#{doc["id"]}:#{doc["version"]}"
  def requirement_key(doc), do: doc["id"]
  def mapping_set_key(doc), do: doc["id"]
  def ruleset_key(doc), do: doc["ruleset"]
  def rubric_key(doc), do: doc["domain"]
  def question_set_key(doc), do: doc["domain"]

  def template_key(doc) do
    doc["id"] || (doc["source_path"] && Path.basename(doc["source_path"], ".md"))
  end

  def maps_to_edge_key(mapping_set_id, from, to, relation) do
    "#{mapping_set_id}|#{from}|#{to}|#{relation}"
  end

  def flatten_mapping_edges(mapping_sets) do
    for doc <- mapping_sets,
        m <- doc["mappings"] || [] do
      mapping_set_id = mapping_set_key(doc)
      from = m["from"]
      to = m["to"]
      relation = m["relation"]

      %{
        key: maps_to_edge_key(mapping_set_id, from, to, relation),
        mapping_set_id: mapping_set_id,
        from: from,
        to: to,
        relation: relation,
        strength: m["strength"],
        note: m["note"],
        reviewed: m["reviewed"],
        reviewer: m["reviewer"],
        source_path: doc["source_path"],
        set_status: doc["status"] || "draft",
        from_framework: framework_version_from_id(from) || doc["from_framework"],
        to_framework: framework_version_from_id(to) || doc["to_framework"]
      }
    end
  end

  def framework_version_from_id(id) when is_binary(id) do
    case String.split(id, "/") do
      [fw, ver | rest] when rest != [] -> "#{fw}/#{ver}"
      _ -> nil
    end
  end

  def framework_version_from_id(_), do: nil

  defp load_domains(root) do
    path = Paths.join!(root, "vocab/domains.yaml")

    if File.exists?(path) do
      for d <- YAML.read!(path)["domains"] || [] do
        Map.put(d, "source_path", Paths.relative!(path, root))
      end
    else
      []
    end
  end

  defp load_frameworks(root) do
    for path <- Paths.wildcard!(root, "frameworks/*/*/framework.yaml") do
      path |> YAML.read!() |> Map.put("source_path", Paths.relative!(path, root))
    end
  end

  defp load_requirements(root) do
    for path <- Paths.wildcard!(root, "frameworks/*/*/requirements/*.yaml") do
      path |> YAML.read!() |> Map.put("source_path", Paths.relative!(path, root))
    end
  end

  defp load_mapping_sets(root) do
    for path <- Paths.wildcard!(root, "mappings/*.yaml") do
      path |> YAML.read!() |> Map.put("source_path", Paths.relative!(path, root))
    end
  end

  defp load_rulesets(root) do
    for path <- Paths.wildcard!(root, "rulesets/*.yaml") do
      path |> YAML.read!() |> Map.put("source_path", Paths.relative!(path, root))
    end
  end

  defp load_rubrics(root) do
    for path <- Paths.wildcard!(root, "rubrics/*.yaml") do
      path |> YAML.read!() |> Map.put("source_path", Paths.relative!(path, root))
    end
  end

  defp load_question_sets(root) do
    for path <- Paths.wildcard!(root, "questions/*.yaml") do
      path |> YAML.read!() |> Map.put("source_path", Paths.relative!(path, root))
    end
  end

  defp load_templates(root) do
    for path <- Paths.wildcard!(root, "templates/*.md") do
      rel = Paths.relative!(path, root)
      text = File.read!(path)

      unless String.starts_with?(text, "---\n") do
        raise ArgumentError, "#{rel}: missing YAML frontmatter"
      end

      case String.split(String.slice(text, 4..-1//1), "\n---\n", parts: 2) do
        [fm_text, body] ->
          fm =
            fm_text
            |> YamlElixir.read_from_string!()
            |> YAML.normalize()

          fm
          |> Map.put("body", body)
          |> Map.put("source_path", rel)

        _ ->
          raise ArgumentError, "#{rel}: unterminated YAML frontmatter"
      end
    end
  end
end
