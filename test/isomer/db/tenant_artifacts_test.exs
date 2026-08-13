defmodule Isomer.Db.TenantArtifactsTest do
  use Isomer.Case, async: true

  alias Isomer.Db.Tenant

  test "artifact pack constants are the supported storage markers" do
    assert Tenant.artifact_pack() == "question_set"
    assert Tenant.artifact_pack_ref() == "__artifacts__"
  end
end
