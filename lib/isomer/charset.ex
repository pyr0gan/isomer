defmodule Isomer.Charset do
  @moduledoc "Reject non-Latin letters in content files (port of tools/check_content_charset.py)."

  alias Isomer.Paths

  @scan_dirs ~w(frameworks mappings rulesets rubrics questions templates vocab schemas)
  @suffixes ~w(.yaml .yml .md .json)
  @allowed_non_ascii MapSet.new(["—", "–", "…", "→", "←", "⟨", "⟩", "‘", "’", "“", "”", "•", "×"])

  def run(root \\ Isomer.root()) do
    root = Paths.expand_root!(root)

    errors =
      for dir <- @scan_dirs,
          base = Paths.join!(root, dir),
          File.dir?(base),
          path <- sorted_files(base, root),
          error <- scan_file(path, root),
          do: error

    Enum.each(errors, &IO.puts("ERROR #{&1}"))
    IO.puts("#{length(errors)} charset error(s)")
    if errors == [], do: :ok, else: :error
  end

  defp sorted_files(base, root) do
    Paths.wildcard!(root, Paths.relative!(base, root) <> "/**/*")
    |> Enum.filter(&(File.regular?(&1) and Path.extname(&1) in @suffixes))
  end

  defp scan_file(path, root) do
    rel = Paths.relative!(path, root)

    path
    |> File.read!()
    |> String.split(~r/\R/)
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, lineno} ->
      line
      |> String.graphemes()
      |> Enum.with_index(1)
      |> Enum.reduce_while([], fn {ch, col}, _acc ->
        if disallowed?(ch) do
          {:halt,
           [
             "#{rel}:#{lineno}:#{col}: disallowed non-Latin letter #{inspect(ch)}"
           ]}
        else
          {:cont, []}
        end
      end)
    end)
  end

  defp disallowed?(<<c::utf8>>) when c < 128, do: false

  defp disallowed?(ch) do
    cond do
      MapSet.member?(@allowed_non_ascii, ch) -> false
      String.trim(ch) == "" -> false
      Regex.match?(~r/^\p{L}$/u, ch) and not Regex.match?(~r/^\p{Latin}$/u, ch) -> true
      true -> false
    end
  end
end
