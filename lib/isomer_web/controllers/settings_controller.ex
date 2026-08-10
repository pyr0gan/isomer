defmodule IsomerWeb.SettingsController do
  @moduledoc """
  HTTP save for guidance prefs.

  Pref columns on Surreal `user` may be missing on some Surreal Cloud compute
  nodes even after CI ensure. Display name still updates via `UPDATE $auth SET name`.
  Role / experience / comfort are stored in the cookie session so LiveViews can
  adapt copy without those columns.
  """

  use IsomerWeb, :controller

  alias Isomer.Db.Tenant
  alias Isomer.Db.UserClient

  def update(conn, params) do
    prefs = %{
      "self_role" => blank_to_nil(Map.get(params, "self_role")),
      "experience_level" => blank_to_nil(Map.get(params, "experience_level")),
      "comfort_level" => blank_to_nil(Map.get(params, "comfort_level"))
    }

    name = Map.get(params, "name", "") |> to_string() |> String.trim()

    conn =
      conn
      |> put_session(:guide_prefs, prefs)
      |> put_session(:guide_name, name)

    token = get_session(conn, :surreal_token)

    surreal_result =
      if is_binary(token) and token != "" do
        case UserClient.connect_with_token(token) do
          {:ok, db} ->
            try do
              # Name always works on the live schema. Pref columns are best-effort.
              _ = Tenant.update_user_prefs(db, Map.put(prefs, "name", name))
              :ok
            after
              UserClient.stop(db)
            end

          {:error, _} ->
            :ok
        end
      else
        :ok
      end

    _ = surreal_result

    conn
    |> put_flash(
      :info,
      "Preferences saved — guidance copy will adapt on the next pages you open."
    )
    |> redirect(to: ~p"/settings")
  end

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil

  defp blank_to_nil(value) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: nil, else: value
  end

  defp blank_to_nil(value), do: value
end
