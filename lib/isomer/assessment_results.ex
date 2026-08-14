defmodule Isomer.AssessmentResults do
  @moduledoc """
  Pure builder for the assessment Results view (Theme 2.2).

  Combines:

  - Classification summary + activated obligations
  - Residual / coverage rows from `maps_to` satisfiers
    (`satisfied_by` / `partially_satisfied_by`) cross-checked against domain
    answers that reference target requirements
  - Domain maturity completion for assessments that include question packs
  """

  alias Isomer.Domains
  alias Isomer.Maturity

  @satisfaction_rank %{
    "satisfied_by" => 3,
    "partially_satisfied_by" => 2
  }

  @doc """
  Builds the Results payload from in-memory inputs (no Surreal I/O).

  Expected keys (string or atom):

  - `assessment` — assessment row (`classification`, `activates`, `domains`, …)
  - `answers` — answer rows for this assessment
  - `question_sets` — published packs (`domain`, `questions` with `requirements`)
  - `requirements` — optional `%{corpus_id => %{title, framework}}`
  - `satisfier_edges` — maps_to rows with `from_corpus_id`, `target_corpus_id`,
    `relation`, optional titles/notes
  """
  def build(input) when is_map(input) do
    assessment = fetch(input, :assessment) || %{}
    answers = fetch(input, :answers) || []
    question_sets = fetch(input, :question_sets) || []
    requirements = normalize_requirements(fetch(input, :requirements) || %{})
    edges = fetch(input, :satisfier_edges) || []

    answer_index = answer_index(answers)
    {req_to_questions, questions_by_domain} = index_questions(question_sets)
    edges_by_from = Enum.group_by(edges, &edge_from/1)

    activates =
      assessment
      |> Map.get("activates", [])
      |> List.wrap()
      |> Enum.map(&to_string/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.uniq()

    obligations =
      Enum.map(activates, fn corpus_id ->
        build_obligation(
          corpus_id,
          Map.get(edges_by_from, corpus_id, []),
          requirements,
          req_to_questions,
          answer_index
        )
      end)

    domains = assessment["domains"] || []

    domain_rows =
      domains
      |> Enum.map(&to_string/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.uniq()
      |> Enum.map(fn domain_id ->
        qs = Map.get(questions_by_domain, domain_id, [])
        score_domain(domain_id, qs, answer_index)
      end)

    classification = normalize_classification(assessment["classification"])

    %{
      "classification" => classification,
      "ruleset_id" => assessment["ruleset_id"],
      "has_classification" => classification["label"] not in [nil, ""],
      "obligations" => obligations,
      "obligation_summary" => obligation_summary(obligations),
      "domains" => domain_rows,
      "domain_summary" => domain_summary(domain_rows),
      "kind" => assessment["kind"] || "domains"
    }
  end

  defp build_obligation(corpus_id, edges, requirements, req_to_questions, answer_index) do
    meta = Map.get(requirements, corpus_id, %{})
    title = meta["title"] || short_id(corpus_id)
    framework = meta["framework"] || framework_of(corpus_id)

    satisfiers =
      edges
      |> Enum.map(fn edge ->
        target = edge_target(edge)
        qids = Map.get(req_to_questions, target, [])
        yes? = Enum.any?(qids, &truthy_answer?(answer_index, &1))

        %{
          "target_corpus_id" => target,
          "target_title" =>
            Map.get(edge, "target_title") ||
              get_in(requirements, [target, "title"]) ||
              short_id(target),
          "target_framework" =>
            Map.get(edge, "target_framework") ||
              get_in(requirements, [target, "framework"]) ||
              framework_of(target),
          "relation" => Map.get(edge, "relation"),
          "strength" => Map.get(edge, "strength"),
          "note" => Map.get(edge, "note"),
          "question_ids" => qids,
          "answered_yes" => yes?
        }
      end)
      |> Enum.sort_by(&{&1["target_corpus_id"], &1["relation"]})

    mapping_status = mapping_status(satisfiers)
    progress_status = progress_status(satisfiers)
    gap_notes = gap_notes(satisfiers)

    %{
      "corpus_id" => corpus_id,
      "title" => title,
      "framework" => framework,
      "short_id" => short_id(corpus_id),
      "mapping_status" => mapping_status,
      "progress_status" => progress_status,
      "satisfiers" => satisfiers,
      "gap_notes" => gap_notes
    }
  end

  defp mapping_status([]), do: "open"

  defp mapping_status(satisfiers) do
    best =
      satisfiers
      |> Enum.map(&Map.get(@satisfaction_rank, &1["relation"], 0))
      |> Enum.max(fn -> 0 end)

    case best do
      3 -> "covered"
      2 -> "partial"
      _ -> "open"
    end
  end

  defp progress_status([]), do: "unmapped"

  defp progress_status(satisfiers) do
    yes_count = Enum.count(satisfiers, & &1["answered_yes"])
    total = length(satisfiers)

    cond do
      yes_count == 0 -> "untouched"
      yes_count == total -> "addressed"
      true -> "partial"
    end
  end

  defp gap_notes(satisfiers) do
    satisfiers
    |> Enum.filter(&(&1["relation"] == "partially_satisfied_by"))
    |> Enum.map(& &1["note"])
    |> Enum.filter(&(is_binary(&1) and String.trim(&1) != ""))
    |> Enum.map(&extract_gap/1)
    |> Enum.uniq()
  end

  defp extract_gap(note) do
    trimmed = note |> String.trim() |> String.replace(~r/\s+/, " ")

    if String.contains?(trimmed, "Gap:") do
      trimmed
      |> String.split("Gap:")
      |> List.last()
      |> String.trim()
      |> String.trim_trailing(".")
    else
      trimmed
    end
  end

  defp obligation_summary(obligations) do
    %{
      "total" => length(obligations),
      "open" => Enum.count(obligations, &(&1["mapping_status"] == "open")),
      "partial" => Enum.count(obligations, &(&1["mapping_status"] == "partial")),
      "covered" => Enum.count(obligations, &(&1["mapping_status"] == "covered")),
      "addressed" => Enum.count(obligations, &(&1["progress_status"] == "addressed")),
      "untouched" =>
        Enum.count(obligations, &(&1["progress_status"] in ["untouched", "unmapped"]))
    }
  end

  defp score_domain(domain_id, questions, answer_index) do
    total = length(questions)

    {yes, answered, unanswered} =
      Enum.reduce(questions, {0, 0, 0}, fn q, {y, a, u} ->
        qid = q["id"]
        bucket = answer_bucket(q["kind"] || "text", Map.get(answer_index, qid, :missing))

        y = if bucket == :yes, do: y + 1, else: y
        a = if bucket in [:yes, :no, :answered], do: a + 1, else: a
        u = if bucket == :unanswered, do: u + 1, else: u
        {y, a, u}
      end)

    level = estimate_level(questions, answer_index)
    meta = Maturity.level_meta(level)
    catalog = Domains.catalog() |> Map.new(&{&1["id"], &1})
    label = get_in(catalog, [domain_id, "label"]) || Domains.sentence_case(domain_id)

    yes_pct = if total > 0, do: round(100 * yes / total), else: nil

    %{
      "domain" => domain_id,
      "label" => label,
      "total" => total,
      "answered" => answered,
      "unanswered" => unanswered,
      "yes" => yes,
      "yes_pct" => yes_pct,
      "level" => level,
      "level_label" => meta.label,
      "level_color" => meta.color
    }
  end

  defp estimate_level(questions, answers) do
    cond do
      level_complete?(questions, answers, "L2") -> "L2"
      level_complete?(questions, answers, "L1") -> "L1"
      true -> "L0"
    end
  end

  defp level_complete?(questions, answers, level) do
    qs = Enum.filter(questions, &(&1["level"] == level))

    qs != [] and
      Enum.all?(qs, fn q ->
        Map.has_key?(answers, q["id"]) and met?(q, answers[q["id"]])
      end)
  end

  defp met?(q, value) do
    case q["kind"] || "text" do
      "boolean" -> truthy?(value)
      _ -> value not in [nil, "", :missing]
    end
  end

  defp domain_summary(rows) do
    total = Enum.reduce(rows, 0, &(&1["total"] + &2))
    answered = Enum.reduce(rows, 0, &(&1["answered"] + &2))
    unanswered = Enum.reduce(rows, 0, &(&1["unanswered"] + &2))
    yes = Enum.reduce(rows, 0, &(&1["yes"] + &2))

    %{
      "domains" => length(rows),
      "total" => total,
      "answered" => answered,
      "unanswered" => unanswered,
      "yes" => yes,
      "yes_pct" => if(total > 0, do: round(100 * yes / total), else: nil)
    }
  end

  defp index_questions(sets) do
    Enum.reduce(sets, {%{}, %{}}, fn set, {req_acc, domain_acc} ->
      domain = set["domain"]
      questions = set["questions"] || []

      domain_acc =
        if is_binary(domain) do
          Map.update(domain_acc, domain, questions, &(&1 ++ questions))
        else
          domain_acc
        end

      req_acc =
        Enum.reduce(questions, req_acc, fn q, acc ->
          qid = q["id"]

          Enum.reduce(q["requirements"] || [], acc, fn rid, inner ->
            rid = to_string(rid)
            Map.update(inner, rid, [qid], fn ids -> Enum.uniq(ids ++ [qid]) end)
          end)
        end)

      {req_acc, domain_acc}
    end)
  end

  defp answer_index(rows) do
    Enum.reduce(rows, %{}, fn row, acc ->
      qid = row["question_id"]

      if is_binary(qid) do
        {value, _} = unpack_value(row["value"])
        Map.put(acc, qid, value)
      else
        acc
      end
    end)
  end

  defp unpack_value(%{"v" => value}), do: {value, ""}
  defp unpack_value(value), do: {value, ""}

  defp answer_bucket("boolean", value) do
    case unwrap(value) do
      v when v in [true, "true", "yes", 1, "1"] -> :yes
      v when v in [false, "false", "no", 0, "0"] -> :no
      :missing -> :unanswered
      nil -> :unanswered
      "" -> :unanswered
      _ -> :unanswered
    end
  end

  defp answer_bucket(_kind, :missing), do: :unanswered
  defp answer_bucket(_kind, nil), do: :unanswered
  defp answer_bucket(_kind, ""), do: :unanswered
  defp answer_bucket("multi", list) when is_list(list) and list == [], do: :unanswered
  defp answer_bucket(_kind, _), do: :answered

  defp truthy_answer?(index, qid), do: truthy?(Map.get(index, qid))

  defp truthy?(value) do
    case unwrap(value) do
      v when v in [true, "true", "yes", 1, "1"] -> true
      _ -> false
    end
  end

  defp unwrap(value) when is_list(value), do: List.last(value)
  defp unwrap(value), do: value

  defp normalize_classification(%{"label" => label} = c) when is_binary(label), do: c

  defp normalize_classification(%{"classification" => label} = c) when is_binary(label) do
    Map.put(c, "label", label)
  end

  defp normalize_classification(c) when is_map(c), do: Map.put_new(c, "label", nil)
  defp normalize_classification(_), do: %{"label" => nil}

  defp normalize_requirements(map) when is_map(map) do
    Map.new(map, fn {k, v} ->
      v =
        cond do
          is_map(v) ->
            %{
              "title" => Map.get(v, "title") || Map.get(v, :title),
              "framework" => Map.get(v, "framework") || Map.get(v, :framework)
            }

          is_binary(v) ->
            %{"title" => v, "framework" => framework_of(to_string(k))}

          true ->
            %{"title" => nil, "framework" => framework_of(to_string(k))}
        end

      {to_string(k), v}
    end)
  end

  defp edge_from(edge) do
    Map.get(edge, "from_corpus_id") ||
      Map.get(edge, "in_corpus_id") ||
      ""
  end

  defp edge_target(edge) do
    Map.get(edge, "target_corpus_id") ||
      Map.get(edge, "out_corpus_id") ||
      ""
  end

  defp framework_of(corpus_id) when is_binary(corpus_id) do
    case String.split(corpus_id, "/") do
      [fw, ver | _] -> "#{fw}/#{ver}"
      _ -> corpus_id
    end
  end

  defp framework_of(_), do: nil

  defp short_id(corpus_id) when is_binary(corpus_id) do
    corpus_id |> String.split("/") |> List.last()
  end

  defp short_id(_), do: ""

  defp fetch(map, key) when is_atom(key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end
end
