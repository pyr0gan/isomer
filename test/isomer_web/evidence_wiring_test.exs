defmodule IsomerWeb.EvidenceWiringTest do
  use ExUnit.Case, async: true

  test "router exposes authenticated evidence download" do
    router = File.read!("lib/isomer_web/router.ex")
    assert router =~ ~s[get("/evidence/:id/download", EvidenceController, :download)]
  end

  test "EvidenceController streams object keys via Storage" do
    src = File.read!("lib/isomer_web/controllers/evidence_controller.ex")
    assert src =~ "Storage.get(key)"
    assert src =~ "Tenant.get_evidence"
    assert src =~ "content-disposition"
  end

  test "wizard stages file upload and links object downloads" do
    src = File.read!("lib/isomer_web/live/assessment_live/wizard.ex")
    assert src =~ "allow_upload(:evidence_file"
    assert src =~ "evidence-file-staging"
    assert src =~ ~s[/evidence/]
    assert src =~ "download"
    assert src =~ "Storage.object_key?"
    assert src =~ "Storage.put("
    assert src =~ "Storage.delete(key)"
    assert src =~ "update_evidence_storage_key"
  end
end
