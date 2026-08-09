defmodule Isomer.MixProject do
  use Mix.Project

  def project do
    [
      app: :isomer,
      version: "1.0.0",
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      elixirc_paths: elixirc_paths(Mix.env())
    ]
  end

  def cli do
    [
      preferred_envs: [
        "isomer.validate": :dev,
        "isomer.charset": :dev,
        "isomer.delta": :dev,
        "isomer.ruleset.eval": :dev,
        "isomer.db.ping": :dev,
        "isomer.db.sync": :dev,
        "isomer.db.ingest_sample": :dev,
        "isomer.sbom": :dev,
        "sbom.cyclonedx": :dev,
        sbom: :dev
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
      {:surrealdb, github: "surrealdb/surrealdb.elixir"},
      # CycloneDX SBoM generator (EEF mix_sbom). Dev-only — do not use MIX_ENV=prod.
      {:sbom, "~> 0.10", only: :dev, runtime: false}
    ]
  end

  defp aliases do
    [
      "lint.corpus": ["isomer.validate", "isomer.charset"],
      lint: ["lint.corpus"],
      sbom: ["isomer.sbom"]
    ]
  end
end
