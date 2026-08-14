defmodule Isomer.Db.TenantMembersTest do
  use Isomer.Case, async: true

  alias Isomer.Db.Tenant

  test "add_member_by_email validates email and refuses owner invites" do
    assert {:error, "Enter a valid email address."} =
             Tenant.add_member_by_email(:unused, "org:o1", "not-an-email", "assessor")

    assert {:error, "Promote an existing member to owner instead of inviting as owner."} =
             Tenant.add_member_by_email(:unused, "org:o1", "a@b.co", "owner")
  end
end
