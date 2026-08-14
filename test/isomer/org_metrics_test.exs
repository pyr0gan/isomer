defmodule Isomer.OrgMetricsTest do
  use Isomer.Case, async: true

  alias Isomer.OrgMetrics

  test "sparkline_ready? needs at least two non-nil points" do
    refute OrgMetrics.sparkline_ready?([])
    refute OrgMetrics.sparkline_ready?([10])
    refute OrgMetrics.sparkline_ready?([10, nil])
    assert OrgMetrics.sparkline_ready?([10, 20])
    assert OrgMetrics.sparkline_ready?([nil, 10, 20])
  end

  test "sparkline_points returns nil without two values" do
    assert OrgMetrics.sparkline_points([1]) == nil
    assert OrgMetrics.sparkline_points([1, nil, nil]) == nil
  end

  test "sparkline_points builds SVG point pairs" do
    points = OrgMetrics.sparkline_points([0, 50, 100], 100, 20)
    assert is_binary(points)
    assert length(String.split(points, " ")) == 3
  end

  test "score_questions computes yes %, unanswered, and evidence coverage" do
    questions = [
      %{id: "q1", kind: "boolean", evidence_prompt: "Attach policy"},
      %{id: "q2", kind: "boolean", evidence_prompt: nil},
      %{id: "q3", kind: "text", evidence_prompt: "Note"}
    ]

    answers = %{"q1" => true, "q2" => false}
    notes = %{"q1" => "policy.pdf", "q3" => ""}

    stats = OrgMetrics.score_questions(questions, answers, notes)
    assert stats.yes_pct == 33
    assert stats.unanswered == 1
    assert stats.evidence_pct == 50
  end

  test "score_questions accepts evidence question-id MapSet from evidence rows" do
    questions = [
      %{id: "q1", kind: "boolean", evidence_prompt: "Attach policy"},
      %{id: "q2", kind: "boolean", evidence_prompt: "Attach register"}
    ]

    answers = %{"q1" => true, "q2" => true}
    evidence = MapSet.new(["q1"])

    stats = OrgMetrics.score_questions(questions, answers, evidence)
    assert stats.evidence_pct == 50
  end

  test "score_questions returns nil percentages when empty" do
    stats = OrgMetrics.score_questions([], %{}, %{})
    assert stats.yes_pct == nil
    assert stats.unanswered == 0
    assert stats.evidence_pct == nil
  end
end
