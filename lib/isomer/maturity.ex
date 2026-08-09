defmodule Isomer.Maturity do
  @moduledoc """
  Lightweight org maturity snapshot from assessment answers.

  Levels are estimated per domain from boolean question outcomes (cumulative
  L1 → L2). Unanswered or No counts as not met. Non-boolean answers count as
  met when present.
  """

  alias Isomer.Domains
  alias Isomer.Db.Tenant

  @level_order ~w(L0 L1 L2 L3 L4)
  @level_fill %{"L0" => 8, "L1" => 35, "L2" => 60, "L3" => 80, "L4" => 100}

  @doc """
  Builds domain maturity bars for an org from its assessments (newest answers win).

  Returns `{:ok, bars}` where each bar is a map with string keys:
  `domain`, `label`, `level`, `pct`, `answered`, `total`.
  """
  def org_domain_bars(conn, assessments) when is_list(assessments) do
    with {:ok, sets} <- Tenant.list_question_sets(conn) do
      answer_index = load_answer_index(conn, assessments)
      catalog = Domains.catalog()

      bars =
        catalog
        |> Enum.map(fn domain ->
          domain_id = domain["id"]
          questions = questions_for_domain(sets, domain_id)

          if questions == [] do
            nil
          else
            scored = score_domain(questions, answer_index)
            level = scored.level

            %{
              "domain" => domain_id,
              "label" => domain["label"] || Domains.sentence_case(domain_id),
              "level" => level,
              "pct" => Map.get(@level_fill, level, 8),
              "answered" => scored.answered,
              "total" => scored.total,
              "yes" => scored.yes
            }
          end
        end)
        |> Enum.reject(&is_nil/1)
        # Only domains that appear on at least one assessment
        |> Enum.filter(fn bar ->
          Enum.any?(assessments, fn a -> bar["domain"] in (a["domains"] || []) end)
        end)

      {:ok, bars}
    end
  end

  defp load_answer_index(conn, assessments) do
    # Newest assessments first (list_assessments already ORDER BY created_at DESC).
    Enum.reduce(assessments, %{}, fn assessment, acc ->
      id = Tenant.canonicalize_record_id(assessment["id"])

      case Tenant.list_answers(conn, id) do
        {:ok, rows} ->
          Enum.reduce(rows, acc, fn row, inner ->
            qid = row["question_id"]

            if is_binary(qid) and not Map.has_key?(inner, qid) do
              {value, _note} = unpack_value(row["value"])
              Map.put(inner, qid, value)
            else
              inner
            end
          end)

        {:error, _} ->
          acc
      end
    end)
  end

  defp questions_for_domain(sets, domain_id) do
    sets
    |> Enum.filter(&(&1["domain"] == domain_id))
    |> Enum.flat_map(fn set -> set["questions"] || [] end)
  end

  defp score_domain(questions, answers) do
    total = length(questions)

    answered =
      Enum.count(questions, fn q ->
        Map.has_key?(answers, q["id"]) and met?(q, answers[q["id"]])
      end)

    yes =
      Enum.count(questions, fn q ->
        kind = q["kind"] || "text"
        kind == "boolean" and truthy?(answers[q["id"]])
      end)

    level =
      cond do
        level_complete?(questions, answers, "L2") -> "L2"
        level_complete?(questions, answers, "L1") -> "L1"
        true -> "L0"
      end

    %{level: level, answered: answered, total: total, yes: yes}
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
      _ -> value not in [nil, ""]
    end
  end

  defp truthy?(value) do
    case unwrap(value) do
      v when v in [true, "true", "yes", 1, "1"] -> true
      _ -> false
    end
  end

  defp unpack_value(%{"v" => value}), do: {value, ""}
  defp unpack_value(value), do: {value, ""}

  defp unwrap(value) when is_list(value), do: List.last(value)
  defp unwrap(value), do: value

  def level_order, do: @level_order
end
