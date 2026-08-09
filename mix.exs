defmodule Isomer.MixProject do
  use Mix.Project

  def project do
    [
      app: :isomer,
      version: "1.0.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      elixirc_paths: elixirc_paths(Mix.env()),
      preferred_cli_env: [
        "isomer.validate": :dev,
        "isomer.charset": :dev,
        "isomer.delta": :dev,
        "isomer.ruleset.eval": :dev,
        "isomer.db.ping": :dev,
        "isomer.db.sync": :dev,
        "isomer.db.ingest_sample": :dev
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto, :ssl, :inets]
    ]
  end

  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:jason, "~> 1.4"},
      {:yaml_elixir, "~> 2.9"},
      {:ex_json_schema, "~> 0.11"},
      {:req, "~> 0.5"},
      {:dotenvy, "~> 0.8"},
      {:surrealdb, github: "surrealdb/surrealdb.elixir"}
    ]
  end

  defp aliases do
    [
      "lint.corpus": ["isomer.validate", "isomer.charset"],
      lint: ["lint.corpus"]
    ]
  end
end
