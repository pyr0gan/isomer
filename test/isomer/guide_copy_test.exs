defmodule Isomer.GuideCopyTest do
  use ExUnit.Case, async: true

  alias Isomer.GuideCopy

  test "normalize accepts unknown values as unset" do
    prefs = GuideCopy.normalize(%{"self_role" => "wizard", "experience_level" => "beginner"})
    assert prefs["self_role"] == nil
    assert prefs["experience_level"] == "beginner"
  end

  test "guided? is true for beginners and unset prefs" do
    assert GuideCopy.guided?(%{})
    assert GuideCopy.guided?(%{"experience_level" => "beginner"})
    refute GuideCopy.concise?(%{"experience_level" => "beginner", "comfort_level" => "low"})
  end

  test "concise? only when practitioner/expert and high comfort" do
    assert GuideCopy.concise?(%{
             "experience_level" => "expert",
             "comfort_level" => "high"
           })

    refute GuideCopy.concise?(%{
             "experience_level" => "expert",
             "comfort_level" => "low"
           })
  end

  test "wizard_lede and question_help adapt by role" do
    beginner = %{"experience_level" => "beginner", "self_role" => "executive"}
    assert GuideCopy.wizard_lede(beginner, false) =~ "one domain"
    assert GuideCopy.question_help(beginner, %{level: "L1"}) =~ "ownership"

    expert = %{"experience_level" => "expert", "comfort_level" => "high"}
    assert GuideCopy.wizard_lede(expert, false) =~ "Answers save"
    assert GuideCopy.question_help(expert, %{level: "L1"}) == nil
  end

  test "artifacts discovery copy points at per-assessment generation" do
    assert GuideCopy.artifacts_nav_label() == "Generate documents"
    assert GuideCopy.artifacts_intro(%{}) =~ "This is where documents for this assessment"
    assert GuideCopy.library_empty_artifacts(%{}) =~ "Generate documents"
  end

  test "overlay_prefs keeps Surreal values when session overlay is empty or nil-filled" do
    surreal = %{
      "self_role" => "engineering",
      "experience_level" => "beginner",
      "comfort_level" => "low"
    }

    assert GuideCopy.overlay_prefs(surreal, %{}) == surreal
    assert GuideCopy.overlay_prefs(surreal, nil) == surreal

    wiped_shape = %{
      "self_role" => nil,
      "experience_level" => nil,
      "comfort_level" => nil
    }

    assert GuideCopy.overlay_prefs(surreal, wiped_shape) == surreal
  end

  test "overlay_prefs lets non-nil session values win without clearing other fields" do
    surreal = %{
      "self_role" => "engineering",
      "experience_level" => "beginner",
      "comfort_level" => "low"
    }

    assert GuideCopy.overlay_prefs(surreal, %{"self_role" => "security"}) == %{
             "self_role" => "security",
             "experience_level" => "beginner",
             "comfort_level" => "low"
           }
  end

  test "time_scale_help explains relative effort, not a calendar period" do
    beginner = %{"experience_level" => "beginner"}
    expert = %{"experience_level" => "expert", "comfort_level" => "high"}

    assert GuideCopy.time_scale_help(beginner) =~ "relative effort rating"
    assert GuideCopy.time_scale_help(beginner) =~ "not a date range"
    assert GuideCopy.time_scale_help(beginner) =~ "Neither field affects maturity scores"
    assert GuideCopy.time_scale_help(expert) =~ "not a calendar period"
    assert GuideCopy.time_scale_help(expert) =~ "Neither changes scores"

    assert GuideCopy.org_time_scale_help(beginner) =~ "not a calendar period"
    assert GuideCopy.org_time_scale_help(beginner) =~ "Neither changes maturity scores"
    assert GuideCopy.org_time_scale_help(expert) =~ "relative effort"
  end

  test "evidence_help_text keeps the prompt and a short sufficiency line" do
    prefs = %{"experience_level" => "beginner"}
    prompt = "Attach the approved policy and a communication/acknowledgement record."

    assert GuideCopy.evidence_help_text(prefs, prompt) ==
             prompt <>
               " Attach a label plus URL or reference below — a filename or ticket link is enough."

    assert GuideCopy.evidence_help_text(prefs, nil) ==
             "Attach a label plus URL or reference below — a filename or ticket link is enough."
  end
end
