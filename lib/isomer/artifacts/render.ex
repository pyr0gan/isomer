defmodule Isomer.Artifacts.Render do
  @moduledoc """
  Renders corpus templates by substituting `{{merge.field}}` placeholders.

  Unknown or blank fields become an em-dash placeholder so drafts stay readable.
  """

  @placeholder "—"

  @doc """
  Renders `body` with `values` keyed by dotted merge-field paths
  (e.g. `%{"org.name" => "Acme"}`).
  """
  def render(body, values) when is_binary(body) and is_map(values) do
    Regex.replace(~r/\{\{\s*([a-zA-Z0-9_.]+)\s*\}\}/, body, fn _full, path ->
      case Map.get(values, path) do
        nil -> @placeholder
        "" -> @placeholder
        value -> value |> to_string() |> String.trim() |> empty_to_placeholder()
      end
    end)
  end

  @doc "Lists unique `{{field}}` paths in document order."
  def extract_fields(body) when is_binary(body) do
    Regex.scan(~r/\{\{\s*([a-zA-Z0-9_.]+)\s*\}\}/, body)
    |> Enum.map(fn [_, path] -> path end)
    |> Enum.uniq()
  end

  @doc """
  Builds a merge-value map from org + assessment + optional overrides.

  `overrides` wins. Known keys are prefilled when present on org/assessment.
  """
  def build_values(org, assessment, overrides \\ %{})
      when is_map(org) and is_map(assessment) and is_map(overrides) do
    today = Date.utc_today() |> Date.to_iso8601()

    base = %{
      "org.name" => Map.get(org, "name") || "",
      "assessment.date" => today,
      "assessment.assessor" => "",
      "register.last_updated" => today,
      "policy.effective_date" => today,
      "soa.approval_date" => today
    }

    overrides =
      overrides
      |> Enum.map(fn {k, v} -> {to_string(k), blank_to_empty(v)} end)
      |> Map.new()

    Map.merge(base, overrides)
  end

  @doc "Filename-safe stem from a template name or id."
  def filename_stem(name) when is_binary(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
    |> case do
      "" -> "artifact"
      stem -> stem
    end
  end

  @doc "Very small Markdown→HTML for print/PDF download (headings, bold, paragraphs)."
  def to_printable_html(markdown, title \\ "Artifact", opts \\ [])
      when is_binary(markdown) and is_binary(title) and is_list(opts) do
    body =
      markdown
      |> String.split(~r/\R{2,}/, trim: true)
      |> Enum.map_join("\n", &block_to_html/1)

    autoprint =
      if Keyword.get(opts, :autoprint, false) do
        "<script>window.addEventListener(\"load\", function () { window.print(); });</script>"
      else
        ""
      end

    """
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="utf-8" />
      <title>#{html_escape(title)}</title>
      <style>
        @page { margin: 2cm; }
        body {
          font-family: "PT Sans", "Segoe UI", sans-serif;
          line-height: 1.5;
          color: #0f172a;
          max-width: 48rem;
          margin: 2rem auto;
          padding: 0 1.25rem;
        }
        h1 { font-size: 1.75rem; margin: 0 0 1rem; }
        h2 { font-size: 1.25rem; margin: 1.75rem 0 0.5rem; }
        h3 { font-size: 1.1rem; margin: 1.25rem 0 0.4rem; }
        p, li { font-size: 1rem; }
        ul { padding-left: 1.25rem; }
        strong { font-weight: 600; }
        .meta { color: #64748b; font-size: 0.9rem; margin-bottom: 1.5rem; }
        @media print {
          body { margin: 0; max-width: none; }
          .no-print { display: none !important; }
        }
      </style>
    </head>
    <body>
      <p class="meta no-print">Use your browser’s Print → Save as PDF for a PDF copy.</p>
      #{body}
      #{autoprint}
    </body>
    </html>
    """
  end

  defp block_to_html(block) do
    cond do
      String.starts_with?(block, "# ") ->
        "<h1>#{inline(String.trim_leading(block, "# "))}</h1>"

      String.starts_with?(block, "## ") ->
        "<h2>#{inline(String.trim_leading(block, "## "))}</h2>"

      String.starts_with?(block, "### ") ->
        "<h3>#{inline(String.trim_leading(block, "### "))}</h3>"

      String.starts_with?(block, "- ") or String.starts_with?(block, "* ") ->
        items =
          block
          |> String.split(~r/\R/, trim: true)
          |> Enum.map(fn
            <<"- ", rest::binary>> -> "<li>#{inline(rest)}</li>"
            <<"* ", rest::binary>> -> "<li>#{inline(rest)}</li>"
            line -> "<li>#{inline(line)}</li>"
          end)
          |> Enum.join()

        "<ul>#{items}</ul>"

      true ->
        "<p>#{inline(block)}</p>"
    end
  end

  defp inline(text) do
    text
    |> html_escape()
    |> String.replace(~r/\*\*(.+?)\*\*/, "<strong>\\1</strong>")
    |> String.replace("\n", "<br />\n")
  end

  defp html_escape(text) do
    text
    |> to_string()
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end

  defp empty_to_placeholder(""), do: @placeholder
  defp empty_to_placeholder(value), do: value

  defp blank_to_empty(nil), do: ""
  defp blank_to_empty(value), do: to_string(value)
end
