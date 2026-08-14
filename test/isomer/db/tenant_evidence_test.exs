defmodule Isomer.Db.TenantEvidenceTest do
  use Isomer.Case, async: true

  alias Isomer.Db.Tenant

  test "create_evidence requires a non-empty label" do
    assert {:error, "Evidence label is required."} =
             Tenant.create_evidence(:unused_conn, %{
               "org_id" => "org:o1",
               "answer_id" => "answer:a1",
               "label" => "   "
             })
  end
end
