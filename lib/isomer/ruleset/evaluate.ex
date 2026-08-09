defmodule Isomer.Ruleset.Evaluate do
  @moduledoc """
  First-match classification ruleset evaluation.

  Outcome order is semantic. Outcome `applicable_from` overrides requirement-level dates.
  """

  def evaluate(ruleset, answers, requirements_by_id \\ %{}) do
    {outcome, matched, index} = select_outcome(ruleset, answers)

    if is_nil(outcome) do
      raise ArgumentError, "Ruleset has no matching outcome and no default_outcome"
    end

    framework = ruleset["framework"]
    outcome_date = outcome["applicable_from"]
    activates = outcome["activates"] || []

    obligations =
      Enum.map(activates, fn ref ->
        id = "#{framework}/#{ref}"
        req = Map.get(requirements_by_id, id, %{})
        requirement_date = req["applicable_from"]
        applicable_from = outcome_date || requirement_date

        %{
          "ref" => ref,
          "id" => id,
          "title" => req["title"],
          "applicable_from" => applicable_from,
          "requirement_applicable_from" => requirement_date,
          "date_source" => if(outcome_date, do: "outcome", else: "requirement")
        }
      end)

    %{
      "ruleset" => ruleset["ruleset"],
      "framework" => framework,
      "classification" => outcome["classification"],
      "matched" => matched,
      "outcome_index" => index,
      "note" => outcome["note"],
      "outcome_applicable_from" => outcome_date,
      "activates" => obligations
    }
  end

  def select_outcome(ruleset, answers) do
    outcomes = ruleset["outcomes"] || []

    case Enum.find_index(outcomes, &matches_when?(&1["when"], answers)) do
      nil ->
        {ruleset["default_outcome"], "default", nil}

      idx ->
        {Enum.at(outcomes, idx), "outcome", idx}
    end
  end

  def matches_when?(when_map, answers) do
    Enum.all?(when_map || %{}, fn {qid, expected} ->
      answer_matches?(expected, Map.get(answers, qid) || Map.get(answers, to_string(qid)))
    end)
  end

  defp answer_matches?(expected, actual) when is_list(expected), do: actual in expected
  defp answer_matches?(expected, actual) when is_boolean(expected), do: !!actual == expected
  defp answer_matches?(expected, actual), do: actual == expected
end
