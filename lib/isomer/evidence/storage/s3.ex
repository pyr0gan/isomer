defmodule Isomer.Evidence.Storage.S3 do
  @moduledoc false

  @behaviour Isomer.Evidence.Storage

  @impl true
  def put(key, body, meta) do
    content_type =
      Map.get(meta, "content_type") || Map.get(meta, :content_type) || "application/octet-stream"

    headers = [{"content-type", content_type}]

    case request("PUT", key, body, headers) do
      {:ok, %{status: status}} when status in 200..299 -> :ok
      {:ok, %{status: status, body: resp}} -> {:error, {:http, status, resp}}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def get(key) do
    case request("GET", key, "", []) do
      {:ok, %{status: 200, body: body, headers: headers}} ->
        content_type =
          headers
          |> Map.new(fn {k, v} -> {String.downcase(to_string(k)), to_string(v)} end)
          |> Map.get("content-type", "application/octet-stream")

        {:ok, body, %{"content_type" => content_type}}

      {:ok, %{status: 404}} ->
        {:error, :not_found}

      {:ok, %{status: status, body: resp}} ->
        {:error, {:http, status, resp}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def delete(key) do
    case request("DELETE", key, "", []) do
      {:ok, %{status: status}} when status in 200..299 or status == 404 -> :ok
      {:ok, %{status: status, body: resp}} -> {:error, {:http, status, resp}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp request(method, key, body, extra_headers) do
    cfg = config!()
    url = object_url(cfg, key)
    now = :calendar.universal_time()

    base_headers =
      [
        {"host", host_header(cfg)},
        {"x-amz-content-sha256", hash_hex(body)}
      ] ++ extra_headers

    header_binaries =
      Enum.map(base_headers, fn {k, v} ->
        {String.downcase(to_string(k)) |> then(& &1), to_string(v)}
      end)
      |> Enum.map(fn {k, v} -> {k, v} end)

    # aws_signature expects binary keys/values.
    signed =
      :aws_signature.sign_v4(
        cfg.access_key_id,
        cfg.secret_access_key,
        cfg.region,
        "s3",
        now,
        method,
        url,
        Enum.map(header_binaries, fn {k, v} -> {k, v} end),
        body
      )

    headers =
      Enum.map(signed, fn {k, v} ->
        {to_string(k), to_string(v)}
      end)

    opts = [url: url, headers: headers, receive_timeout: 60_000]

    case method do
      "PUT" -> Req.put(opts ++ [body: body])
      "GET" -> Req.get(opts)
      "DELETE" -> Req.delete(opts)
    end
  end

  defp config! do
    bucket = env!("EVIDENCE_S3_BUCKET")
    access_key_id = env!("EVIDENCE_S3_ACCESS_KEY_ID")
    secret_access_key = env!("EVIDENCE_S3_SECRET_ACCESS_KEY")
    region = System.get_env("EVIDENCE_S3_REGION") || "auto"
    endpoint = System.get_env("EVIDENCE_S3_ENDPOINT")
    force_path = truthy?(System.get_env("EVIDENCE_S3_FORCE_PATH_STYLE"))

    %{
      bucket: bucket,
      access_key_id: access_key_id,
      secret_access_key: secret_access_key,
      region: region,
      endpoint: endpoint,
      force_path_style: force_path or is_binary(endpoint)
    }
  end

  defp env!(name) do
    case System.get_env(name) do
      value when is_binary(value) and value != "" -> value
      _ -> raise ArgumentError, "#{name} is required for S3 evidence storage"
    end
  end

  defp object_url(cfg, key) do
    key = String.trim_leading(key, "/")

    cond do
      is_binary(cfg.endpoint) and cfg.endpoint != "" and cfg.force_path_style ->
        base = String.trim_trailing(cfg.endpoint, "/")
        "#{base}/#{cfg.bucket}/#{key}"

      is_binary(cfg.endpoint) and cfg.endpoint != "" ->
        uri = URI.parse(cfg.endpoint)
        host = "#{cfg.bucket}.#{uri.host}"
        port = if uri.port in [80, 443, nil], do: "", else: ":#{uri.port}"
        "#{uri.scheme}://#{host}#{port}/#{key}"

      true ->
        "https://#{cfg.bucket}.s3.#{cfg.region}.amazonaws.com/#{key}"
    end
  end

  defp host_header(cfg) do
    url = object_url(cfg, "x")
    uri = URI.parse(url)
    if uri.port in [80, 443, nil], do: uri.host, else: "#{uri.host}:#{uri.port}"
  end

  defp hash_hex(body) do
    :crypto.hash(:sha256, body) |> Base.encode16(case: :lower)
  end

  defp truthy?(v) when v in ["1", "true", "TRUE", "yes", "on"], do: true
  defp truthy?(_), do: false
end
