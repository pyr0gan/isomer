defmodule Isomer do
  @moduledoc """
  Elixir tooling for the isomer governance content corpus.

  Mix tasks:

    mix isomer.validate
    mix isomer.charset
    mix isomer.delta PATH
    mix isomer.ruleset.eval --ruleset PATH --answers JSON
    mix isomer.db.ping
    mix isomer.db.sync [--dry-run] [--no-prune]
    mix isomer.db.ensure_runtime
    mix isomer.sbom [--pretty]
  """

  @doc "Repo root (directory containing mix.exs / corpus folders)."
  def root do
    Application.get_env(:isomer, :root) || File.cwd!()
  end
end
