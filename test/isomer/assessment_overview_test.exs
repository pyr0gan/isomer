defmodule Isomer.AssessmentOverviewTest do
  use Isomer.Case, async: true

  alias Isomer.AssessmentOverview

  @sets [
    %{
      "domain" => "ai-lifecycle",
      "questions" => [
        %{"id" => "al-01", "kind" => "boolean"},
        %{"id" => "al-02", "kind" => "boolean", "evidence_prompt" => "Attach policy"},
        %{"id" => "al-03", "kind" => "boolean"}
      ]
    }
  ]

  test "build reports progress, evidence coverage, and continue CTA" do
    overview =
      AssessmentOverview.build(%{
        assessment: %{
          "title" => "Run A",
          "status" => "in_progress",
          "domains" => ["ai-lifecycle"],
          "domain_metrics" => %{"ai-lifecycle" => %{"collect" => true}}
        },
        question_sets: @sets,
        answers: [
          %{"question_id" => "al-01", "value" => %{"v" => true}},
          %{"question_id" => "al-02", "value" => %{"v" => false}}
        ],
        evidence_rows: [%{"question_id" => "al-02"}],
        ruleset: nil
      })

    assert overview["total"] == 3
    assert overview["answered"] == 2
    assert overview["unanswered"] == 1
    assert overview["evidence_pct"] == 100
    assert overview["primary_action"]["kind"] == "wizard"
    assert overview["primary_action"]["label"] =~ "1 open"

    section = hd(overview["sections"])
    assert section["id"] == "ai-lifecycle"
    assert section["answered"] == 2
    assert section["collect"] == true
  end

  test "complete questionnaire points at Results; finalized points at artifacts" do
    answers =
      for id <- ["al-01", "al-02", "al-03"] do
        %{"question_id" => id, "value" => %{"v" => true}}
      end

    ready =
      AssessmentOverview.build(%{
        assessment: %{"status" => "in_progress", "domains" => ["ai-lifecycle"]},
        question_sets: @sets,
        answers: answers,
        evidence_rows: [],
        ruleset: nil
      })

    assert ready["unanswered"] == 0
    assert ready["primary_action"]["kind"] == "results"

    done =
      AssessmentOverview.build(%{
        assessment: %{"status" => "complete", "domains" => ["ai-lifecycle"]},
        question_sets: @sets,
        answers: answers,
        evidence_rows: [],
        ruleset: nil
      })

    assert done["primary_action"]["kind"] == "artifacts"
    assert done["finalized"] == true
  end

  test "classification section is included when a ruleset has questions" do
    overview =
      AssessmentOverview.build(%{
        assessment: %{
          "status" => "draft",
          "domains" => [],
          "ruleset_id" => "eu-ai-act/2024+2026-1744/classification",
          "classification" => %{"label" => "high-risk"},
          "activates" => ["eu-ai-act/2024+2026-1744/art-6"]
        },
        question_sets: @sets,
        answers: [],
        evidence_rows: [],
        ruleset: %{
          "questions" => [
            %{"id" => "rs-1", "kind" => "boolean"}
          ]
        }
      })

    assert overview["has_ruleset"]
    assert overview["classification_label"] == "high-risk"
    assert overview["activates_count"] == 1
    assert hd(overview["sections"])["id"] == "__classification__"
    assert overview["total"] == 1
  end
end
