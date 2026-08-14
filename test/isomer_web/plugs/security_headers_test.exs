defmodule IsomerWeb.Plugs.SecurityHeadersTest do
  use Isomer.Case, async: true
  import Plug.Conn
  import Plug.Test

  alias IsomerWeb.Plugs.SecurityHeaders

  @opts SecurityHeaders.init(enabled: true)

  test "sets HSTS when the request arrived as HTTPS via the proxy" do
    conn =
      :get
      |> conn("/login")
      |> put_req_header("x-forwarded-proto", "https")
      |> SecurityHeaders.call(@opts)

    assert get_resp_header(conn, "strict-transport-security") == [
             SecurityHeaders.hsts_header_value()
           ]

    assert SecurityHeaders.hsts_header_value() =~ "max-age="
  end

  test "sets HSTS when conn.scheme is https" do
    conn =
      :get
      |> conn("https://isomer-demo.fly.dev/login")
      |> SecurityHeaders.call(@opts)

    assert get_resp_header(conn, "strict-transport-security") == [
             SecurityHeaders.hsts_header_value()
           ]
  end

  test "does not set HSTS on cleartext (Fly internal /health)" do
    conn =
      :get
      |> conn("/health")
      |> SecurityHeaders.call(@opts)

    assert get_resp_header(conn, "strict-transport-security") == []
  end

  test "does not set HSTS when disabled" do
    conn =
      :get
      |> conn("/login")
      |> put_req_header("x-forwarded-proto", "https")
      |> SecurityHeaders.call(SecurityHeaders.init(enabled: false))

    assert get_resp_header(conn, "strict-transport-security") == []
  end

  test "prod config enables HSTS" do
    contents = File.read!("config/prod.exs")
    assert contents =~ "hsts: true"
  end
end
