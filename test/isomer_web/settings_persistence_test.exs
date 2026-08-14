defmodule IsomerWeb.SettingsPersistenceTest do
  use ExUnit.Case, async: true

  alias Isomer.Db.Tenant
  alias Isomer.GuideCopy

  test "settings save requires Surreal persist and overlays prefs safely" do
    controller = File.read!("lib/isomer_web/controllers/settings_controller.ex")
    auth = File.read!("lib/isomer_web/user_auth.ex")
    tenant = File.read!("lib/isomer/db/tenant.ex")

    assert controller =~ "persist_prefs"
    assert controller =~ "prefs_schema_missing"
    assert controller =~ "Could not save preferences to your account"
    refute controller =~ "_ = Tenant.update_user_prefs"

    assert auth =~ "GuideCopy.overlay_prefs"
    refute auth =~ "Map.merge(surreal_prefs, session_prefs)"

    assert tenant =~ "FROM ONLY $auth"
    assert tenant =~ "guide_prefs"
    assert tenant =~ "missing_user_field_error?"
  end

  test "missing_user_field_error? matches Surreal SCHEMAFULL messages" do
    assert Tenant.missing_user_field_error?(
             "Found field `comfort_level`, but no such field exists for table `user`"
           )

    assert Tenant.missing_user_field_error?(%{message: "no such field `guide_prefs`"})
    refute Tenant.missing_user_field_error?("connection timeout")
  end

  test "GuideCopy.normalize reads nested guide_prefs" do
    prefs =
      GuideCopy.normalize(%{
        "guide_prefs" => %{
          "self_role" => "engineering",
          "experience_level" => "beginner",
          "comfort_level" => "low"
        }
      })

    assert prefs["self_role"] == "engineering"
    assert prefs["experience_level"] == "beginner"
    assert prefs["comfort_level"] == "low"
  end

  test "runtime schema defines guide_prefs FLEXIBLE bag" do
    src = File.read!("lib/isomer/db/runtime_schema.ex")
    assert src =~ "guide_prefs"
    assert src =~ "FLEXIBLE"
  end
end
