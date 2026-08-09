defmodule Mix.Tasks.Isomer.Validate do
  @shortdoc "Validate the on-disk governance corpus"
  @moduledoc """
  Runs schema + semantic checks over frameworks, requirements, mappings,
  rulesets, rubrics, questions, and templates.
  """

  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    case Isomer.Validate.run() do
      :ok -> :ok
      :error -> exit({:shutdown, 1})
    end
  end
end
