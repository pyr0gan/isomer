defmodule Isomer.Evidence.Storage do
  @moduledoc """
  Object storage for evidence binaries (roadmap slice F).

  Surreal keeps metadata (`evidence.storage_key`, `content_type`). Bytes live in
  the configured backend:

  - `memory` — ETS (tests / ephemeral)
  - `local` — filesystem under `EVIDENCE_LOCAL_ROOT`
  - `s3` — S3-compatible API (R2 / MinIO / AWS) via `EVIDENCE_S3_*`

  External `http(s)://` URLs stored as `storage_key` are not objects — callers
  must treat those as remote links (`object_key?/1`).
  """

  @type key :: String.t()
  @type body :: binary()
  @type meta :: %{optional(String.t()) => term()}

  @callback put(key(), body(), meta()) :: :ok | {:error, term()}
  @callback get(key()) :: {:ok, body(), meta()} | {:error, term()}
  @callback delete(key()) :: :ok | {:error, term()}

  @doc "Configured backend module."
  def backend do
    case Application.get_env(:isomer, __MODULE__, []) |> Keyword.get(:backend) do
      Isomer.Evidence.Storage.S3 -> Isomer.Evidence.Storage.S3
      Isomer.Evidence.Storage.Local -> Isomer.Evidence.Storage.Local
      Isomer.Evidence.Storage.Memory -> Isomer.Evidence.Storage.Memory
      "s3" -> Isomer.Evidence.Storage.S3
      "local" -> Isomer.Evidence.Storage.Local
      "memory" -> Isomer.Evidence.Storage.Memory
      :s3 -> Isomer.Evidence.Storage.S3
      :local -> Isomer.Evidence.Storage.Local
      :memory -> Isomer.Evidence.Storage.Memory
      _ -> default_backend()
    end
  end

  defp default_backend do
    cond do
      s3_configured?() -> Isomer.Evidence.Storage.S3
      local_configured?() -> Isomer.Evidence.Storage.Local
      true -> Isomer.Evidence.Storage.Memory
    end
  end

  defp s3_configured? do
    bucket = System.get_env("EVIDENCE_S3_BUCKET")
    key = System.get_env("EVIDENCE_S3_ACCESS_KEY_ID")
    secret = System.get_env("EVIDENCE_S3_SECRET_ACCESS_KEY")
    present?(bucket) and present?(key) and present?(secret)
  end

  defp local_configured? do
    present?(System.get_env("EVIDENCE_LOCAL_ROOT"))
  end

  defp present?(v) when is_binary(v), do: String.trim(v) != ""
  defp present?(_), do: false

  @doc "True when uploads to object storage are available (not URL-only metadata)."
  def uploads_enabled?,
    do:
      backend() in [
        Isomer.Evidence.Storage.S3,
        Isomer.Evidence.Storage.Local,
        Isomer.Evidence.Storage.Memory
      ]

  def put(key, body, meta \\ %{}) when is_binary(key) and is_binary(body) do
    backend().put(key, body, stringify_meta(meta))
  end

  def get(key) when is_binary(key), do: backend().get(key)

  def delete(key) when is_binary(key), do: backend().delete(key)

  @doc "True when `storage_key` is an object key (not an external URL)."
  def object_key?(key) when is_binary(key) do
    key = String.trim(key)

    key != "" and not String.starts_with?(key, "http://") and
      not String.starts_with?(key, "https://")
  end

  def object_key?(_), do: false

  @doc """
  Builds a stable object key under org/assessment/evidence.

  `evidence_key` should be the Surreal record key (without `evidence:`).
  """
  def build_key(org_id, assessment_id, evidence_key)
      when is_binary(org_id) and is_binary(assessment_id) and is_binary(evidence_key) do
    org = sanitize_segment(org_id)
    assessment = sanitize_segment(assessment_id)
    evidence = sanitize_segment(evidence_key)
    "org/#{org}/assessment/#{assessment}/evidence/#{evidence}"
  end

  defp sanitize_segment(id) do
    id
    |> to_string()
    |> String.replace_leading("org:", "")
    |> String.replace_leading("assessment:", "")
    |> String.replace_leading("evidence:", "")
    |> String.replace(~r/[^A-Za-z0-9._-]+/, "_")
  end

  defp stringify_meta(meta) when is_map(meta) do
    Map.new(meta, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} -> {to_string(k), v}
    end)
  end
end
