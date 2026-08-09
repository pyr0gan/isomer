defmodule Mix.Tasks.Isomer.Ruleset.Eval do
  @shortdoc "Evaluate a classification ruleset (first-match)"
  @moduledoc """
      mix isomer.ruleset.eval --ruleset rulesets/eu-ai-act-classification.yaml \\
        --answers '{"role":"provider","annex-iii-area":"employment"}'
  """

  use Mix.Task

  alias Isomer.Corpus.Load
  alias Isomer.Ruleset.Evaluate
  alias Isomer.YAML

  @impl Mix.Task
  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        strict: [ruleset: :string, answers: :string, help: :boolean],
        aliases: [h: :help]
      )

    if opts[:help] do
      Mix.shell().info(@moduledoc)
      :ok
    else
      ruleset_path = opts[:ruleset] || "rulesets/eu-ai-act-classification.yaml"
      answers_json = opts[:answers]

      unless is_binary(answers_json) do
        Mix.shell().error("Missing --answers JSON")
        exit({:shutdown, 1})
      end

      answers =
        case Jason.decode(answers_json) do
          {:ok, map} when is_map(map) ->
            map

          {:ok, _} ->
            raise ArgumentError, "--answers must be a JSON object"

          {:error, err} ->
            raise ArgumentError, "Failed to parse --answers: #{Exception.message(err)}"
        end

      ruleset = YAML.read!(Path.expand(ruleset_path, Isomer.root()))
      corpus = Load.load()
      result = Evaluate.evaluate(ruleset, answers, Load.requirements_by_id(corpus))
      Mix.shell().info(Isomer.JSON.encode!(result, pretty: true))
    end
  end
end
