defmodule Isomer.Db.Tenant do
  @moduledoc "Surreal queries for orgs, assessments, and wizard answers (user JWT)."

  alias Isomer.Db.UserClient

  def list_orgs(conn) do
    case UserClient.query(conn, "SELECT * FROM org ORDER BY name ASC;") do
      {:ok, results} -> {:ok, Enum.map(rows_of(results), &normalize_record/1)}
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
      {:ok, results} -> unwrap_created(results, :unexpected_create_org)
      {:error, reason} -> {:error, reason}
    end
  end

  def get_org(conn, org_id) when is_binary(org_id) do
    case UserClient.query(conn, "SELECT * FROM type::record($id);", %{"id" => org_id}) do
      {:ok, results} -> unwrap_one(results)
      {:error, reason} -> {:error, reason}
    end
  end

  def list_assessments(conn, org_id) when is_binary(org_id) do
    sql = """
    SELECT * FROM assessment
    WHERE org = type::record($org_id)
    ORDER BY created_at DESC;
    """

    case UserClient.query(conn, sql, %{"org_id" => org_id}) do
      {:ok, results} -> {:ok, Enum.map(rows_of(results), &normalize_record/1)}
      {:error, reason} -> {:error, reason}
    end
  end

  def create_assessment(conn, org_id, attrs) when is_binary(org_id) and is_map(attrs) do
    title = Map.fetch!(attrs, "title") |> String.trim()
    kind = Map.get(attrs, "kind", "domains")
    domains = Map.get(attrs, "domains") || []
    ruleset_id = Map.get(attrs, "ruleset_id")

    # Pre-generate id + SELECT back. CREATE ONLY often returns NONE when the
    # statement result is filtered by PERMISSIONS even though the write succeeds.
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
    LET $key = string::concat("a", rand::string(16));
    LET $aid = type::record("assessment", $key);
    CREATE $aid SET
      org = type::record($org_id),
      title = $title,
      kind = $kind,
      domains = $domains,
      #{ruleset_sql}
      status = 'draft',
      created_by = $auth.id,
      updated_at = time::now();
    RETURN SELECT * FROM ONLY $aid;
    """

    case UserClient.query(conn, sql, vars) do
      {:ok, results} -> unwrap_created(results, :unexpected_create_assessment)
      {:error, reason} -> {:error, reason}
    end
  end

  def get_assessment(conn, assessment_id) when is_binary(assessment_id) do
    case UserClient.query(conn, "SELECT * FROM type::record($id);", %{"id" => assessment_id}) do
      {:ok, results} -> unwrap_one(results)
      {:error, reason} -> {:error, reason}
    end
  end

  def list_question_sets(conn) do
    case UserClient.query(
           conn,
           "SELECT corpus_id, title, domain, questions FROM question_set ORDER BY domain ASC;"
         ) do
      {:ok, results} -> {:ok, rows_of(results)}
      {:error, reason} -> {:error, reason}
    end
  end

  def list_answers(conn, assessment_id) when is_binary(assessment_id) do
    sql = """
    SELECT * FROM answer WHERE assessment = type::record($id);
    """

    case UserClient.query(conn, sql, %{"id" => assessment_id}) do
      {:ok, results} -> {:ok, rows_of(results)}
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

      none?(value) ->
        ""

      is_struct(value) ->
        to_string(value)

      is_map(value) and not is_struct(value) and Map.has_key?(value, "tb") and
          Map.has_key?(value, "id") ->
        "#{value["tb"]}:#{value["id"]}"

      true ->
        inspect(value)
    end
  end

  defp unwrap_created(results, error_tag) do
    case useful_result(results) do
      row when is_map(row) and not is_struct(row) ->
        {:ok, normalize_record(row)}

      [row | _] when is_map(row) and not is_struct(row) ->
        {:ok, normalize_record(row)}

      other ->
        {:error, {error_tag, other}}
    end
  end

  defp unwrap_one(results) do
    case useful_result(results) do
      row when is_map(row) and not is_struct(row) ->
        {:ok, normalize_record(row)}

      [row | _] when is_map(row) and not is_struct(row) ->
        {:ok, normalize_record(row)}

      [] ->
        {:error, :not_found}

      nil ->
        {:error, :not_found}

      other ->
        if none?(other), do: {:error, :not_found}, else: {:error, {:unexpected, other}}
    end
  end

  defp rows_of(results) do
    case useful_result(results) do
      rows when is_list(rows) ->
        Enum.filter(rows, &(is_map(&1) and not is_struct(&1)))

      row when is_map(row) and not is_struct(row) ->
        [row]

      _ ->
        []
    end
  end

  defp useful_result(results) when is_list(results) do
    results
    |> Enum.reverse()
    |> Enum.find(fn
      nil -> false
      :ok -> false
      value -> not none?(value)
    end)
  end

  defp useful_result(other), do: other

  defp normalize_record(row) when is_map(row) and not is_struct(row) do
    id = record_id(Map.get(row, "id") || Map.get(row, :id))
    Map.put(row, "id", id)
  end

  defp none?(%SurrealDB.None{}), do: true
  defp none?(_), do: false
end
