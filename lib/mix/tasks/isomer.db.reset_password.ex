defmodule Mix.Tasks.Isomer.Db.ResetPassword do
  @shortdoc "Reset a Surreal record-user password (root/Vault; Mix-only)"
  @moduledoc """
  Updates `user.password` with a fresh argon2 hash. Intended for demo/admin
  recovery when signup is blocked by a unique email and the password is unknown.

      mix isomer.db.reset_password --email you@example.com --password 'new-secret'

  Does not print the password. Requires Vault-backed Surreal root credentials
  (same as `mix isomer.db.ping`).
  """

  use Mix.Task

  @switches [email: :string, password: :string]
  @aliases [e: :email, p: :password]

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _, _} = OptionParser.parse(args, switches: @switches, aliases: @aliases)
    email = opts[:email] || System.get_env("RESET_EMAIL")
    password = opts[:password] || System.get_env("RESET_PASSWORD")

    cond do
      not is_binary(email) or email == "" ->
        Mix.shell().error("Missing --email (or RESET_EMAIL)")
        exit({:shutdown, 1})

      not is_binary(password) or password == "" ->
        Mix.shell().error("Missing --password (or RESET_PASSWORD)")
        exit({:shutdown, 1})

      String.length(password) < 8 ->
        Mix.shell().error("Password must be at least 8 characters")
        exit({:shutdown, 1})

      true ->
        reset!(email, password)
    end
  end

  defp reset!(email, password) do
    db = Isomer.Db.Connect.connect!()

    try do
      {:ok, result} =
        SurrealDB.query(
          db,
          """
          UPDATE user SET password = crypto::argon2::generate($password)
            WHERE email = $email
            RETURN AFTER;
          """,
          %{"email" => email, "password" => password}
        )

      rows = result |> List.wrap() |> List.flatten()

      case rows do
        [%{"email" => ^email} | _] ->
          Mix.shell().info("db:reset_password OK")

          Mix.shell().info(
            Isomer.JSON.encode!(%{ok: true, email: email, updated: 1}, pretty: true)
          )

        [] ->
          Mix.shell().error("No user found for email=#{email}")
          exit({:shutdown, 1})

        other ->
          Mix.shell().error("Unexpected result: #{inspect(other)}")
          exit({:shutdown, 1})
      end
    after
      SurrealDB.close(db)
    end
  rescue
    e ->
      Mix.shell().error("db:reset_password FAILED")
      Mix.shell().error(Exception.message(e))
      exit({:shutdown, 1})
  end
end
