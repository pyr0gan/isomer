defmodule Isomer.OrgMetrics do
  @moduledoc """
  Org-level assessment metric series for the maturity dashboard.

  An assessment contributes once at least one domain is opted in via
  `assessment.domain_metrics[domain].collect`. Yes %, unanswered, and evidence
  coverage are scored across **all** domains on that assessment; time scale /
  hours are opt-in domains only. Sparklines need at least two assessment
  points; otherwise the UI shows "data req'd".
  """

  alias Isomer.Domains
  alias Isomer.Db.Tenant

  @time_scale_rank %{"low" => 1, "medium" => 2, "high" => 3}

  @doc """
  Builds the metrics panel payload for an org.

  Returns `{:ok, map}` with string keys:
  - `has_collection` — any opted-in domain across assessments
  - `current` — latest snapshot (`yes_pct`, `unanswered`, `evidence_pct`, `domains`)
  - `series` — chronological points for sparklines (`yes_pct`, `unanswered`,
    `evidence_pct`, `time_hours`)
  """
  def org_panel(conn, assessments) when is_list(assessments) do
    with {:ok, sets} <- Tenant.list_question_sets(conn) do
      catalog = Domains.catalog()
      question_index = question_index(sets)

      # Chronological for series (oldest → newest); list_assessments is DESC.
      chronological = Enum.reverse(assessments)

      snapshots =
        chronological
        |> Enum.map(fn assessment ->
          snapshot_for(conn, assessment, question_index, catalog)
        end)
        |> Enum.reject(&is_nil/1)

      current = List.last(snapshots)

      {:ok,
       %{
         "has_collection" => snapshots != [],
         "current" => current,
         "series" => %{
           "yes_pct" => Enum.map(snapshots, & &1["yes_pct"]),
           "unanswered" => Enum.map(snapshots, & &1["unanswered"]),
           "evidence_pct" => Enum.map(snapshots, & &1["evidence_pct"]),
           "time_hours" => Enum.map(snapshots, & &1["time_hours_total"])
         }
       }}
    end
  end

  @doc "True when a sparkline series has enough points to draw."
  def sparkline_ready?(series) when is_list(series),
    do: length(Enum.reject(series, &is_nil/1)) >= 2

  def sparkline_ready?(_), do: false

  @doc """
  SVG polyline points for a numeric series (nil skipped). Returns `nil` when
  fewer than two finite values.
  """
  def sparkline_points(series, width \\ 120, height \\ 28) when is_list(series) do
    values =
      series
      |> Enum.with_index()
      |> Enum.flat_map(fn
        {v, i} when is_number(v) -> [{i, v * 1.0}]
        _ -> []
      end)

    if length(values) < 2 do
      nil
    else
      xs = Enum.map(values, &elem(&1, 0))
      ys = Enum.map(values, &elem(&1, 1))
      min_x = Enum.min(xs)
      max_x = Enum.max(xs)
      min_y = Enum.min(ys)
      max_y = Enum.max(ys)
      span_x = max(max_x - min_x, 1)
      span_y = max(max_y - min_y, 1.0)
      pad = 2

      values
      |> Enum.map(fn {x, y} ->
        px = pad + (x - min_x) / span_x * (width - 2 * pad)
        # Invert y so higher values sit toward the top.
        py = height - pad - (y - min_y) / span_y * (height - 2 * pad)
        "#{Float.round(px, 1)},#{Float.round(py, 1)}"
      end)
      |> Enum.join(" ")
    end
  end

  defp snapshot_for(conn, assessment, question_index, catalog) do
    metrics = normalize_metrics(assessment["domain_metrics"])
    collecting = collecting_domains(metrics)
    assessment_domains = assessment["domains"] || []

    if collecting == [] do
      nil
    else
      id = Tenant.canonicalize_record_id(assessment["id"])

      {answers, notes} =
        case Tenant.list_answers(conn, id) do
          {:ok, rows} -> unpack_answers(rows)
          {:error, _} -> {%{}, %{}}
        end

      # Yes % / unanswered / evidence use every domain on the assessment;
      # time rows stay opt-in only.
      score_domains =
        assessment_domains
        |> Enum.map(&to_string/1)
        |> Enum.reject(&(&1 == ""))
        |> Enum.uniq()

      score_domains = if score_domains == [], do: collecting, else: score_domains

      questions =
        score_domains
        |> Enum.flat_map(fn domain_id -> Map.get(question_index, domain_id, []) end)

      stats = score_questions(questions, answers, notes)
      domain_rows = domain_time_rows(collecting, metrics, catalog)

      %{
        "assessment_id" => id,
        "title" => assessment["title"],
        "status" => assessment["status"],
        "yes_pct" => stats.yes_pct,
        "unanswered" => stats.unanswered,
        "evidence_pct" => stats.evidence_pct,
        "time_hours_total" =>
          Enum.reduce(domain_rows, 0.0, fn row, acc -> acc + (row["hours"] || 0) end),
        "domains" => domain_rows
      }
    end
  end

  defp question_index(sets) do
    Enum.reduce(sets, %{}, fn set, acc ->
      domain = set["domain"]

      if is_binary(domain) do
        qs =
          Enum.map(set["questions"] || [], fn q ->
            %{
              id: q["id"],
              kind: q["kind"] || "text",
              evidence_prompt: q["evidence_prompt"],
              domain: domain
            }
          end)

        Map.put(acc, domain, qs)
      else
        acc
      end
    end)
  end

  defp normalize_metrics(metrics) when is_map(metrics) and not is_struct(metrics), do: metrics
  defp normalize_metrics(_), do: %{}

  defp collecting_domains(metrics) do
    metrics
    |> Enum.filter(fn {_domain, entry} ->
      is_map(entry) and truthy?(Map.get(entry, "collect"))
    end)
    |> Enum.map(fn {domain, _} -> to_string(domain) end)
    |> Enum.sort()
  end

  defp unpack_answers(rows) do
    Enum.reduce(rows, {%{}, %{}}, fn row, {vals, notes} ->
      qid = row["question_id"]

      if is_binary(qid) do
        {value, note} = unpack_value(row["value"])
        {Map.put(vals, qid, value), Map.put(notes, qid, note)}
      else
        {vals, notes}
      end
    end)
  end

  defp unpack_value(%{"v" => value} = map) when is_map(map) do
    {value, map |> Map.get("evidence", "") |> to_string()}
  end

  defp unpack_value(value), do: {value, ""}

  defp score_questions(questions, answers, notes) do
    total = length(questions)

    {yes, unanswered, evidence_needed, evidence_have} =
      Enum.reduce(questions, {0, 0, 0, 0}, fn q, {y, u, en, eh} ->
        bucket = answer_bucket(q.kind, Map.get(answers, q.id, :missing))
        y = if bucket == :yes, do: y + 1, else: y
        u = if bucket == :unanswered, do: u + 1, else: u

        {en, eh} =
          if present?(q.evidence_prompt) do
            note = Map.get(notes, q.id, "")
            {en + 1, if(present?(note), do: eh + 1, else: eh)}
          else
            {en, eh}
          end

        {y, u, en, eh}
      end)

    yes_pct =
      if total > 0 do
        round(100 * yes / total)
      else
        nil
      end

    evidence_pct =
      if evidence_needed > 0 do
        round(100 * evidence_have / evidence_needed)
      else
        nil
      end

    %{
      yes_pct: yes_pct,
      unanswered: unanswered,
      evidence_pct: evidence_pct
    }
  end

  defp domain_time_rows(domains, metrics, catalog) do
    label_index = Map.new(catalog, &{&1["id"], &1["label"] || Domains.sentence_case(&1["id"])})

    Enum.map(domains, fn domain_id ->
      entry = Map.get(metrics, domain_id) || %{}
      scale = normalize_scale(Map.get(entry, "time_scale"))
      hours = normalize_hours(Map.get(entry, "time_hours"))

      %{
        "domain" => domain_id,
        "label" => Map.get(label_index, domain_id, Domains.sentence_case(domain_id)),
        "time_scale" => scale,
        "time_scale_label" => scale_label(scale),
        "hours" => hours,
        "rank" => Map.get(@time_scale_rank, scale)
      }
    end)
  end

  defp answer_bucket("boolean", value) do
    case unwrap(value) do
      v when v in [true, "true", "yes", 1, "1"] -> :yes
      v when v in [false, "false", "no", 0, "0"] -> :no
      :missing -> :unanswered
      nil -> :unanswered
      "" -> :unanswered
      _ -> :unanswered
    end
  end

  defp answer_bucket(_kind, :missing), do: :unanswered
  defp answer_bucket(_kind, nil), do: :unanswered
  defp answer_bucket(_kind, ""), do: :unanswered
  defp answer_bucket("multi", list) when is_list(list) and list == [], do: :unanswered
  defp answer_bucket(_kind, _), do: :answered

  defp unwrap(value) when is_list(value), do: List.last(value)
  defp unwrap(value), do: value

  defp truthy?(v) when v in [true, "true", "on", "1", 1], do: true
  defp truthy?(_), do: false

  defp present?(v) when is_binary(v), do: String.trim(v) != ""
  defp present?(_), do: false

  defp normalize_scale(scale) when scale in ["low", "medium", "high"], do: scale
  defp normalize_scale(_), do: nil

  defp normalize_hours(nil), do: nil
  defp normalize_hours(n) when is_number(n) and n >= 0, do: n * 1.0

  defp normalize_hours(n) when is_binary(n) do
    case Float.parse(String.trim(n)) do
      {v, _} when v >= 0 -> v
      _ -> nil
    end
  end

  defp normalize_hours(_), do: nil

  defp scale_label("low"), do: "Low"
  defp scale_label("medium"), do: "Medium"
  defp scale_label("high"), do: "High"
  defp scale_label(_), do: "—"
end
