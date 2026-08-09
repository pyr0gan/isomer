defmodule Mix.Tasks.Isomer.GitHooks do
  @shortdoc "Point git core.hooksPath at .githooks/ (pre-commit format/lint)"
  @moduledoc """
  Configures this repo to use `.githooks/` so commits run the same format /
  compile / lint checks that CI enforces.

      mix isomer.git_hooks
      # or via mix setup
  """

  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    hooks_dir = Path.expand(".githooks")
    pre_commit = Path.join(hooks_dir, "pre-commit")

    unless File.dir?(hooks_dir) and File.exists?(pre_commit) do
      Mix.raise("Expected #{pre_commit} to exist")
    end

    File.chmod!(pre_commit, 0o755)

    {_, 0} = System.cmd("git", ["config", "core.hooksPath", ".githooks"], cd: File.cwd!())
    Mix.shell().info("git.hooks: core.hooksPath=.githooks (pre-commit installed)")
  end
end
