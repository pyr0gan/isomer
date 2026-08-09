defmodule Isomer.Vault.Secrets do
  @moduledoc "HashiCorp Vault KV reader (token or AppRole) with retries."

  def get_surreal_password!(vault), do: read_secret_field!(vault)

  def read_secret_field!(vault) do
    token = resolve_token!(vault)
    json = vault_fetch!(vault.addr, vault.path, token: token)

    version =
      cond do
        is_binary(vault.kv_version) -> String.to_integer(vault.kv_version)
        match?(%{"data" => %{"data" => data}} when is_map(data), json) -> 2
        true -> 1
      end

    data =
      case version do
        2 -> get_in(json, ["data", "data"])
        1 -> json["data"]
      end

    unless is_map(data) do
      raise "Vault secret at #{vault.path} has unexpected shape (KV v1 vs v2 path?)"
    end

    case data[vault.field] do
      nil -> raise "Vault secret at #{vault.path} is missing field \"#{vault.field}\""
      "" -> raise "Vault secret at #{vault.path} is missing field \"#{vault.field}\""
      value -> to_string(value)
    end
  end

  def resolve_token!(%{token: token}) when is_binary(token) and token != "", do: token

  def resolve_token!(%{addr: addr, role_id: role_id, secret_id: secret_id}) do
    json =
      vault_fetch!(addr, "auth/approle/login",
        method: :post,
        body: %{role_id: role_id, secret_id: secret_id}
      )

    case get_in(json, ["auth", "client_token"]) do
      nil -> raise "Vault AppRole login succeeded but no client_token returned"
      token -> token
    end
  end

  defp vault_fetch!(addr, path, opts) do
    method = Keyword.get(opts, :method, :get)
    token = Keyword.get(opts, :token)
    body = Keyword.get(opts, :body)
    url = "#{addr}/v1/#{normalize_path(path)}"

    headers =
      [{"content-type", "application/json"}] ++
        if(token, do: [{"x-vault-token", token}], else: [])

    attempt_fetch(url, method, headers, body, path, 1)
  end

  defp attempt_fetch(url, method, headers, body, path, attempt) do
    req =
      Req.new(url: url, headers: headers)
      |> then(fn r ->
        if body, do: Req.merge(r, json: body), else: r
      end)

    case Req.request(req, method: method) do
      {:ok, %{status: status, body: resp}} when status >= 200 and status < 300 ->
        decode_body(resp)

      {:ok, %{status: status, body: resp}} ->
        msg =
          case decode_body(resp) do
            %{"errors" => errs} when is_list(errs) -> Enum.join(errs, "; ")
            %{"error" => e} -> to_string(e)
            other -> inspect(other)
          end

        raise "Vault #{method} #{path} failed (#{status}): #{msg}"

      {:error, err} ->
        if attempt < 3 and transient?(err) do
          Process.sleep(400 * attempt)
          attempt_fetch(url, method, headers, body, path, attempt + 1)
        else
          raise "fetch failed talking to Vault at #{url} — #{Exception.message(err)}"
        end
    end
  end

  defp decode_body(body) when is_map(body), do: body

  defp decode_body(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, json} -> json
      _ -> %{"raw" => body}
    end
  end

  defp transient?(%Req.TransportError{}), do: true
  defp transient?(%Mint.TransportError{}), do: true
  defp transient?(_), do: true

  defp normalize_path(path) do
    path
    |> to_string()
    |> String.trim()
    |> String.trim_leading("/")
    |> String.replace_prefix("v1/", "")
  end
end
