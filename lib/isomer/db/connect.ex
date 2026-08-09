defmodule Isomer.Db.Connect do
  @moduledoc "SurrealDB WSS connect + ping (password from Vault)."

  alias Isomer.Config
  alias Isomer.Vault.Secrets

  def connect!(overrides \\ %{}) do
    surreal = Map.merge(Config.surreal!(), overrides)
    vault = Config.vault!()
    password = Secrets.get_surreal_password!(vault)

    opts = [
      url: surreal.url,
      namespace: surreal.namespace,
      database: surreal.database,
      auth: %SurrealDB.Auth.Root{user: surreal.username, pass: password}
    ]

    case SurrealDB.start_link(opts) do
      {:ok, db} -> db
      {:error, reason} -> raise "SurrealDB connect failed: #{inspect(reason)}"
    end
  end

  def ping!(overrides \\ %{}) do
    surreal = Map.merge(Config.surreal!(), overrides)

    try do
      db = connect!(overrides)

      try do
        case SurrealDB.query(db, "RETURN 'isomer-ok';") do
          {:ok, result} ->
            %{
              ok: true,
              url: surreal.url,
              namespace: surreal.namespace,
              database: surreal.database,
              result: result
            }

          {:error, err} ->
            raise auth_or_error(err, surreal)
        end
      after
        SurrealDB.close(db)
      end
    rescue
      e ->
        reraise auth_or_error(e, surreal), __STACKTRACE__
    end
  end

  defp auth_or_error(err, surreal) do
    msg =
      case err do
        %{message: m} when is_binary(m) -> m
        _ -> Exception.message(err)
      end

    cond do
      String.contains?(msg, "InvalidAuth") ->
        %RuntimeError{
          message:
            "SurrealDB authentication failed (InvalidAuth). " <>
              "Confirm the password stored in Vault matches a Root user in Surrealist " <>
              "(Authentication → Root Authentication), and that SURREAL_USERNAME matches that user."
        }

      String.contains?(msg, "Vault") or String.contains?(msg, "Missing required env") ->
        if is_exception(err), do: err, else: %RuntimeError{message: msg}

      true ->
        %RuntimeError{message: "SurrealDB error at #{surreal.url}: #{msg}"}
    end
  end
end
