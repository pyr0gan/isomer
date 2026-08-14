defmodule IsomerWeb.OrgLayoutTest do
  use ExUnit.Case, async: true

  test "org dashboard opens maturity/metrics and links to a members page" do
    show = File.read!("lib/isomer_web/live/org_live/show.ex")
    members = File.read!("lib/isomer_web/live/org_live/members.ex")
    router = File.read!("lib/isomer_web/router.ex")
    layout = File.read!("lib/isomer_web/components/layouts/app.html.heex")

    assert show =~ "open={true}"
    assert show =~ "Maturity & metrics"
    refute show =~ "expands when you want the charts"
    refute show =~ "phx-submit=\"invite_member\""
    assert show =~ ~S("/orgs/#{@org_id}/members")

    assert members =~ "defmodule IsomerWeb.OrgLive.Members"
    assert members =~ "phx-submit=\"invite_member\""
    assert members =~ "Only owners and admins can manage members."

    assert router =~ ~S[live("/orgs/:org_id/members", OrgLive.Members, :index)]
    assert layout =~ ~S("/orgs/#{@nav_org_id}/members")
    assert layout =~ "nav_show_members"
  end
end
