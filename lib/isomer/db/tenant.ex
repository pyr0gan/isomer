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
    # Pre-generate an alphanumeric org key (leading letter) so URLs/ids never need
    # Surreal backtick escaping — digit-leading ids break type::record($id) round-trips.
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
    {table, key} = split_record_id!(org_id)

    case UserClient.query(conn, "SELECT * FROM type::record($table, $key);", %{
           "table" => table,
           "key" => key
         }) do
      {:ok, results} ->
        case unwrap_one(results) do
          {:ok, org} = ok ->
            _ = ensure_owner_membership(conn, org["id"])
            ok

          other ->
            other
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Orgs created during the early CREATE/RELATE bug can exist without a `member`
  edge. Assessment create requires membership, so heal owner membership when the
  current user is `created_by` and no member row exists yet.
  """
  def ensure_owner_membership(conn, org_id) when is_binary(org_id) do
    {table, key} = split_record_id!(org_id)

    check_sql = """
    LET $org = type::record($table, $key);
    RETURN {
      auth: $auth.id,
      creator: (SELECT VALUE created_by FROM ONLY $org),
      members: (SELECT * FROM member WHERE in = $auth.id AND out = $org)
    };
    """

    case UserClient.query(conn, check_sql, %{"table" => table, "key" => key}) do
      {:ok, results} ->
        info = useful_result(results)

        if heal_owner?(info) do
          heal_sql = """
          LET $org = type::record($table, $key);
          RELATE $auth -> member -> $org SET role = 'owner';
          """

          case UserClient.query(conn, heal_sql, %{"table" => table, "key" => key}) do
            {:ok, _} -> :ok
            {:error, reason} -> {:error, reason}
          end
        else
          :ok
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  def list_assessments(conn, org_id) when is_binary(org_id) do
    {table, key} = split_record_id!(org_id)

    sql = """
    SELECT * FROM assessment
    WHERE org = type::record($table, $key)
    ORDER BY created_at DESC;
    """

    case UserClient.query(conn, sql, %{"table" => table, "key" => key}) do
      {:ok, results} -> {:ok, Enum.map(rows_of(results), &normalize_record/1)}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Deletes an org and its tenant data (evidence, answers, assessments, members).
  Requires owner role on the org (Surreal PERMISSIONS).
  """
  def delete_org(conn, org_id) when is_binary(org_id) do
    org_id = canonicalize_record_id(org_id)
    {table, key} = split_record_id!(org_id)

    # Delete the org while membership still exists — org FOR delete checks
    # member_org_ids_with_roles(["owner"]). Removing members first would deny
    # the org delete. Clean up member edges afterward.
    sql = """
    LET $org = type::record($table, $key);
    DELETE evidence WHERE org = $org;
    DELETE answer WHERE org = $org;
    DELETE assessment WHERE org = $org;
    DELETE $org;
    DELETE member WHERE out = $org;
    RETURN SELECT * FROM ONLY $org;
    """

    case UserClient.query(conn, sql, %{"table" => table, "key" => key}) do
      {:ok, results} ->
        case useful_result(results) do
          row when is_map(row) and not is_struct(row) ->
            {:error, "Organization could not be deleted (still present). Are you the owner?"}

          [row | _] when is_map(row) and not is_struct(row) ->
            {:error, "Organization could not be deleted (still present). Are you the owner?"}

          _ ->
            :ok
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Short suffix of the record key for disambiguating duplicate names in the UI."
  def short_key(org_id) when is_binary(org_id) do
    {_table, key} = split_record_id!(org_id)
    String.slice(key, -6, 6)
  end

  def short_key(_), do: ""

  def create_assessment(conn, org_id, attrs) when is_binary(org_id) and is_map(attrs) do
    title = Map.fetch!(attrs, "title") |> String.trim()
    kind = Map.get(attrs, "kind", "domains")
    domains = Map.get(attrs, "domains") || []
    ruleset_id = Map.get(attrs, "ruleset_id")
    org_id = canonicalize_record_id(org_id)
    _ = ensure_owner_membership(conn, org_id)
    {org_table, org_key} = split_record_id!(org_id)

    {ruleset_sql, vars} =
      if is_binary(ruleset_id) and ruleset_id != "" do
        {"ruleset_id = $ruleset_id,",
         %{
           "org_table" => org_table,
           "org_key" => org_key,
           "title" => title,
           "kind" => kind,
           "domains" => domains,
           "ruleset_id" => ruleset_id
         }}
      else
        {"",
         %{
           "org_table" => org_table,
           "org_key" => org_key,
           "title" => title,
           "kind" => kind,
           "domains" => domains
         }}
      end

    sql = """
    LET $key = string::concat("a", rand::string(16));
    LET $aid = type::record("assessment", $key);
    LET $org = type::record($org_table, $org_key);
    LET $created = CREATE $aid SET
      org = $org,
      title = $title,
      kind = $kind,
      domains = $domains,
      #{ruleset_sql}
      status = 'draft',
      created_by = $auth.id,
      updated_at = time::now();
    RETURN $created;
    RETURN SELECT * FROM ONLY $aid;
    """

    case UserClient.query(conn, sql, vars) do
      {:ok, results} ->
        case take_created_assessment(results) do
          {:ok, _} = ok ->
            ok

          {:error, _} ->
            {:error,
             "Could not create assessment for #{canonicalize_record_id(org_id)}. " <>
               "This usually means there is no owner membership on the org " <>
               "(an early create bug left some orgs without a member edge). " <>
               "Open the org from /orgs once to repair, or create a new org."}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  def get_assessment(conn, assessment_id) when is_binary(assessment_id) do
    {table, key} = split_record_id!(assessment_id)

    case UserClient.query(conn, "SELECT * FROM type::record($table, $key);", %{
           "table" => table,
           "key" => key
         }) do
      {:ok, results} -> unwrap_one(results)
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Updates assessment `status` (`draft` | `in_progress` | `complete` | `archived`).
  Returns the updated assessment.
  """
  def update_assessment_status(conn, assessment_id, status)
      when is_binary(assessment_id) and is_binary(status) do
    assessment_id = canonicalize_record_id(assessment_id)
    {table, key} = split_record_id!(assessment_id)

    if status not in ["draft", "in_progress", "complete", "archived"] do
      {:error, "invalid assessment status: #{status}"}
    else
      sql = """
      LET $aid = type::record($table, $key);
      UPDATE $aid SET status = $status, updated_at = time::now();
      RETURN SELECT * FROM ONLY $aid;
      """

      case UserClient.query(conn, sql, %{
             "table" => table,
             "key" => key,
             "status" => status
           }) do
        {:ok, results} -> unwrap_one(results)
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @doc """
  Deletes an assessment and its answers/evidence. Requires owner/admin on the org.
  """
  def delete_assessment(conn, assessment_id) when is_binary(assessment_id) do
    assessment_id = canonicalize_record_id(assessment_id)
    {table, key} = split_record_id!(assessment_id)

    sql = """
    LET $aid = type::record($table, $key);
    LET $answer_ids = (SELECT VALUE id FROM answer WHERE assessment = $aid);
    DELETE evidence WHERE answer IN $answer_ids;
    DELETE answer WHERE assessment = $aid;
    DELETE $aid;
    RETURN SELECT * FROM ONLY $aid;
    """

    case UserClient.query(conn, sql, %{"table" => table, "key" => key}) do
      {:ok, results} ->
        case useful_result(results) do
          row when is_map(row) and not is_struct(row) ->
            {:error, "Assessment could not be deleted (still present)."}

          [row | _] when is_map(row) and not is_struct(row) ->
            {:error, "Assessment could not be deleted (still present)."}

          _ ->
            :ok
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Unions `new_domains` into the assessment's `domains` array (does not remove
  existing domains). Returns the updated assessment.
  """
  def add_assessment_domains(conn, assessment_id, new_domains)
      when is_binary(assessment_id) and is_list(new_domains) do
    assessment_id = canonicalize_record_id(assessment_id)
    {table, key} = split_record_id!(assessment_id)

    incoming =
      new_domains
      |> Enum.map(&to_string/1)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.uniq()

    with {:ok, assessment} <- get_assessment(conn, assessment_id) do
      merged =
        (assessment["domains"] || [])
        |> Kernel.++(incoming)
        |> Enum.uniq()

      if merged == (assessment["domains"] || []) do
        {:ok, assessment}
      else
        sql = """
        LET $aid = type::record($table, $key);
        UPDATE $aid SET domains = $domains, updated_at = time::now();
        RETURN SELECT * FROM ONLY $aid;
        """

        case UserClient.query(conn, sql, %{
               "table" => table,
               "key" => key,
               "domains" => merged
             }) do
          {:ok, results} -> unwrap_one(results)
          {:error, reason} -> {:error, reason}
        end
      end
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
    {table, key} = split_record_id!(assessment_id)

    sql = """
    SELECT * FROM answer WHERE assessment = type::record($table, $key);
    """

    case UserClient.query(conn, sql, %{"table" => table, "key" => key}) do
      {:ok, results} -> {:ok, rows_of(results)}
      {:error, reason} -> {:error, reason}
    end
  end

  def upsert_answer(conn, attrs) when is_map(attrs) do
    {org_table, org_key} = split_record_id!(attrs["org_id"])
    {assessment_table, assessment_key} = split_record_id!(attrs["assessment_id"])

    sql = """
    DELETE answer WHERE
      assessment = type::record($assessment_table, $assessment_key)
      AND pack = $pack
      AND pack_ref = $pack_ref
      AND question_id = $question_id;
    CREATE answer SET
      org = type::record($org_table, $org_key),
      assessment = type::record($assessment_table, $assessment_key),
      question_id = $question_id,
      pack = $pack,
      pack_ref = $pack_ref,
      value = $value,
      answered_by = $auth.id,
      answered_at = time::now();
    """

    vars =
      attrs
      |> Map.drop(["org_id", "assessment_id"])
      |> Map.merge(%{
        "org_table" => org_table,
        "org_key" => org_key,
        "assessment_table" => assessment_table,
        "assessment_key" => assessment_key
      })

    case UserClient.query(conn, sql, vars) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Removes a single answer row (and its evidence) so the question becomes unanswered.
  """
  def delete_answer(conn, attrs) when is_map(attrs) do
    {assessment_table, assessment_key} = split_record_id!(attrs["assessment_id"])

    sql = """
    LET $rows = (
      SELECT VALUE id FROM answer WHERE
        assessment = type::record($assessment_table, $assessment_key)
        AND pack = $pack
        AND pack_ref = $pack_ref
        AND question_id = $question_id
    );
    DELETE evidence WHERE answer IN $rows;
    DELETE answer WHERE
      assessment = type::record($assessment_table, $assessment_key)
      AND pack = $pack
      AND pack_ref = $pack_ref
      AND question_id = $question_id;
    """

    vars = %{
      "assessment_table" => assessment_table,
      "assessment_key" => assessment_key,
      "pack" => attrs["pack"],
      "pack_ref" => attrs["pack_ref"],
      "question_id" => attrs["question_id"]
    }

    case UserClient.query(conn, sql, vars) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Canonical `table:key` without Surreal backtick escapes (safe for routes + binds)."
  def canonicalize_record_id(value) do
    case split_record_id(value) do
      {:ok, table, key} -> "#{table}:#{key}"
      :error -> value |> to_string() |> strip_backticks()
    end
  end

  def record_id(value) do
    canonicalize_record_id(value)
  end

  def split_record_id!(value) do
    case split_record_id(value) do
      {:ok, table, key} ->
        {table, key}

      :error ->
        raise ArgumentError, "invalid Surreal record id: #{inspect(value)}"
    end
  end

  defp split_record_id(%SurrealDB.RecordId{table: table, id: key}) do
    {:ok, strip_backticks(to_string(table)), normalize_key(key)}
  end

  defp split_record_id(value) when is_binary(value) do
    value = value |> URI.decode() |> String.trim() |> strip_backticks()

    case String.split(value, ":", parts: 2) do
      [table, key] when table != "" and key != "" ->
        {:ok, table, strip_backticks(key)}

      _ ->
        :error
    end
  end

  defp split_record_id(value) when is_map(value) and not is_struct(value) do
    cond do
      Map.has_key?(value, "tb") and Map.has_key?(value, "id") ->
        {:ok, strip_backticks(to_string(value["tb"])), normalize_key(value["id"])}

      Map.has_key?(value, "id") ->
        split_record_id(value["id"])

      true ->
        :error
    end
  end

  defp split_record_id(value) when is_struct(value) do
    if none?(value), do: :error, else: split_record_id(to_string(value))
  end

  defp split_record_id(_), do: :error

  defp normalize_key(key) when is_binary(key), do: strip_backticks(key)
  defp normalize_key(key) when is_integer(key), do: Integer.to_string(key)
  defp normalize_key(key), do: strip_backticks(to_string(key))

  defp strip_backticks(value) when is_binary(value), do: String.replace(value, "`", "")

  defp take_created_assessment(results) do
    # Prefer a concrete row from CREATE/SELECT. Do not treat a bare RecordId as
    # success — CREATE can fail (empty []) while RETURN $aid still yields an id.
    case useful_result(results) do
      row when is_map(row) and not is_struct(row) ->
        {:ok, normalize_record(row)}

      [row | _] when is_map(row) and not is_struct(row) ->
        {:ok, normalize_record(row)}

      _ ->
        {:error, :not_created}
    end
  end

  defp unwrap_created(results, error_tag) do
    case useful_result(results) do
      row when is_map(row) and not is_struct(row) ->
        {:ok, normalize_record(row)}

      [row | _] when is_map(row) and not is_struct(row) ->
        {:ok, normalize_record(row)}

      %SurrealDB.RecordId{} = rid ->
        {:ok, %{"id" => canonicalize_record_id(rid)}}

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
    id = canonicalize_record_id(Map.get(row, "id") || Map.get(row, :id))
    Map.put(row, "id", id)
  end

  defp heal_owner?(info) when is_map(info) do
    auth = Map.get(info, "auth")
    creator = Map.get(info, "creator")
    members = Map.get(info, "members") || []

    same_user?(auth, creator) and members_empty?(members)
  end

  defp heal_owner?(_), do: false

  defp same_user?(a, b) do
    canonicalize_record_id(a) != "" and
      canonicalize_record_id(a) == canonicalize_record_id(b)
  end

  defp members_empty?(members) when is_list(members), do: members == []
  defp members_empty?(%SurrealDB.None{}), do: true
  defp members_empty?(_), do: false

  defp none?(%SurrealDB.None{}), do: true
  defp none?(_), do: false
end
