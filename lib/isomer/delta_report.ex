defmodule Isomer.DeltaReport do
  @moduledoc "Integration delta report (port of tools/delta_report.py)."

  alias Isomer.Paths
  alias Isomer.YAML

  @rank %{
    "satisfied_by" => 3,
    "partially_satisfied_by" => 2,
    "supports" => 1,
    "related" => 1
  }

  @label %{3 => :covered, 2 => :partial, 1 => :adjacent, 0 => :net_new}

  def run(map_path, root \\ Isomer.root()) do
    root = Paths.expand_root!(root)
    map_path = Paths.expand_under!(root, map_path)
    ms = YAML.read!(map_path)
    from_fw = ms["from_framework"]
    [fw, ver] = String.split(from_fw, "/", parts: 2)
    fw = Paths.segment!(fw)
    ver = Paths.segment!(ver)

    reqs =
      root
      |> Paths.wildcard!("frameworks/#{fw}/#{ver}/requirements/*.yaml")
      |> Map.new(fn p ->
        d = YAML.read!(p)
        {d["id"], d["title"]}
      end)

    best = Map.new(reqs, fn {rid, _} -> {rid, 0} end)
    notes = Map.new(reqs, fn {rid, _} -> {rid, []} end)

    {best, notes} =
      Enum.reduce(ms["mappings"] || [], {best, notes}, fn m, {b, n} ->
        rid = m["from"]

        if Map.has_key?(b, rid) do
          r = Map.get(@rank, m["relation"], 0)
          b = Map.update!(b, rid, &max(&1, r))

          n =
            if m["relation"] == "partially_satisfied_by" and is_binary(m["note"]) do
              note =
                m["note"]
                |> String.trim()
                |> String.replace("\n", " ")

              Map.update!(n, rid, &[note | &1])
            else
              n
            end

          {b, n}
        else
          {b, n}
        end
      end)

    buckets = %{covered: [], partial: [], adjacent: [], net_new: []}

    buckets =
      Enum.reduce(reqs, buckets, fn {rid, title}, acc ->
        label = Map.fetch!(@label, Map.fetch!(best, rid))
        Map.update!(acc, label, &[{rid, title} | &1])
      end)

    buckets = Map.new(buckets, fn {k, v} -> {k, Enum.reverse(v)} end)

    IO.puts("Integration delta: #{from_fw} against #{ms["to_framework"]}")

    IO.puts(
      "#{map_size(reqs)} requirements: " <>
        Enum.map_join([:covered, :partial, :adjacent, :net_new], ", ", fn k ->
          "#{k}=#{length(buckets[k])}"
        end)
    )

    IO.puts("")

    for bucket <- [:net_new, :partial, :adjacent, :covered],
        rows = buckets[bucket],
        rows != [] do
      IO.puts("== #{bucket} (#{length(rows)}) ==")

      for {rid, title} <- rows do
        ref = rid |> String.split("/") |> List.last()
        IO.puts("  #{String.pad_leading(ref, 8)}  #{title}")

        if bucket == :partial do
          for n <- Enum.reverse(notes[rid]) do
            gap =
              if String.contains?(n, "Gap:") do
                n
                |> String.split("Gap:")
                |> List.last()
                |> String.trim()
                |> String.trim_trailing(".")
              else
                n
              end

            IO.puts("            gap: #{gap}")
          end
        end
      end

      IO.puts("")
    end

    :ok
  end
end
