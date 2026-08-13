defmodule Isomer.AssessmentResultsTest do
  use Isomer.Case, async: true

  alias Isomer.AssessmentResults

  @sets [
    %{
      "domain" => "ai-lifecycle",
      "questions" => [
        %{
          "id" => "al-01",
          "level" => "L1",
          "kind" => "boolean",
          "requirements" => ["iso42001/2023/A.4.2"]
        },
        %{
          "id" => "al-02",
          "level" => "L1",
          "kind" => "boolean",
          "requirements" => ["iso42001/2023/A.9.2"]
        },
        %{
          "id" => "al-03",
          "level" => "L2",
          "kind" => "boolean",
          "requirements" => ["iso42001/2023/A.6.1.3"]
        }
      ]
    }
  ]

  @requirements %{
    "eu-ai-act/2024+2026-1744/art-5" => %{
      "title" => "Prohibited AI practices",
      "framework" => "eu-ai-act/2024+2026-1744"
    },
    "eu-ai-act/2024+2026-1744/art-4" => %{
      "title" => "AI literacy",
      "framework" => "eu-ai-act/2024+2026-1744"
    },
    "iso42001/2023/A.9.2" => %{"title" => "AI system intake", "framework" => "iso42001/2023"},
    "annex-sl-core/1.0/7.2" => %{"title" => "Competence", "framework" => "annex-sl-core/1.0"}
  }

  test "domain-only assessment reports completion and maturity level" do
    results =
      AssessmentResults.build(%{
        assessment: %{
          "kind" => "domains",
          "domains" => ["ai-lifecycle"],
          "activates" => []
        },
        answers: [
          %{"question_id" => "al-01", "value" => %{"v" => true}},
          %{"question_id" => "al-02", "value" => %{"v" => true}}
        ],
        question_sets: @sets,
        requirements: @requirements,
        satisfier_edges: []
      })

    assert results["obligations"] == []
    assert results["domain_summary"]["total"] == 3
    assert results["domain_summary"]["answered"] == 2
    assert results["domain_summary"]["unanswered"] == 1
    assert hd(results["domains"])["level"] == "L1"
  end

  test "activated obligations surface mapping and assessment progress" do
    results =
      AssessmentResults.build(%{
        assessment: %{
          "kind" => "combined",
          "ruleset_id" => "eu-ai-act/2024+2026-1744/classification",
          "classification" => %{"label" => "prohibited", "note" => "Must not place on market."},
          "activates" => [
            "eu-ai-act/2024+2026-1744/art-5",
            "eu-ai-act/2024+2026-1744/art-4"
          ],
          "domains" => ["ai-lifecycle"]
        },
        answers: [
          %{"question_id" => "al-02", "value" => %{"v" => true}}
        ],
        question_sets: @sets,
        requirements: @requirements,
        satisfier_edges: [
          %{
            "from_corpus_id" => "eu-ai-act/2024+2026-1744/art-5",
            "target_corpus_id" => "iso42001/2023/A.9.2",
            "target_title" => "AI system intake",
            "relation" => "partially_satisfied_by",
            "note" => "Use-approval process. Gap: Article 5 practice list."
          },
          %{
            "from_corpus_id" => "eu-ai-act/2024+2026-1744/art-4",
            "target_corpus_id" => "annex-sl-core/1.0/7.2",
            "relation" => "partially_satisfied_by",
            "note" => "Competence machinery. Gap: literacy coverage scope."
          }
        ]
      })

    assert results["has_classification"]
    assert results["classification"]["label"] == "prohibited"
    assert results["obligation_summary"]["total"] == 2
    assert results["obligation_summary"]["partial"] == 2

    art5 = Enum.find(results["obligations"], &(&1["short_id"] == "art-5"))
    assert art5["mapping_status"] == "partial"
    assert art5["progress_status"] == "addressed"
    assert hd(art5["satisfiers"])["answered_yes"]
    assert "Article 5 practice list" in art5["gap_notes"]

    art4 = Enum.find(results["obligations"], &(&1["short_id"] == "art-4"))
    assert art4["progress_status"] == "untouched"
    assert "literacy coverage scope" in art4["gap_notes"]
  end

  test "obligation with no satisfiers is open / unmapped" do
    results =
      AssessmentResults.build(%{
        assessment: %{
          "classification" => %{"classification" => "minimal-risk"},
          "activates" => ["eu-ai-act/2024+2026-1744/art-4"],
          "domains" => []
        },
        answers: [],
        question_sets: @sets,
        requirements: @requirements,
        satisfier_edges: []
      })

    [ob] = results["obligations"]
    assert results["classification"]["label"] == "minimal-risk"
    assert ob["mapping_status"] == "open"
    assert ob["progress_status"] == "unmapped"
  end
end
