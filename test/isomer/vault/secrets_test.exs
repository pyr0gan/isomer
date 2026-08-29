defmodule Isomer.Vault.SecretsTest do
  use ExUnit.Case, async: true

  alias Isomer.Vault.Secrets

  describe "tls_connect_options/1" do
    test "returns empty list by default" do
      assert Secrets.tls_connect_options(%{}) == []
      assert Secrets.tls_connect_options(%{skip_verify: false}) == []
    end

    test "skip_verify adds verify_none transport opts" do
      assert Secrets.tls_connect_options(%{skip_verify: true}) ==
               [connect_options: [transport_opts: [verify: :verify_none]]]
    end

    test "cacert takes precedence over skip_verify" do
      assert Secrets.tls_connect_options(%{cacert: "/tmp/vault-ca.pem", skip_verify: true}) ==
               [
                 connect_options: [
                   transport_opts: [cacertfile: ~c"/tmp/vault-ca.pem", verify: :verify_peer]
                 ]
               ]
    end

    test "ignores blank cacert" do
      assert Secrets.tls_connect_options(%{cacert: ""}) == []
    end
  end
end
