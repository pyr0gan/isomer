defmodule Isomer.Evidence.Storage.Memory do
  @moduledoc false

  @behaviour Isomer.Evidence.Storage

  @table :isomer_evidence_blobs

  @impl true
  def put(key, body, meta) do
    ensure_table!()
    true = :ets.insert(@table, {key, body, meta})
    :ok
  end

  @impl true
  def get(key) do
    ensure_table!()

    case :ets.lookup(@table, key) do
      [{^key, body, meta}] -> {:ok, body, meta}
      [] -> {:error, :not_found}
    end
  end

  @impl true
  def delete(key) do
    ensure_table!()
    :ets.delete(@table, key)
    :ok
  end

  @doc false
  def reset! do
    ensure_table!()
    :ets.delete_all_objects(@table)
    :ok
  end

  defp ensure_table! do
    case :ets.whereis(@table) do
      :undefined ->
        :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])

      _tid ->
        @table
    end
  end
end
