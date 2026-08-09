defmodule Isomer.Db.Tenant do
  @moduledoc "Surreal queries for orgs, assessments, and wizard answers (user JWT)."

  alias Isomer.Db.UserClient

  def list_orgs(conn) do
    case UserClient.query(conn, "SELECT * FROM org ORDER BY name ASC;") do
      {:ok, [rows]} when is_list(rows) -> {:ok, Enum.map(rows, &normalize_record/1)}
      {:ok, rows} when is_list(rows) -> {:ok, Enum.map(rows, &normalize_record/1)}
      {:error, reason} -> {:error, reason}
    end
  end

  def create_org(conn, name) when is_binary(name) do
    # Pre-generate the org id so RELATE does not depend on CREATE's return value.
    # Under older org PERMISSIONS (select only via member_org_ids), CREATE returns
    # NONE until the member edge exists — which broke `RELATE … -> $org`.
    sql = """
    LET $key = string::concat("o", rand::string(16));
    LET $oid = type::record("org", $key);
    CREATE $oid SET name = $name, created_by = $auth.id;
    RELATE $auth -> member -> $oid SET role = 'owner';
    RETURN SELECT * FROM ONLY $oid;
    """

    case UserClient.query(conn, sql, %{"name" => String.trim(name)}) do
      {:ok, results} ->
        case last_result(results) do
          row when is_map(row) -> {:ok, normalize_record(row)}
          [row | _] when is_map(row) -> {:ok, normalize_record(row)}
          other -> {:error, {:unexpected_create_org, other}}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  def get_org(conn, org_id) when is_binary(org_id) do
    case UserClient.query(conn, "SELECT * FROM type::record($id);", %{"id" => org_id}) do
      {:ok, [row]} when is_map(row) ->
        {:ok, normalize_record(row)}

      {:ok, [[row]]} when is_map(row) ->
        {:ok, normalize_record(row)}

      {:ok, [rows]} when is_list(rows) ->
        case rows do
          [row | _] -> {:ok, normalize_record(row)}
          [] -> {:error, :not_found}
        end

      {:ok, []} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def list_assessments(conn, org_id) when is_binary(org_id) do
    sql = """
    SELECT * FROM assessment
    WHERE org = type::record($org_id)
    ORDER BY created_at DESC;
    """

    case UserClient.query(conn, sql, %{"org_id" => org_id}) do
      {:ok, [rows]} when is_list(rows) -> {:ok, Enum.map(rows, &normalize_record/1)}
      {:ok, rows} when is_list(rows) -> {:ok, Enum.map(rows, &normalize_record/1)}
      {:error, reason} -> {:error, reason}
    end
  end

  def create_assessment(conn, org_id, attrs) when is_binary(org_id) and is_map(attrs) do
    title = Map.fetch!(attrs, "title") |> String.trim()
    kind = Map.get(attrs, "kind", "domains")
    domains = Map.get(attrs, "domains") || []
    ruleset_id = Map.get(attrs, "ruleset_id")

    # Surreal option<string> rejects JSON null — omit the field when unset.
    {ruleset_sql, vars} =
      if is_binary(ruleset_id) and ruleset_id != "" do
        {"ruleset_id = $ruleset_id,",
         %{
           "org_id" => org_id,
           "title" => title,
           "kind" => kind,
           "domains" => domains,
           "ruleset_id" => ruleset_id
         }}
      else
        {"",
         %{
           "org_id" => org_id,
           "title" => title,
           "kind" => kind,
           "domains" => domains
         }}
      end

    sql = """
    CREATE ONLY assessment SET
      org = type::record($org_id),
      title = $title,
      kind = $kind,
      domains = $domains,
      #{ruleset_sql}
      status = 'draft',
      created_by = $auth.id,
      updated_at = time::now();
    """

    case UserClient.query(conn, sql, vars) do
      {:ok, [row]} when is_map(row) ->
        {:ok, normalize_record(row)}

      {:ok, [[row]]} when is_map(row) ->
        {:ok, normalize_record(row)}

      {:ok, [rows]} when is_list(rows) ->
        case rows do
          [row | _] -> {:ok, normalize_record(row)}
          other -> {:error, {:unexpected_create_assessment, other}}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  def get_assessment(conn, assessment_id) when is_binary(assessment_id) do
    case UserClient.query(conn, "SELECT * FROM type::record($id);", %{"id" => assessment_id}) do
      {:ok, [row]} when is_map(row) ->
        {:ok, normalize_record(row)}

      {:ok, [[row]]} when is_map(row) ->
        {:ok, normalize_record(row)}

      {:ok, [rows]} when is_list(rows) ->
        case rows do
          [row | _] -> {:ok, normalize_record(row)}
          [] -> {:error, :not_found}
        end

      {:ok, []} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def list_question_sets(conn) do
    case UserClient.query(
           conn,
           "SELECT corpus_id, title, domain, questions FROM question_set ORDER BY domain ASC;"
         ) do
      {:ok, [rows]} when is_list(rows) -> {:ok, rows}
      {:ok, rows} when is_list(rows) -> {:ok, rows}
      {:error, reason} -> {:error, reason}
    end
  end

  def list_answers(conn, assessment_id) when is_binary(assessment_id) do
    sql = """
    SELECT * FROM answer WHERE assessment = type::record($id);
    """

    case UserClient.query(conn, sql, %{"id" => assessment_id}) do
      {:ok, [rows]} when is_list(rows) -> {:ok, rows}
      {:ok, rows} when is_list(rows) -> {:ok, rows}
      {:error, reason} -> {:error, reason}
    end
  end

  def upsert_answer(conn, attrs) when is_map(attrs) do
    sql = """
    DELETE answer WHERE
      assessment = type::record($assessment_id)
      AND pack = $pack
      AND pack_ref = $pack_ref
      AND question_id = $question_id;
    CREATE answer SET
      org = type::record($org_id),
      assessment = type::record($assessment_id),
      question_id = $question_id,
      pack = $pack,
      pack_ref = $pack_ref,
      value = $value,
      answered_by = $auth.id,
      answered_at = time::now();
    """

    case UserClient.query(conn, sql, attrs) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  def record_id(value) do
    cond do
      is_binary(value) ->
        value

      is_struct(value) ->
        to_string(value)

      is_map(value) and Map.has_key?(value, "tb") and Map.has_key?(value, "id") ->
        "#{value["tb"]}:#{value["id"]}"

      true ->
        inspect(value)
    end
  end

  defp normalize_record(row) when is_map(row) do
    id = record_id(Map.get(row, "id") || Map.get(row, :id))
    Map.put(row, "id", id)
  end

  defp last_result(results) when is_list(results) do
    results
    |> Enum.reverse()
    |> Enum.find(fn
      nil -> false
      :ok -> false
      _ -> true
    end)
  end

  defp last_result(other), do: other
end
