defmodule IsomerWeb.ResultsHeaderTest do
  use ExUnit.Case, async: true

  test "Results heading does not show status or kind tags" do
    src = File.read!("lib/isomer_web/live/assessment_live/results.ex")

    refute src =~ "status_label"
    refute src =~ "status_badge_color"
    refute src =~ ~s(assessment["kind"])

    assert src =~ ~s(results["classification"]["label"])
    assert src =~ "What applies, what mappings cover"
  end
end
