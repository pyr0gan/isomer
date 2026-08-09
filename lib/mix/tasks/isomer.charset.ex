defmodule Mix.Tasks.Isomer.Charset do
  @shortdoc "Reject non-Latin letters in content files"
  @moduledoc "Scan corpus YAML/MD/JSON for disallowed non-Latin letters."

  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    case Isomer.Charset.run() do
      :ok -> :ok
      :error -> exit({:shutdown, 1})
    end
  end
end
