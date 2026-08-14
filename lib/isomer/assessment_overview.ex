defmodule Isomer.AssessmentOverview do
  @moduledoc """
  Progress and next-action payload for the Assessment Details hub.

  Pure builder (no Surreal I/O): domain + optional ruleset question progress,
  evidence coverage, and a single primary CTA based on assessment state.
  """

  alias Isomer.Domains
  alias Isomer.OrgMetrics

  @classification_id "__classification__"

  @doc """
  Builds the Details overview map.

  Expected keys (string or atom):

  - `assessment` — assessment row
  - `question_sets` — published packs
  - `answers` — questionnaire answer rows (artifacts already excluded)
  - `evidence_rows` — evidence rows with `question_id`
  - `ruleset` — optional ruleset row (`questions` list), or nil
  """
  def build(input) when is_map(input) do
    assessment = fetch(input, :assessment) || %{}
    sets = fetch(input, :question_sets) || []
    answers = fetch(input, :answers) || []
    evidence_rows = fetch(input, :evidence_rows) || []
    ruleset = fetch(input, :ruleset)

    {answer_map, _notes} = unpack_answers(answers)
    evidence_set = evidence_question_ids(evidence_rows)

    domain_ids =
      assessment
      |> Map.get("domains", [])
      |> List.wrap()
      |> Enum.map(&to_string/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.uniq()

    catalog = Map.new(Domains.catalog(), &{&1["id"], &1})
    metrics = normalize_metrics(assessment["domain_metrics"])

    domain_rows =
      Enum.map(domain_ids, fn domain_id ->
        questions = questions_for_domain(sets, domain_id)
        counts = progress_counts(questions, answer_map)
        entry = Map.get(metrics, domain_id) || %{}

        %{
          "id" => domain_id,
          "label" => get_in(catalog, [domain_id, "label"]) || Domains.sentence_case(domain_id),
          "total" => counts.total,
          "answered" => counts.answered,
          "unanswered" => counts.unanswered,
          "collect" => truthy?(Map.get(entry, "collect"))
        }
      end)

    ruleset_questions = ruleset_questions(ruleset)

    ruleset_row =
      if ruleset_questions == [] do
        nil
      else
        counts = progress_counts(ruleset_questions, answer_map)

        %{
          "id" => @classification_id,
          "label" => "Classification",
          "total" => counts.total,
          "answered" => counts.answered,
          "unanswered" => counts.unanswered,
          "collect" => false
        }
      end

    all_questions =
      ruleset_questions ++ Enum.flat_map(domain_ids, &questions_for_domain(sets, &1))

    stats = OrgMetrics.score_questions(all_questions, answer_map, evidence_set)
    answered = max(length(all_questions) - stats.unanswered, 0)

    classification = normalize_classification(assessment["classification"])
    activates = List.wrap(assessment["activates"]) |> Enum.reject(&(&1 in [nil, ""]))
    finalized? = finalized?(assessment)

    sections =
      case ruleset_row do
        nil -> domain_rows
        row -> [row | domain_rows]
      end

    %{
      "total" => length(all_questions),
      "answered" => answered,
      "unanswered" => stats.unanswered,
      "evidence_pct" => stats.evidence_pct,
      "yes_pct" => stats.yes_pct,
      "sections" => sections,
      "has_ruleset" => is_binary(assessment["ruleset_id"]) and assessment["ruleset_id"] != "",
      "ruleset_id" => assessment["ruleset_id"],
      "classification_label" => classification,
      "activates_count" => length(activates),
      "finalized" => finalized?,
      "primary_action" => primary_action(finalized?, stats.unanswered, length(all_questions))
    }
  end

  defp primary_action(true, _unanswered, _total) do
    %{
      "kind" => "artifacts",
      "label" => "Generate documents",
      "hint" => "This run is finalized — create policy or register drafts from templates."
    }
  end

  defp primary_action(false, unanswered, total) when total > 0 and unanswered > 0 do
    %{
      "kind" => "wizard",
      "label" => "Continue questionnaire (#{unanswered} open)",
      "hint" => "Pick up where you left off — unanswered questions stay open until you save."
    }
  end

  defp primary_action(false, 0, total) when total > 0 do
    %{
      "kind" => "results",
      "label" => "Review Results",
      "hint" => "Questionnaire is complete — check coverage, then finalize when ready."
    }
  end

  defp primary_action(false, _unanswered, _total) do
    %{
      "kind" => "wizard",
      "label" => "Open questionnaire",
      "hint" => "Add domains or answer classification questions to start progress."
    }
  end

  defp questions_for_domain(sets, domain_id) do
    sets
    |> Enum.filter(&(&1["domain"] == domain_id))
    |> Enum.flat_map(fn set ->
      Enum.map(set["questions"] || [], fn q ->
        %{
          id: q["id"],
          kind: q["kind"] || "text",
          evidence_prompt: q["evidence_prompt"],
          domain: domain_id
        }
      end)
    end)
  end

  defp ruleset_questions(nil), do: []

  defp ruleset_questions(ruleset) when is_map(ruleset) do
    Enum.map(ruleset["questions"] || [], fn q ->
      %{
        id: q["id"],
        kind: q["kind"] || "text",
        evidence_prompt: q["evidence_prompt"],
        domain: @classification_id
      }
    end)
  end

  defp progress_counts(questions, answers) do
    total = length(questions)

    answered =
      Enum.count(questions, fn q ->
        answer_bucket(q.kind, Map.get(answers, q.id, :missing)) != :unanswered
      end)

    %{total: total, answered: answered, unanswered: total - answered}
  end

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

  defp unwrap(value) when is_list(value), do: List.last(value)
  defp unwrap(value), do: value

  defp unpack_answers(rows) do
    Enum.reduce(rows, {%{}, %{}}, fn row, {vals, notes} ->
      qid = row["question_id"]

      if is_binary(qid) do
        {value, note} = unpack_value(row["value"])
        {Map.put(vals, qid, value), Map.put(notes, qid, note)}
      else
        {vals, notes}
      end
    end)
  end

  defp unpack_value(%{"v" => value} = map) when is_map(map) do
    {value, map |> Map.get("evidence", "") |> to_string()}
  end

  defp unpack_value(value), do: {value, ""}

  defp evidence_question_ids(rows) do
    rows
    |> Enum.map(& &1["question_id"])
    |> Enum.filter(&(is_binary(&1) and &1 != ""))
    |> MapSet.new()
  end

  defp normalize_metrics(metrics) when is_map(metrics) and not is_struct(metrics), do: metrics
  defp normalize_metrics(_), do: %{}

  defp normalize_classification(%{"label" => label}) when is_binary(label) and label != "",
    do: label

  defp normalize_classification(%{"classification" => label})
       when is_binary(label) and label != "",
       do: label

  defp normalize_classification(_), do: nil

  defp finalized?(%{"status" => status}) when status in ["complete", "archived"], do: true
  defp finalized?(_), do: false

  defp truthy?(v) when v in [true, "true", "on", "1", 1], do: true
  defp truthy?(_), do: false

  defp fetch(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end
end
