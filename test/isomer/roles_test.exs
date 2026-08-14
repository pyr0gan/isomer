defmodule Isomer.RolesTest do
  use Isomer.Case, async: true

  alias Isomer.Roles

  test "role labels and options" do
    assert Roles.label("owner") == "Owner"
    assert {"Assessor", "assessor"} in Roles.options()
    assert {"Viewer", "viewer"} in Roles.invite_options()
    refute Enum.any?(Roles.invite_options(), fn {_, role} -> role == "owner" end)
  end

  test "authorization helpers" do
    assert Roles.can_manage_members?("owner")
    assert Roles.can_manage_members?("admin")
    refute Roles.can_manage_members?("assessor")

    assert Roles.can_write?("assessor")
    refute Roles.can_write?("viewer")

    assert Roles.can_delete_org?("owner")
    refute Roles.can_delete_org?("admin")

    assert Roles.can_delete_assessment?("admin")
    refute Roles.can_delete_assessment?("assessor")
  end

  test "normalize defaults unknown roles to viewer" do
    assert Roles.normalize("admin") == "admin"
    assert Roles.normalize("nope") == "viewer"
    assert Roles.normalize(nil) == "viewer"
  end
end
