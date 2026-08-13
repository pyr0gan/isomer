defmodule Isomer.SbomTest do
  use ExUnit.Case, async: true

  alias Isomer.Sbom

  @sample %{
    "bomFormat" => "CycloneDX",
    "specVersion" => "1.6",
    "serialNumber" => "urn:uuid:11111111-1111-1111-1111-111111111111",
    "version" => 1,
    "metadata" => %{
      "timestamp" => "2026-01-01T00:00:00Z",
      "component" => %{"name" => "isomer", "version" => "0.1.2"}
    },
    "components" => [
      %{"name" => "jason", "version" => "1.4.5"},
      %{"name" => "bandit", "version" => "1.12.4"}
    ]
  }

  test "canonicalize drops volatile fields" do
    canon = Sbom.canonicalize(@sample)
    refute Map.has_key?(canon, "serialNumber")
    refute Map.has_key?(canon, "version")
    refute Map.has_key?(canon["metadata"], "timestamp")
    assert canon["metadata"]["component"]["name"] == "isomer"
    assert length(canon["components"]) == 2
  end

  test "content_hash is stable across volatile field changes" do
    other =
      @sample
      |> Map.put("serialNumber", "urn:uuid:22222222-2222-2222-2222-222222222222")
      |> Map.put("version", 99)
      |> put_in(["metadata", "timestamp"], "2099-12-31T23:59:59Z")

    assert Sbom.content_hash(@sample) == Sbom.content_hash(other)
  end

  test "content_hash changes when dependencies change" do
    changed = update_in(@sample, ["components"], fn comps -> tl(comps) end)
    refute Sbom.content_hash(@sample) == Sbom.content_hash(changed)
  end
end
