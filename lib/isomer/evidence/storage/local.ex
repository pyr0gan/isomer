defmodule Isomer.Evidence.Storage.Local do
  @moduledoc false

  @behaviour Isomer.Evidence.Storage

  @impl true
  def put(key, body, meta) do
    path = path_for(key)

    with :ok <- File.mkdir_p(Path.dirname(path)),
         :ok <- File.write(path, body),
         :ok <- File.write(path <> ".meta.json", Jason.encode!(meta)) do
      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def get(key) do
    path = path_for(key)

    case File.read(path) do
      {:ok, body} ->
        meta =
          case File.read(path <> ".meta.json") do
            {:ok, json} ->
              case Jason.decode(json) do
                {:ok, map} when is_map(map) -> map
                _ -> %{}
              end

            _ ->
              %{}
          end

        {:ok, body, meta}

      {:error, :enoent} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def delete(key) do
    path = path_for(key)
    _ = File.rm(path)
    _ = File.rm(path <> ".meta.json")
    :ok
  end

  defp path_for(key) do
    root =
      System.get_env("EVIDENCE_LOCAL_ROOT") ||
        Application.get_env(:isomer, Isomer.Evidence.Storage, [])
        |> Keyword.get(:local_root) ||
        Path.join(System.tmp_dir!(), "isomer-evidence")

    # Prevent path escape: only allow relative key segments.
    safe =
      key
      |> String.split("/", trim: true)
      |> Enum.reject(&(&1 in [".", ".."]))
      |> Path.join()

    Path.join(root, safe)
  end
end
