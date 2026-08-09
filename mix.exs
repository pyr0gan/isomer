defmodule Isomer.MixProject do
  use Mix.Project

  def project do
    [
      app: :isomer,
      version: "0.1.0",
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      elixirc_paths: elixirc_paths(Mix.env()),
      compilers: Mix.compilers(),
      # Required by Phoenix 1.8 code reloader (mix sync listener).
      listeners: [Phoenix.CodeReloader],
      releases: [
        isomer: [
          include_executables_for: [:unix],
          applications: [runtime_tools: :permanent]
        ]
      ]
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
        "isomer.db.ensure_runtime": :dev,
        "isomer.sbom": :dev,
        "sbom.cyclonedx": :dev,
        sbom: :dev
      ]
    ]
  end

  def application do
    [
      mod: {Isomer.Application, []},
      extra_applications: [:logger, :runtime_tools, :crypto, :ssl, :inets]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:jason, "~> 1.4"},
      {:yaml_elixir, "~> 2.9"},
      {:ex_json_schema, "~> 0.11.5"},
      # Override transitive decimal 2.x (EEF-CVE-2026-32686) until dependents catch up.
      {:decimal, "~> 3.1", override: true},
      {:req, "~> 0.5"},
      {:dotenvy, "~> 0.8"},
      {:surrealdb, github: "surrealdb/surrealdb.elixir"},
      {:phoenix, "~> 1.8"},
      {:phoenix_html, "~> 4.2"},
      {:phoenix_live_view, "~> 1.1"},
      {:phoenix_live_reload, "~> 1.5", only: :dev},
      {:bandit, "~> 1.6"},
      {:dns_cluster, "~> 0.2"},
      # UI (Petal free components). phoenix_ecto/ecto are required by Petal helpers
      # (Ecto.UUID); there is no Ecto Repo in this app.
      {:petal_components, "~> 4.12"},
      {:phoenix_ecto, "~> 4.4"},
      {:ecto, "~> 3.10"},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.2.0",
       app: false,
       compile: false,
       sparse: "optimized"},
      {:tailwind, "~> 0.5", runtime: Mix.env() == :dev},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      # CycloneDX SBoM generator (EEF mix_sbom). Dev-only — do not use MIX_ENV=prod.
      {:sbom, "~> 0.10", only: :dev, runtime: false}
    ]
  end

  defp aliases do
    [
      "lint.corpus": ["isomer.validate", "isomer.charset"],
      lint: ["lint.corpus"],
      sbom: ["isomer.sbom"],
      setup: ["deps.get", "assets.setup", "assets.build"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["tailwind isomer", "esbuild isomer"],
      "assets.deploy": [
        "tailwind isomer --minify",
        "esbuild isomer --minify",
        "phx.digest"
      ],
      "phx.server": ["app.config", "phx.server"]
    ]
  end
end
