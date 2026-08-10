defmodule Mix.Tasks.Isomer.Db.EnsureRuntime do
  @shortdoc "Apply assessment runtime Surreal schema (auth + tenant tables)"
  @moduledoc """
  Defines Surreal record auth (`isomer_user`), org/member/assessment/answer/evidence
  tables, helper functions, and corpus read grants for authenticated users.

  See `docs/assessment-runtime.md`. Does not sync corpus content — run
  `mix isomer.db.sync` separately (usually first).

  After DEFINE, verifies `user` has guidance-pref fields (`self_role`,
  `experience_level`, `comfort_level`) via `INFO FOR TABLE` **and** a SCHEMAFULL
  write probe (INFO alone can be green while Settings still fails). Prints a
  non-secret Surreal host fingerprint so Fly vs Actions target mismatches are
  obvious.

      mix isomer.db.ensure_runtime
  """

  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    try do
      surreal = Isomer.Config.surreal!()
      target = Isomer.Config.surreal_target_fingerprint(surreal)
      Mix.shell().info("db:ensure_runtime target #{target}")

      db = Isomer.Db.Connect.connect!()

      try do
        :ok = Isomer.Db.RuntimeSchema.ensure!(db)
        user_fields = Isomer.Db.RuntimeSchema.user_field_names!(db)

        Mix.shell().info("db:ensure_runtime OK")

        Mix.shell().info(
          Isomer.JSON.encode!(
            %{
              ok: true,
              target: target,
              access: Isomer.Db.RuntimeSchema.access_name(),
              user_fields: user_fields,
              tables: [
                "user",
                "org",
                "member",
                "assessment",
                "answer",
                "evidence",
                "artifact"
              ],
              docs: "docs/assessment-runtime.md"
            },
            pretty: true
          )
        )
      after
        SurrealDB.close(db)
      end
    rescue
      e ->
        Mix.shell().error("db:ensure_runtime FAILED")
        Mix.shell().error(Exception.message(e))

        if System.get_env("DEBUG_SYNC") == "1" do
          Mix.shell().error(Exception.format(:error, e, __STACKTRACE__))
        end

        exit({:shutdown, 1})
    end
  end
end
