defmodule Isomer.Fixtures do
  @moduledoc false

  @doc "Minimal EU AI Act classification ruleset fixture for evaluator tests."
  def eu_ai_act_ruleset do
    %{
      "ruleset" => "eu-ai-act/2024+2026-1744/classification",
      "framework" => "eu-ai-act/2024+2026-1744",
      "outcomes" => [
        %{
          "when" => %{"prohibited-use" => true},
          "classification" => "prohibited",
          "activates" => ["art-5"],
          "applicable_from" => "2025-02-02",
          "note" => "Must not be placed on the market."
        },
        %{
          "when" => %{
            "role" => "provider",
            "annex-iii-area" => ["employment", "education"]
          },
          "classification" => "high-risk-annex-iii-provider",
          "activates" => ["art-9", "art-16"],
          "applicable_from" => "2027-12-02"
        },
        %{
          "when" => %{"interacts-or-generates" => true},
          "classification" => "limited-risk-transparency",
          "activates" => ["art-50"],
          "applicable_from" => "2026-08-02"
        }
      ],
      "default_outcome" => %{
        "classification" => "minimal-risk",
        "activates" => ["art-4"],
        "note" => "Literacy applies broadly."
      }
    }
  end

  @doc "Requirement map keyed by full corpus id for date override tests."
  def sample_requirements do
    %{
      "eu-ai-act/2024+2026-1744/art-5" => %{
        "title" => "Prohibited AI practices",
        "applicable_from" => "2025-01-01"
      },
      "eu-ai-act/2024+2026-1744/art-4" => %{
        "title" => "AI literacy",
        "applicable_from" => "2025-02-02"
      },
      "eu-ai-act/2024+2026-1744/art-50" => %{
        "title" => "Transparency obligations",
        "applicable_from" => "2026-01-01"
      }
    }
  end
end
