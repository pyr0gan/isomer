defmodule Isomer.Domains do
  @moduledoc "Maturity domain catalog from `vocab/domains.yaml`."

  alias Isomer.YAML

  @doc "All domain defs as maps with string keys (`id`, `name`, `description`, …)."
  def catalog do
    path = Path.join(Isomer.root(), "vocab/domains.yaml")

    if File.exists?(path) do
      path
      |> YAML.read!()
      |> Map.get("domains", [])
      |> Enum.map(&normalize_domain/1)
    else
      []
    end
  end

  @doc "Catalog entries that have a published question set (by domain id)."
  def selectable(question_set_domain_ids) when is_list(question_set_domain_ids) do
    available = MapSet.new(question_set_domain_ids)

    catalog()
    |> Enum.filter(&MapSet.member?(available, &1["id"]))
  end

  @doc """
  Sentence-case label for display.

  Preserves short all-caps tokens (AI, ISO) and ampersands; lowercases the rest
  after the first word.
  """
  def sentence_case(name) when is_binary(name) do
    name
    |> String.split(~r/\s+/, trim: true)
    |> Enum.with_index()
    |> Enum.map(fn {word, index} ->
      cond do
        word in ["&", "/"] -> word
        acronym?(word) -> word
        index == 0 -> capitalize_word(word)
        true -> String.downcase(word)
      end
    end)
    |> Enum.join(" ")
  end

  def sentence_case(_), do: ""

  defp normalize_domain(domain) when is_map(domain) do
    desc =
      domain
      |> Map.get("description", "")
      |> to_string()
      |> String.replace(~r/\s+/, " ")
      |> String.trim()

    domain
    |> Map.put("description", desc)
    |> Map.put("label", sentence_case(Map.get(domain, "name") || Map.get(domain, "id") || ""))
  end

  defp acronym?(word) do
    String.match?(word, ~r"^[A-Z0-9]{2,}[A-Z0-9+./-]*$")
  end

  defp capitalize_word(word) do
    case String.downcase(word) do
      <<first::utf8, rest::binary>> ->
        String.upcase(<<first::utf8>>) <> rest

      other ->
        other
    end
  end
end
