defmodule Isomer.Mix.Boot do
  @moduledoc """
  Starts the OTP app for Mix DB tasks **without** Phoenix.

  `mix isomer.db.sync` / `ensure_runtime` / etc. only need Config, Vault, and the
  Surreal client. Calling `Mix.Task.run("app.start")` under `MIX_ENV=dev` (CI
  default) also boots `IsomerWeb.Endpoint`, which tries Phoenix live-reload /
  `file_system` / inotify and prints noisy errors on GitHub Actions runners.

  Call `start_for_db!/0` from those tasks instead of raw `app.start`.
  """

  @doc """
  Starts `:isomer` with `IsomerWeb.Endpoint` omitted.

  Safe to call more than once (subsequent `app.start` is a no-op when already
  started). Idempotent w.r.t. `:start_endpoint` — leaves the flag false.

  Does **not** mutate Endpoint compile-time keys such as `:code_reloader`
  (Phoenix validates those at boot). Skipping the child is enough.
  """
  def start_for_db! do
    # Must be set before the Application module builds its child list.
    Application.put_env(:isomer, :start_endpoint, false)
    Mix.Task.run("app.start")
    :ok
  end
end
