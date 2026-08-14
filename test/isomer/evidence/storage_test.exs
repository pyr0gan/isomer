defmodule Isomer.Evidence.StorageTest do
  use ExUnit.Case, async: false

  alias Isomer.Evidence.Storage
  alias Isomer.Evidence.Storage.Local
  alias Isomer.Evidence.Storage.Memory

  setup do
    Memory.reset!()
    :ok
  end

  test "memory backend put/get/delete round-trip" do
    assert Storage.backend() == Memory

    key = "org/o1/assessment/a1/evidence/e1"
    body = "hello evidence"
    meta = %{"content_type" => "text/plain", "filename" => "note.txt"}

    assert :ok = Storage.put(key, body, meta)
    assert {:ok, ^body, got_meta} = Storage.get(key)
    assert got_meta["content_type"] == "text/plain"
    assert :ok = Storage.delete(key)
    assert {:error, :not_found} = Storage.get(key)
  end

  test "object_key?/1 rejects blank and http(s) URLs" do
    assert Storage.object_key?("org/o1/assessment/a1/evidence/e1")
    refute Storage.object_key?("")
    refute Storage.object_key?("https://example.com/doc.pdf")
    refute Storage.object_key?("http://example.com/doc.pdf")
    refute Storage.object_key?(nil)
  end

  test "build_key/3 sanitizes record prefixes and unsafe chars" do
    assert Storage.build_key("org:acme", "assessment:a1", "evidence:e/../x") ==
             "org/acme/assessment/a1/evidence/e_.._x"
  end

  test "local backend writes under configured root" do
    root = Path.join(System.tmp_dir!(), "isomer-evidence-test-#{System.unique_integer([:positive])}")
    File.rm_rf!(root)
    File.mkdir_p!(root)

    previous = Application.get_env(:isomer, Storage, [])

    on_exit(fn ->
      Application.put_env(:isomer, Storage, previous)
      File.rm_rf!(root)
    end)

    Application.put_env(:isomer, Storage, backend: Local, local_root: root)
    System.put_env("EVIDENCE_LOCAL_ROOT", root)

    try do
      key = "org/o1/assessment/a1/evidence/e2"
      assert :ok = Local.put(key, "bytes", %{"content_type" => "application/pdf"})
      assert {:ok, "bytes", meta} = Local.get(key)
      assert meta["content_type"] == "application/pdf"
      assert :ok = Local.delete(key)
      assert {:error, :not_found} = Local.get(key)
    after
      System.delete_env("EVIDENCE_LOCAL_ROOT")
    end
  end
end
