defmodule IsomerWeb.EndpointSessionTest do
  use Isomer.Case, async: true

  test "session cookie is HttpOnly and SameSite=Lax" do
    opts = IsomerWeb.Endpoint.session_options()

    assert opts[:store] == :cookie
    assert opts[:key] == "_isomer_key"
    assert opts[:http_only] == true
    assert opts[:same_site] == "Lax"
  end

  test "Secure flag follows session_cookie_secure config" do
    opts = IsomerWeb.Endpoint.session_options()
    expected = Application.fetch_env!(:isomer, IsomerWeb.Endpoint)[:session_cookie_secure]

    assert expected == false
    assert Keyword.fetch!(opts, :secure) == false
  end

  test "prod config enables Secure on the session cookie" do
    contents = File.read!("config/prod.exs")
    assert contents =~ "session_cookie_secure: true"
  end
end
