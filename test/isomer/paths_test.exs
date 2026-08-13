defmodule Isomer.PathsTest do
  use ExUnit.Case, async: true

  alias Isomer.Paths

  setup do
    root =
      Path.join(
        System.tmp_dir!(),
        "isomer-paths-" <> Integer.to_string(System.unique_integer([:positive]))
      )

    File.mkdir_p!(Path.join(root, "frameworks/demo/1.0"))
    File.write!(Path.join(root, "frameworks/demo/1.0/note.txt"), "ok")
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root}
  end

  test "join! keeps results under root", %{root: root} do
    path = Paths.join!(root, "frameworks/demo/1.0/note.txt")
    assert Paths.under_root?(path, root)
    assert File.read!(path) == "ok"
  end

  test "join! rejects parent traversal", %{root: root} do
    assert_raise ArgumentError, ~r/escapes corpus root/, fn ->
      Paths.join!(root, "../outside.txt")
    end
  end

  test "join! rejects absolute relatives", %{root: root} do
    assert_raise ArgumentError, ~r/absolute path/, fn ->
      Paths.join!(root, "/etc/passwd")
    end
  end

  test "segment! and schema_name! reject slashes and dots dots" do
    assert Paths.segment!("iso42001") == "iso42001"
    assert Paths.segment!("2024+2026-1744") == "2024+2026-1744"

    assert_raise ArgumentError, fn -> Paths.segment!("../etc") end
    assert_raise ArgumentError, fn -> Paths.segment!("a/b") end

    assert Paths.schema_name!("framework.schema.json") == "framework.schema.json"
    assert_raise ArgumentError, fn -> Paths.schema_name!("../framework.schema.json") end
  end

  test "wildcard! drops escapes and finds corpus files", %{root: root} do
    paths = Paths.wildcard!(root, "frameworks/*/*/note.txt")
    assert length(paths) == 1
    assert Paths.relative!(hd(paths), root) == "frameworks/demo/1.0/note.txt"

    assert_raise ArgumentError, ~r/\.\./, fn ->
      Paths.wildcard!(root, "frameworks/../../*")
    end
  end

  test "expand_under! confines CLI paths", %{root: root} do
    abs = Paths.expand_under!(root, "frameworks/demo/1.0/note.txt")
    assert abs == Path.expand("frameworks/demo/1.0/note.txt", root)

    assert_raise ArgumentError, ~r/escapes corpus root/, fn ->
      Paths.expand_under!(root, "../note.txt")
    end
  end
end
