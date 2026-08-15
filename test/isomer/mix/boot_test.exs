defmodule Isomer.Mix.BootTest do
  use ExUnit.Case, async: true

  test "isomer.db Mix tasks boot without Phoenix app.start" do
    paths = Path.wildcard("lib/mix/tasks/isomer.db.*.ex")
    assert paths != []

    for path <- paths do
      src = File.read!(path)
      refute src =~ ~s[Mix.Task.run("app.start")], "#{path} still calls app.start"
      assert src =~ "Isomer.Mix.Boot.start_for_db!", "#{path} missing Boot.start_for_db!"
    end
  end

  test "Application gates Endpoint on :start_endpoint" do
    src = File.read!("lib/isomer/application.ex")
    assert src =~ ":start_endpoint"
    assert src =~ "endpoint_children"
  end

  test "Boot module documents why Endpoint is skipped" do
    src = File.read!("lib/isomer/mix/boot.ex")
    assert src =~ "live-reload"
    assert src =~ "inotify"
  end
end
