defmodule Isomer.ConfigVaultTest do
  use ExUnit.Case, async: false

  alias Isomer.Config

  setup do
    on_exit(fn ->
      for key <- ~w(VAULT_SKIP_VERIFY VAULT_CACERT VAULT_TOKEN VAULT_SECRET_PATH) do
        System.delete_env(key)
      end
    end)

    System.put_env("VAULT_TOKEN", "test-token")
    System.put_env("VAULT_SECRET_PATH", "kv/data/surreal")
    :ok
  end

  test "vault!/0 parses VAULT_SKIP_VERIFY" do
    System.put_env("VAULT_SKIP_VERIFY", "true")
    vault = Config.vault!()
    assert vault.skip_verify
    refute vault.cacert
  end

  test "vault!/0 parses VAULT_CACERT" do
    System.put_env("VAULT_CACERT", "/etc/vault/ca.pem")
    vault = Config.vault!()
    assert vault.cacert == "/etc/vault/ca.pem"
    refute vault.skip_verify
  end
end
