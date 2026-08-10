defmodule Isomer.Db.UserClient do
  @moduledoc """
  Per-user SurrealDB connection using `ACCESS isomer_user` JWT.

  Root/`Isomer.Db.Connect` stays Mix-only. The web app never holds the Surreal root password.
  """

  require Logger

  alias Isomer.Config
  alias SurrealDB.Auth

  @access "isomer_user"
  # Surreal Cloud free tiers often pause; first WSS after idle can exceed the SDK default.
  @connect_timeout 30_000
  @auth_attempts 3
  @auth_backoff_ms 400

  def start_link(opts \\ []) do
    surreal = Config.surreal!()

    SurrealDB.start_link(
      url: Keyword.get(opts, :url, surreal.url),
      namespace: Keyword.get(opts, :namespace, surreal.namespace),
      database: Keyword.get(opts, :database, surreal.database),
      connect_timeout: Keyword.get(opts, :connect_timeout, @connect_timeout)
    )
  end

  @doc "Open an anonymous connection and authenticate with an existing JWT."
  def connect_with_token(token) when is_binary(token) do
    with_connect_retry(fn ->
      case start_link() do
        {:ok, conn} ->
          case SurrealDB.authenticate(conn, token) do
            {:ok, _} ->
              {:ok, conn}

            {:error, reason} ->
              SurrealDB.close(conn)
              {:error, reason}
          end

        {:error, reason} ->
          {:error, reason}
      end
    end)
  end

  def signup!(attrs) when is_map(attrs) do
    email = fetch_string!(attrs, "email")
    password = fetch_string!(attrs, "password")
    name = Map.get(attrs, "name") || email
    auth_flow(:signup, email, password, %{"name" => name})
  end

  def signin!(email, password) when is_binary(email) and is_binary(password) do
    auth_flow(:signin, email, password, %{})
  end

  def query(conn, sql, vars \\ %{}) do
    SurrealDB.query(conn, sql, vars)
  end

  def info(conn), do: SurrealDB.info(conn)

  def stop(conn) do
    SurrealDB.close(conn)
  end

  @doc """
  True when the failure is a transport/setup timeout (retryable), not bad credentials.
  """
  def transient_error?(reason), do: match_transient?(reason)

  defp auth_flow(kind, email, password, extra) do
    with_connect_retry(fn ->
      case start_link() do
        {:ok, conn} ->
          auth = record_auth(email, password, extra)

          result =
            case kind do
              :signup -> SurrealDB.signup(conn, auth)
              :signin -> SurrealDB.signin(conn, auth)
            end

          case result do
            {:ok, token} when is_binary(token) ->
              {:ok, %{conn: conn, token: token, email: email}}

            {:ok, %{"token" => token}} when is_binary(token) ->
              {:ok, %{conn: conn, token: token, email: email}}

            {:error, reason} ->
              SurrealDB.close(conn)
              {:error, reason}
          end

        {:error, reason} ->
          {:error, reason}
      end
    end)
  end

  defp with_connect_retry(fun), do: with_connect_retry(fun, 1)

  defp with_connect_retry(fun, attempt) when attempt < @auth_attempts do
    case fun.() do
      {:error, reason} = err ->
        if match_transient?(reason) do
          Logger.warning(
            "surreal connect transient failure attempt=#{attempt}/#{@auth_attempts} reason=#{inspect_reason(reason)}"
          )

          Process.sleep(@auth_backoff_ms * attempt)
          with_connect_retry(fun, attempt + 1)
        else
          err
        end

      other ->
        other
    end
  end

  defp with_connect_retry(fun, _attempt), do: fun.()

  defp match_transient?(%{kind: kind}) when kind in [:connection, :timeout], do: true

  defp match_transient?(%{message: msg}) when is_binary(msg) do
    msg = String.downcase(msg)

    String.contains?(msg, "timed out") or
      String.contains?(msg, "timeout") or
      String.contains?(msg, "could not connect") or
      String.contains?(msg, "transport")
  end

  defp match_transient?(%Mint.TransportError{}), do: true
  defp match_transient?({:error, reason}), do: match_transient?(reason)
  defp match_transient?(_), do: false

  defp inspect_reason(%{message: msg}) when is_binary(msg), do: msg
  defp inspect_reason(reason), do: inspect(reason)

  defp record_auth(email, password, extra) do
    surreal = Config.surreal!()

    %Auth.Record{
      namespace: surreal.namespace,
      database: surreal.database,
      access: @access,
      variables: Map.merge(%{"email" => email, "password" => password}, extra)
    }
  end

  defp fetch_string!(map, key) do
    case Map.get(map, key) || Map.get(map, String.to_atom(key)) do
      value when is_binary(value) and value != "" -> value
      _ -> raise ArgumentError, "missing #{key}"
    end
  end
end
