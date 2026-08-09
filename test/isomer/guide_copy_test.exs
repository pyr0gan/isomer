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
end
