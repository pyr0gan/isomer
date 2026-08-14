defmodule IsomerWeb.SettingsController do
  @moduledoc """
  HTTP save for guidance prefs.

  Surreal `user` is the system of record (`self_role` / `experience_level` /
  `comfort_level` / `name`). The cookie session keeps a compact overlay so
  LiveViews can adapt immediately and survive brief Surreal read lag. Session
  nils never wipe Surreal values (`GuideCopy.overlay_prefs/2`).
  """

  use IsomerWeb, :controller

  require Logger

  alias Isomer.Db.Tenant
  alias Isomer.Db.UserClient

  def update(conn, params) do
    prefs = %{
      "self_role" => blank_to_nil(Map.get(params, "self_role")),
      "experience_level" => blank_to_nil(Map.get(params, "experience_level")),
      "comfort_level" => blank_to_nil(Map.get(params, "comfort_level"))
    }

    name = Map.get(params, "name", "") |> to_string() |> String.trim()

    # Only store set keys in the cookie (smaller + overlay-safe).
    session_prefs =
      prefs
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()

    conn =
      conn
      |> put_session(:guide_prefs, session_prefs)
      |> put_session(:guide_name, name)

    case persist_prefs(conn, Map.put(prefs, "name", name)) do
      :ok ->
        conn
        |> put_flash(
          :info,
          "Preferences saved — guidance copy will adapt on the next pages you open."
        )
        |> redirect(to: ~p"/settings")

      {:error, reason} ->
        Logger.warning("settings prefs persist failed: #{inspect(reason)}")

        conn
        |> put_flash(
          :error,
          "Could not save preferences to your account (#{format_error(reason)}). " <>
            "Check your connection and try again."
        )
        |> redirect(to: ~p"/settings")
    end
  end

  defp persist_prefs(conn, attrs) do
    token = get_session(conn, :surreal_token)

    if is_binary(token) and token != "" do
      case UserClient.connect_with_token(token) do
        {:ok, db} ->
          try do
            case Tenant.update_user_prefs(db, attrs) do
              {:ok, _row} -> :ok
              {:error, reason} -> {:error, reason}
            end
          after
            UserClient.stop(db)
          end

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, :not_signed_in}
    end
  end

  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(%{message: msg}) when is_binary(msg), do: msg
  defp format_error(:not_signed_in), do: "not signed in"
  defp format_error(reason), do: inspect(reason)

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil

  defp blank_to_nil(value) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: nil, else: value
  end

  defp blank_to_nil(value), do: value
end
