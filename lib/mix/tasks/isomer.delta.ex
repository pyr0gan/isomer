defmodule Mix.Tasks.Isomer.Delta do
  @shortdoc "Print integration coverage delta for a mapping set"
  @moduledoc """
      mix isomer.delta mappings/iso42001-2023--iso27001-2022.yaml
  """

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    case args do
      [path] ->
        Isomer.DeltaReport.run(path)

      _ ->
        Mix.shell().error("Usage: mix isomer.delta PATH")
        exit({:shutdown, 1})
    end
  end
end
