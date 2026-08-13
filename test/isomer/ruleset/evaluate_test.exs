defmodule Isomer.Ruleset.EvaluateTest do
  use Isomer.Case, async: true

  alias Isomer.Fixtures
  alias Isomer.Ruleset.Evaluate

  test "first matching outcome wins (prohibited before annex III)" do
    ruleset = Fixtures.eu_ai_act_ruleset()

    result =
      Evaluate.evaluate(
        ruleset,
        %{
          "prohibited-use" => true,
          "role" => "provider",
          "annex-iii-area" => "employment"
        },
        Fixtures.sample_requirements()
      )

    assert result["matched"] == "outcome"
    assert result["outcome_index"] == 0
    assert result["classification"] == "prohibited"
    assert hd(result["activates"])["ref"] == "art-5"
    assert hd(result["activates"])["date_source"] == "outcome"
    assert hd(result["activates"])["applicable_from"] == "2025-02-02"
  end

  test "list expected values match a single answer in the list" do
    ruleset = Fixtures.eu_ai_act_ruleset()

    result =
      Evaluate.evaluate(
        ruleset,
        %{
          "prohibited-use" => false,
          "role" => "provider",
          "annex-iii-area" => "employment"
        },
        Fixtures.sample_requirements()
      )

    assert result["classification"] == "high-risk-annex-iii-provider"
    assert result["outcome_index"] == 1
    assert Enum.map(result["activates"], & &1["ref"]) == ["art-9", "art-16"]
  end

  test "default_outcome when nothing matches" do
    ruleset = Fixtures.eu_ai_act_ruleset()

    result =
      Evaluate.evaluate(
        ruleset,
        %{
          "prohibited-use" => false,
          "role" => "deployer",
          "annex-iii-area" => "none",
          "interacts-or-generates" => false
        },
        Fixtures.sample_requirements()
      )

    assert result["matched"] == "default"
    assert result["outcome_index"] == nil
    assert result["classification"] == "minimal-risk"
    assert hd(result["activates"])["date_source"] == "requirement"
    assert hd(result["activates"])["applicable_from"] == "2025-02-02"
  end

  test "outcome applicable_from overrides requirement date" do
    ruleset = Fixtures.eu_ai_act_ruleset()

    result =
      Evaluate.evaluate(
        ruleset,
        %{"prohibited-use" => false, "interacts-or-generates" => true},
        Fixtures.sample_requirements()
      )

    art50 = hd(result["activates"])
    assert art50["ref"] == "art-50"
    assert art50["applicable_from"] == "2026-08-02"
    assert art50["requirement_applicable_from"] == "2026-01-01"
    assert art50["date_source"] == "outcome"
  end

  test "raises when no outcome and no default_outcome" do
    ruleset = %{
      "ruleset" => "empty",
      "framework" => "eu-ai-act/2024+2026-1744",
      "outcomes" => []
    }

    assert_raise ArgumentError, ~r/no matching outcome/, fn ->
      Evaluate.evaluate(ruleset, %{})
    end
  end
end
