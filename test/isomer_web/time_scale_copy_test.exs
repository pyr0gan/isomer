defmodule IsomerWeb.TimeScaleCopyTest do
  use ExUnit.Case, async: true

  test "wizard surfaces Time scale help next to the selector" do
    src = File.read!("lib/isomer_web/live/assessment_live/wizard.ex")
    assert src =~ "GuideCopy.time_scale_help(@guide_prefs)"
    assert src =~ ~s(id={"time-scale-help-\#{section.id}"})
    assert src =~ ~s(aria-describedby={"time-scale-help-\#{section.id}"})
    assert src =~ "Relative effort for this domain, not a calendar period"
  end

  test "org Objective metrics explains Time scale on the dashboard" do
    src = File.read!("lib/isomer_web/live/org_live/show.ex")
    assert src =~ "GuideCopy.org_time_scale_help(@guide_prefs)"
    assert src =~ "Time scale is relative effort, not a calendar period"
  end
end
