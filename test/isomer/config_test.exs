defmodule Isomer.ConfigTest do
  use ExUnit.Case, async: true

  alias Isomer.Config

  test "surreal_target_fingerprint never includes credentials" do
    fp =
      Config.surreal_target_fingerprint(%{
        url: "wss://example.surreal.cloud/rpc",
        namespace: "main",
        database: "main",
        username: "root"
      })

    assert fp == "host=example.surreal.cloud ns=main db=main"
    refute fp =~ "root"
    refute fp =~ "wss://"
  end
end
