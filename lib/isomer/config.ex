defmodule Isomer.Config do
  @moduledoc "Environment configuration for SurrealDB + Vault."

  def load_dotenv! do
    path = Path.join(Isomer.root(), ".env")

    if File.exists?(path) do
      path
      |> File.read!()
      |> String.split(~r/\R/, trim: true)
      |> Enum.each(fn line ->
        line = String.trim(line)

        cond do
          line == "" ->
            :ok

          String.starts_with?(line, "#") ->
            :ok

          true ->
            case String.split(line, "=", parts: 2) do
              [k, v] ->
                k = String.trim(k)
                v = v |> String.trim() |> String.trim("'\"")

                if System.get_env(k) in [nil, ""] do
                  System.put_env(k, v)
                end

              _ ->
                :ok
            end
        end
      end)
    end

    :ok
  end

  def surreal! do
    load_dotenv!()

    %{
      url: required!("SURREAL_URL"),
      namespace: required!("SURREAL_NAMESPACE"),
      database: required!("SURREAL_DATABASE"),
      username: optional("SURREAL_USERNAME", "root")
    }
    |> assert_resolved([:url, :namespace, :database, :username])
  end

  def vault! do
    load_dotenv!()
    token = optional("VAULT_TOKEN")
    role_id = optional("VAULT_ROLE_ID")
    secret_id = optional("VAULT_SECRET_ID")

    if is_nil(token) and not (is_binary(role_id) and is_binary(secret_id)) do
      raise ArgumentError,
            "Vault auth missing: set VAULT_TOKEN, or both VAULT_ROLE_ID and VAULT_SECRET_ID"
    end

    %{
      addr: optional("VAULT_ADDR", "https://v.omega-agent.cloud") |> String.trim_trailing("/"),
      token: token,
      role_id: role_id,
      secret_id: secret_id,
      path: required!("VAULT_SECRET_PATH"),
      field: optional("VAULT_SECRET_FIELD", "password"),
      kv_version: optional("VAULT_KV_VERSION")
    }
    |> assert_resolved([:addr, :path, :field])
  end

  defp required!(name) do
    case System.get_env(name) do
      nil ->
        raise ArgumentError,
              "Missing required env var #{name}. Copy .env.example to .env and fill values."

      "" ->
        raise ArgumentError, "Missing required env var #{name} (empty)."

      value ->
        String.trim(value)
    end
  end

  defp optional(name, default \\ nil) do
    case System.get_env(name) do
      nil -> default
      "" -> default
      value -> String.trim(value)
    end
  end

  defp assert_resolved(map, keys) do
    Enum.each(keys, fn key ->
      case Map.get(map, key) do
        <<"op://", _::binary>> = v ->
          raise ArgumentError,
                "#{key} still looks like a 1Password reference (#{v}). Run via `op run --env-file=.env -- mix …`."

        _ ->
          :ok
      end
    end)

    map
  end
end
