defmodule IsomerWeb.SettingsPersistenceTest do
  use ExUnit.Case, async: true

  test "settings save requires Surreal persist and overlays prefs safely" do
    controller = File.read!("lib/isomer_web/controllers/settings_controller.ex")
    auth = File.read!("lib/isomer_web/user_auth.ex")
    tenant = File.read!("lib/isomer/db/tenant.ex")

    assert controller =~ "persist_prefs"
    assert controller =~ "Could not save preferences to your account"
    refute controller =~ "_ = Tenant.update_user_prefs"

    assert auth =~ "GuideCopy.overlay_prefs"
    refute auth =~ "Map.merge(surreal_prefs, session_prefs)"

    assert tenant =~ "FROM ONLY $auth"
    assert tenant =~ "SELECT id, email, name, self_role, experience_level, comfort_level"
  end
end
