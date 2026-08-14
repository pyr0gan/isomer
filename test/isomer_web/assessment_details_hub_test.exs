defmodule IsomerWeb.AssessmentDetailsHubTest do
  use ExUnit.Case, async: true

  test "Details hub wires overview, rename, lifecycle, and wizard domain deep links" do
    show = File.read!("lib/isomer_web/live/assessment_live/show.ex")
    wizard = File.read!("lib/isomer_web/live/assessment_live/wizard.ex")
    tenant = File.read!("lib/isomer/db/tenant.ex")

    assert show =~ "AssessmentOverview.build"
    assert show =~ "primary_action"
    assert show =~ "save_title"
    assert show =~ "Lifecycle"
    assert show =~ "wizard_domain_path"
    refute show =~ "Ruleset: <code"

    assert wizard =~ "def handle_params(params"
    assert wizard =~ ~S|Map.get(params, "domain")|

    assert tenant =~ "def update_assessment_title"
  end
end
