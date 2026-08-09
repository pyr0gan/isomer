defmodule Isomer.Namegen do
  @moduledoc """
  Human-readable ids in the form `shortword-shortword-xxxxxx`
  (two short words plus 6 alphanumeric characters).
  """

  @words ~w(
    amber anchor apple arctic ash autumn birch blade bloom breeze brook
    cedar clear cliff cloud cobalt comet copper coral craft creek crisp
    delta dune ember fern field flint flora frost glacier grain grove
    harbor hazel heath honey ivory jade kelp lake lava lemon lodge
    maple meadow mercury mist moss nebula north nova oak ocean olive
    orchard pebble pine plume pond quartz rain raven ridge river
    sable sapphire scarlet shadow sierra silver sky slate snow spruce
    stone storm summit tide timber trail valley vapor violet willow
    winter zenith
  )

  @alnum ~c"abcdefghijklmnopqrstuvwxyz0123456789"

  @doc "Generate a name like `harbor-maple-a3k9xm`."
  def generate do
    w1 = Enum.random(@words)
    w2 = Enum.random(@words) |> distinct_from(w1)
    "#{w1}-#{w2}-#{suffix(6)}"
  end

  @doc "True when the string matches `word-word-xxxxxx` (lowercase)."
  def valid?(name) when is_binary(name) do
    Regex.match?(~r/^[a-z]+-[a-z]+-[a-z0-9]{6}$/, name)
  end

  def valid?(_), do: false

  defp distinct_from(word, other) do
    if word == other, do: Enum.random(@words -- [other]), else: word
  end

  defp suffix(n) do
    1..n
    |> Enum.map(fn _ -> Enum.random(@alnum) end)
    |> List.to_string()
  end
end
