defmodule Mix.Tasks.Isomer.Db.EnsureRuntime do
  @shortdoc "Apply assessment runtime Surreal schema (auth + tenant tables)"
  @moduledoc """
  Defines Surreal record auth (`isomer_user`), org/member/assessment/answer/evidence/artifact
  tables, helper functions, and corpus read grants for authenticated users.

  See `docs/assessment-runtime.md`. Does not sync corpus content — run
  `mix isomer.db.sync` separately (usually first).

  After DEFINE, verifies:

  1. `user` has guidance-pref fields (`INFO FOR TABLE` + root SCHEMAFULL write)
  2. Required tenant tables exist (`INFO FOR DB`, including `artifact`)
  3. **Record-auth** signup can write prefs and `SELECT` from `artifact`

  Surreal Cloud hostnames often resolve to several IPs. A single root connection
  can leave later `DEFINE`s visible to CI probes but missing on the dyno. This
  task therefore applies ensure + the record-auth probe across several fresh
  connections (`ENSURE_RUNTIME_PASSES`, default 8).

  Prints a non-secret Surreal host fingerprint so Fly vs Actions target mismatches
  are obvious.

      mix isomer.db.ensure_runtime
  """

  use Mix.Task

  @default_passes 8

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    try do
      surreal = Isomer.Config.surreal!()
      target = Isomer.Config.surreal_target_fingerprint(surreal)
      passes = ensure_passes()
      Mix.shell().info("db:ensure_runtime target #{target} passes=#{passes}")

      {user_fields, tables} =
        Enum.reduce(1..passes, {nil, nil}, fn pass, _acc ->
          Mix.shell().info("db:ensure_runtime pass #{pass}/#{passes}")
          db = Isomer.Db.Connect.connect!()

          try do
            :ok = Isomer.Db.RuntimeSchema.ensure!(db)
            :ok = Isomer.Db.RuntimeSchema.assert_record_runtime!(db)
            fields = Isomer.Db.RuntimeSchema.user_field_names!(db)
            tables = Isomer.Db.RuntimeSchema.table_names!(db)
            {fields, tables}
          after
            SurrealDB.close(db)
          end
        end)

      Mix.shell().info("db:ensure_runtime OK")

      Mix.shell().info(
        Isomer.JSON.encode!(
          %{
            ok: true,
            target: target,
            passes: passes,
            access: Isomer.Db.RuntimeSchema.access_name(),
            user_fields: user_fields,
            tables: tables,
            required_tables: Isomer.Db.RuntimeSchema.required_tenant_tables(),
            docs: "docs/assessment-runtime.md"
          },
          pretty: true
        )
      )
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

  defp ensure_passes do
    case Integer.parse(System.get_env("ENSURE_RUNTIME_PASSES") || "") do
      {n, _} when n >= 1 and n <= 30 -> n
      _ -> @default_passes
    end
  end
end
