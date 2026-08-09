defmodule Isomer.Db.UserClient do
  @moduledoc """
  Per-user SurrealDB connection using `ACCESS isomer_user` JWT.

  Root/`Isomer.Db.Connect` stays Mix-only. The web app never holds the Surreal root password.
  """

  alias Isomer.Config
  alias SurrealDB.Auth

  @access "isomer_user"

  def start_link(opts \\ []) do
    surreal = Config.surreal!()

    SurrealDB.start_link(
      url: Keyword.get(opts, :url, surreal.url),
      namespace: Keyword.get(opts, :namespace, surreal.namespace),
      database: Keyword.get(opts, :database, surreal.database)
    )
  end

  @doc "Open an anonymous connection and authenticate with an existing JWT."
  def connect_with_token(token) when is_binary(token) do
    with {:ok, conn} <- start_link(),
         {:ok, _} <- SurrealDB.authenticate(conn, token) do
      {:ok, conn}
    else
      {:error, reason} -> {:error, reason}
    end
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

  defp auth_flow(kind, email, password, extra) do
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
  end

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
