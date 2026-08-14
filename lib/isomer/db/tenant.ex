defmodule Isomer.Db.Tenant do
  @moduledoc """
  Surreal queries for orgs, assessments, answers, and generated documents (user JWT).

  ## Generated documents (supported storage)

  Rendered templates are **not** written to the standalone `artifact` table.
  They are stored as `answer` rows with:

  - `pack` = `"question_set"`
  - `pack_ref` = `"__artifacts__"`
  - `value` = `%{template_id, title, body, format, merge_values}`

  `Isomer.Db.RuntimeSchema` still `DEFINE`s table `artifact` for forward
  schema readiness and root probes, but LiveView / Library / downloads only
  use this answer-backed path. That avoids Surreal Cloud multi-IP lag where
  Actions can apply `DEFINE TABLE artifact` while the Fly dyno still hits a
  compute node without the table ("table does not exist").

  Org and assessment deletes remove these rows via `DELETE answer …` (same as
  questionnaire answers). A best-effort `DELETE artifact …` may run afterward
  for any leftover standalone-table rows and must never fail the teardown.
  """

  alias Isomer.Db.UserClient
  alias Isomer.GuideCopy
  alias Isomer.Roles

  @artifact_pack "question_set"
  @artifact_pack_ref "__artifacts__"

  @doc "Answer `pack_ref` used for generated documents (Library / downloads)."
  def artifact_pack_ref, do: @artifact_pack_ref

  @doc "Answer `pack` used for generated documents."
  def artifact_pack, do: @artifact_pack

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

  @doc """
  Current user's membership role on an org (`owner` / `admin` / `assessor` /
  `viewer`). Returns `{:error, :not_found}` when the user is not a member.
  """
  def get_membership(conn, org_id) when is_binary(org_id) do
    {table, key} = split_record_id!(org_id)

    sql = """
    SELECT id, role, created_at, in AS user_id, out AS org_id
    FROM member
    WHERE in = $auth.id AND out = type::record($table, $key)
    LIMIT 1;
    """

    case UserClient.query(conn, sql, %{"table" => table, "key" => key}) do
      {:ok, results} ->
        case rows_of(results) do
          [row | _] ->
            {:ok,
             row
             |> normalize_record()
             |> Map.update("role", "viewer", &Roles.normalize/1)
             |> Map.update("user_id", nil, &canonicalize_record_id/1)
             |> Map.update("org_id", nil, &canonicalize_record_id/1)}

          [] ->
            {:error, :not_found}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Members of an org with email/name from the related user.

  Owners/admins can list everyone (Surreal member SELECT). Other roles only see
  their own edge — callers should gate the admin UI with `Roles.can_manage_members?/1`.
  """
  def list_members(conn, org_id) when is_binary(org_id) do
    {table, key} = split_record_id!(org_id)

    sql = """
    SELECT
      id,
      role,
      created_at,
      in AS user_id,
      in.email AS email,
      in.name AS name
    FROM member
    WHERE out = type::record($table, $key)
    ORDER BY role ASC, email ASC;
    """

    case UserClient.query(conn, sql, %{"table" => table, "key" => key}) do
      {:ok, results} ->
        rows =
          results
          |> rows_of()
          |> Enum.map(fn row ->
            row
            |> normalize_record()
            |> Map.update("role", "viewer", &Roles.normalize/1)
            |> Map.update("user_id", nil, &canonicalize_record_id/1)
          end)

        {:ok, rows}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Add an existing user (by email) to the org. Caller must be owner/admin.

  Users must already have an account — this slice does not send invite email.
  """
  def add_member_by_email(conn, org_id, email, role)
      when is_binary(org_id) and is_binary(email) and is_binary(role) do
    email = email |> String.trim() |> String.downcase()
    role = Roles.normalize(role)

    cond do
      not String.contains?(email, "@") ->
        {:error, "Enter a valid email address."}

      role == "owner" ->
        {:error, "Promote an existing member to owner instead of inviting as owner."}

      role not in Roles.all() ->
        {:error, "Unknown role."}

      true ->
        {table, key} = split_record_id!(org_id)

        sql = """
        LET $org = type::record($table, $key);
        IF $org NOT IN fn::isomer::member_org_ids_with_roles(["owner", "admin"]) {
          THROW "Only owners and admins can add members.";
        };
        LET $uid = (SELECT VALUE id FROM user WHERE email = $email LIMIT 1)[0];
        IF $uid = NONE {
          THROW "No account with that email. Ask them to sign up first, then add them here.";
        };
        IF count(SELECT * FROM member WHERE in = $uid AND out = $org) > 0 {
          THROW "That user is already a member of this organization.";
        };
        RELATE $uid -> member -> $org SET role = $role;
        RETURN SELECT
          id, role, created_at,
          in AS user_id, in.email AS email, in.name AS name
        FROM member
        WHERE in = $uid AND out = $org
        LIMIT 1;
        """

        case UserClient.query(
               conn,
               sql,
               %{"table" => table, "key" => key, "email" => email, "role" => role}
             ) do
          {:ok, results} ->
            case unwrap_one(results) do
              {:ok, row} ->
                {:ok,
                 row
                 |> Map.update("role", "viewer", &Roles.normalize/1)
                 |> Map.update("user_id", nil, &canonicalize_record_id/1)}

              other ->
                other
            end

          {:error, reason} ->
            {:error, humanize_member_error(reason)}
        end
    end
  end

  @doc """
  Change a member's role. Refuses to demote the last owner.
  """
  def update_member_role(conn, org_id, member_id, role)
      when is_binary(org_id) and is_binary(member_id) and is_binary(role) do
    role = Roles.normalize(role)
    org_id = canonicalize_record_id(org_id)
    member_id = canonicalize_record_id(member_id)
    {org_table, org_key} = split_record_id!(org_id)
    {member_table, member_key} = split_record_id!(member_id)

    sql = """
    LET $org = type::record($org_table, $org_key);
    LET $mid = type::record($member_table, $member_key);
    IF $org NOT IN fn::isomer::member_org_ids_with_roles(["owner", "admin"]) {
      THROW "Only owners and admins can change roles.";
    };
    LET $row = (SELECT * FROM ONLY $mid);
    IF $row = NONE OR $row.out != $org {
      THROW "Member not found on this organization.";
    };
    IF $row.role = "owner" AND $role != "owner" {
      LET $owners = count(SELECT * FROM member WHERE out = $org AND role = "owner");
      IF $owners <= 1 {
        THROW "Cannot demote the last owner.";
      };
    };
    UPDATE $mid SET role = $role;
    RETURN SELECT
      id, role, created_at,
      in AS user_id, in.email AS email, in.name AS name
    FROM ONLY $mid;
    """

    case UserClient.query(
           conn,
           sql,
           %{
             "org_table" => org_table,
             "org_key" => org_key,
             "member_table" => member_table,
             "member_key" => member_key,
             "role" => role
           }
         ) do
      {:ok, results} ->
        case unwrap_one(results) do
          {:ok, row} ->
            {:ok,
             row
             |> Map.update("role", "viewer", &Roles.normalize/1)
             |> Map.update("user_id", nil, &canonicalize_record_id/1)}

          other ->
            other
        end

      {:error, reason} ->
        {:error, humanize_member_error(reason)}
    end
  end

  @doc """
  Remove a member edge. Refuses to remove the last owner.
  """
  def remove_member(conn, org_id, member_id)
      when is_binary(org_id) and is_binary(member_id) do
    org_id = canonicalize_record_id(org_id)
    member_id = canonicalize_record_id(member_id)
    {org_table, org_key} = split_record_id!(org_id)
    {member_table, member_key} = split_record_id!(member_id)

    sql = """
    LET $org = type::record($org_table, $org_key);
    LET $mid = type::record($member_table, $member_key);
    IF $org NOT IN fn::isomer::member_org_ids_with_roles(["owner", "admin"]) {
      THROW "Only owners and admins can remove members.";
    };
    LET $row = (SELECT * FROM ONLY $mid);
    IF $row = NONE OR $row.out != $org {
      THROW "Member not found on this organization.";
    };
    IF $row.role = "owner" {
      LET $owners = count(SELECT * FROM member WHERE out = $org AND role = "owner");
      IF $owners <= 1 {
        THROW "Cannot remove the last owner.";
      };
    };
    DELETE $mid;
    """

    case UserClient.query(
           conn,
           sql,
           %{
             "org_table" => org_table,
             "org_key" => org_key,
             "member_table" => member_table,
             "member_key" => member_key
           }
         ) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, humanize_member_error(reason)}
    end
  end

  defp humanize_member_error(%{message: msg}) when is_binary(msg), do: strip_throw_prefix(msg)
  defp humanize_member_error(msg) when is_binary(msg), do: strip_throw_prefix(msg)
  defp humanize_member_error(other), do: other

  defp strip_throw_prefix("An error occurred: " <> rest), do: rest
  defp strip_throw_prefix("Error: " <> rest), do: rest
  defp strip_throw_prefix(msg), do: msg

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
    vars = %{"table" => table, "key" => key}

    # Delete the org while membership still exists — org FOR delete checks
    # member_org_ids_with_roles(["owner"]). Removing members first would deny
    # the org delete. Clean up member edges afterward.
    #
    # Generated docs are answer rows (`pack_ref=__artifacts__`) and go away with
    # DELETE answer. Best-effort standalone `artifact` cleanup must not block.
    case UserClient.query(
           conn,
           """
           LET $org = type::record($table, $key);
           DELETE evidence WHERE org = $org;
           DELETE answer WHERE org = $org;
           DELETE assessment WHERE org = $org;
           DELETE $org;
           DELETE member WHERE out = $org;
           RETURN SELECT * FROM ONLY $org;
           """,
           vars
         ) do
      {:ok, results} ->
        _ = best_effort_delete_standalone_artifacts(conn, "org", vars)

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
  Renames an assessment. Blank titles are rejected.
  Returns the updated assessment.
  """
  def update_assessment_title(conn, assessment_id, title)
      when is_binary(assessment_id) and is_binary(title) do
    assessment_id = canonicalize_record_id(assessment_id)
    title = String.trim(title)

    if title == "" do
      {:error, "Title is required"}
    else
      {table, key} = split_record_id!(assessment_id)

      sql = """
      LET $aid = type::record($table, $key);
      UPDATE $aid SET title = $title, updated_at = time::now();
      RETURN SELECT * FROM ONLY $aid;
      """

      case UserClient.query(conn, sql, %{
             "table" => table,
             "key" => key,
             "title" => title
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
    vars = %{"table" => table, "key" => key}

    case UserClient.query(
           conn,
           """
           LET $aid = type::record($table, $key);
           LET $answer_ids = (SELECT VALUE id FROM answer WHERE assessment = $aid);
           DELETE evidence WHERE answer IN $answer_ids;
           DELETE answer WHERE assessment = $aid;
           DELETE $aid;
           RETURN SELECT * FROM ONLY $aid;
           """,
           vars
         ) do
      {:ok, results} ->
        _ = best_effort_delete_standalone_artifacts(conn, "assessment", vars)

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
  Merges one domain's metric collection entry into `assessment.domain_metrics`.

  `attrs` keys (string): `collect` (bool), optional `time_scale`
  (`low`|`medium`|`high` — relative effort for the domain on this assessment,
  not a calendar period), optional `time_hours` (number). When `collect` is
  false the domain key is removed. Omits optional fields rather than binding
  `nil` (Surreal `option` rejects JSON null).
  """
  def update_domain_metric(conn, assessment_id, domain_id, attrs)
      when is_binary(assessment_id) and is_binary(domain_id) and is_map(attrs) do
    assessment_id = canonicalize_record_id(assessment_id)
    domain_id = domain_id |> to_string() |> String.trim()
    {table, key} = split_record_id!(assessment_id)

    with {:ok, assessment} <- get_assessment(conn, assessment_id) do
      current = normalize_domain_metrics(assessment["domain_metrics"])
      collect? = truthy_metric?(Map.get(attrs, "collect") || Map.get(attrs, :collect))

      next =
        if collect? do
          entry = build_domain_metric_entry(attrs)
          Map.put(current, domain_id, entry)
        else
          Map.delete(current, domain_id)
        end

      # Empty map clears opt-ins; avoid binding JSON null into option<object>.
      sql = """
      LET $aid = type::record($table, $key);
      UPDATE $aid SET domain_metrics = $domain_metrics, updated_at = time::now();
      RETURN SELECT * FROM ONLY $aid;
      """

      vars = %{
        "table" => table,
        "key" => key,
        "domain_metrics" => next
      }

      case UserClient.query(conn, sql, vars) do
        {:ok, results} -> unwrap_one(results)
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp normalize_domain_metrics(metrics) when is_map(metrics) and not is_struct(metrics),
    do: metrics

  defp normalize_domain_metrics(_), do: %{}

  defp build_domain_metric_entry(attrs) do
    scale =
      attrs
      |> Map.get("time_scale", Map.get(attrs, :time_scale))
      |> normalize_time_scale()

    hours =
      attrs
      |> Map.get("time_hours", Map.get(attrs, :time_hours))
      |> normalize_time_hours()

    entry = %{"collect" => true}

    entry =
      if is_binary(scale) do
        Map.put(entry, "time_scale", scale)
      else
        entry
      end

    if is_number(hours) do
      Map.put(entry, "time_hours", hours)
    else
      entry
    end
  end

  defp normalize_time_scale(scale) when scale in ["low", "medium", "high"], do: scale
  defp normalize_time_scale(_), do: nil

  defp normalize_time_hours(nil), do: nil
  defp normalize_time_hours(""), do: nil

  defp normalize_time_hours(value) when is_number(value) and value >= 0, do: value

  defp normalize_time_hours(value) when is_binary(value) do
    case Float.parse(String.trim(value)) do
      {n, _} when n >= 0 -> n
      _ -> nil
    end
  end

  defp normalize_time_hours(_), do: nil

  defp truthy_metric?(v) when v in [true, "true", "on", "1", 1], do: true
  defp truthy_metric?(_), do: false

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

  @doc """
  Published classification rulesets (`corpus_id`, questions, outcomes, …).

  Record users may SELECT corpus tables after `ensure_runtime`.
  """
  def list_rulesets(conn) do
    case UserClient.query(
           conn,
           """
           SELECT corpus_id, ruleset, framework, status, questions, outcomes, default_outcome
           FROM ruleset
           ORDER BY corpus_id ASC;
           """
         ) do
      {:ok, results} -> {:ok, rows_of(results)}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Fetch one ruleset by corpus id string."
  def get_ruleset(conn, corpus_id) when is_binary(corpus_id) do
    case UserClient.query(
           conn,
           """
           SELECT * FROM ruleset WHERE corpus_id = $id LIMIT 1;
           """,
           %{"id" => corpus_id}
         ) do
      {:ok, results} ->
        case rows_of(results) do
          [row | _] -> {:ok, row}
          [] -> {:error, :not_found}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Requirement titles/frameworks keyed by corpus id.

  Used by Results to label activated obligations and satisfier targets.
  """
  def list_requirements_by_ids(conn, corpus_ids) when is_list(corpus_ids) do
    ids =
      corpus_ids
      |> Enum.map(&to_string/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.uniq()

    if ids == [] do
      {:ok, %{}}
    else
      case UserClient.query(
             conn,
             """
             SELECT corpus_id, title, framework
             FROM requirement
             WHERE corpus_id INSIDE $ids;
             """,
             %{"ids" => ids}
           ) do
        {:ok, results} ->
          index =
            results
            |> rows_of()
            |> Map.new(fn row ->
              {row["corpus_id"], %{"title" => row["title"], "framework" => row["framework"]}}
            end)

          {:ok, index}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Satisfaction edges (`satisfied_by` / `partially_satisfied_by`) for the given
  requirement corpus ids — same relations as `fn::isomer::satisfiers`.
  """
  def list_satisfier_edges(conn, corpus_ids) when is_list(corpus_ids) do
    ids =
      corpus_ids
      |> Enum.map(&to_string/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.uniq()

    if ids == [] do
      {:ok, []}
    else
      case UserClient.query(
             conn,
             """
             SELECT
               in.corpus_id AS from_corpus_id,
               in.title AS from_title,
               relation,
               strength,
               note,
               out.corpus_id AS target_corpus_id,
               out.title AS target_title,
               out.framework AS target_framework
             FROM maps_to
             WHERE in.corpus_id INSIDE $ids
               AND relation IN $relations
               AND content_source = $content_source
             ORDER BY edge_key ASC;
             """,
             %{
               "ids" => ids,
               "relations" => ["satisfied_by", "partially_satisfied_by"],
               "content_source" => Isomer.Db.Params.content_source()
             }
           ) do
        {:ok, results} -> {:ok, rows_of(results)}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @doc """
  Persist ruleset evaluation onto an assessment.

  `classification` is an object; `activates` is an array of requirement corpus
  id strings. Omits neither field (both are written together).
  """
  def update_assessment_classification(conn, assessment_id, classification, activates)
      when is_binary(assessment_id) and is_map(classification) and is_list(activates) do
    assessment_id = canonicalize_record_id(assessment_id)
    {table, key} = split_record_id!(assessment_id)

    case UserClient.query(
           conn,
           """
           UPDATE type::record($table, $key) SET
             classification = $classification,
             activates = $activates,
             updated_at = time::now();
           RETURN SELECT * FROM ONLY type::record($table, $key);
           """,
           %{
             "table" => table,
             "key" => key,
             "classification" => classification,
             "activates" => activates
           }
         ) do
      {:ok, results} -> unwrap_one(results)
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Current auth user profile (prefs + identity). Never returns password."
  def get_current_user(conn) do
    # Project fields from $auth — do not SELECT * (password hash).
    sql = """
    RETURN {
      id: $auth.id,
      email: $auth.email,
      name: $auth.name,
      self_role: $auth.self_role,
      experience_level: $auth.experience_level,
      comfort_level: $auth.comfort_level,
      created_at: $auth.created_at,
      updated_at: $auth.updated_at
    };
    """

    case UserClient.query(conn, sql) do
      {:ok, results} -> unwrap_one(results)
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Updates self-identified guidance prefs on the auth user.

  Empty strings clear optional fields via `UNSET` (Surreal cannot store JSON null /
  `NONE` into `option` fields the way Postgres does). Pref enum membership is
  checked in Elixir — Surreal columns are plain `option<string>`.
  """
  def update_user_prefs(conn, attrs) when is_map(attrs) do
    fields = [
      {"name", attrs |> Map.get("name", Map.get(attrs, :name)), :any},
      {"self_role", attrs |> Map.get("self_role", Map.get(attrs, :self_role)), GuideCopy.roles()},
      {"experience_level",
       attrs |> Map.get("experience_level", Map.get(attrs, :experience_level)),
       GuideCopy.experience_levels()},
      {"comfort_level", attrs |> Map.get("comfort_level", Map.get(attrs, :comfort_level)),
       GuideCopy.comfort_levels()}
    ]

    with :ok <- validate_pref_enums(fields) do
      {set_parts, unset_parts, vars} =
        Enum.reduce(fields, {[], [], %{}}, fn {field, raw, _allowed}, {sets, unsets, vars} ->
          case blank_to_nil(raw) do
            nil when field == "name" ->
              # Keep name present (option<string>); blank becomes empty string.
              {["name = $name" | sets], unsets, Map.put(vars, "name", "")}

            nil ->
              {sets, [field | unsets], vars}

            value ->
              {["#{field} = $#{field}" | sets], unsets, Map.put(vars, field, value)}
          end
        end)

      # Prefer UPDATE $auth — same subject as the LiveView JWT. Do not SET
      # updated_at here; the field VALUE clause refreshes it when defined.
      statements =
        []
        |> then(fn acc ->
          case set_parts do
            [] -> acc
            parts -> ["UPDATE $auth SET #{Enum.join(Enum.reverse(parts), ", ")};" | acc]
          end
        end)
        |> then(fn acc ->
          case unset_parts do
            [] ->
              acc

            fields ->
              ["UPDATE $auth UNSET #{Enum.join(Enum.reverse(fields), ", ")};" | acc]
          end
        end)
        |> Enum.reverse()

      sql = """
      #{Enum.join(statements, "\n")}
      RETURN {
        id: $auth.id,
        email: $auth.email,
        name: $auth.name,
        self_role: $auth.self_role,
        experience_level: $auth.experience_level,
        comfort_level: $auth.comfort_level,
        created_at: $auth.created_at,
        updated_at: $auth.updated_at
      };
      """

      case UserClient.query(conn, sql, vars) do
        {:ok, results} -> unwrap_one(results)
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp validate_pref_enums(fields) do
    Enum.reduce_while(fields, :ok, fn
      {_field, _raw, :any}, :ok ->
        {:cont, :ok}

      {field, raw, allowed}, :ok when is_list(allowed) ->
        case blank_to_nil(raw) do
          nil ->
            {:cont, :ok}

          value ->
            if value in allowed do
              {:cont, :ok}
            else
              {:halt, {:error, "invalid #{field}: #{inspect(value)}"}}
            end
        end
    end)
  end

  def list_templates(conn) do
    case UserClient.query(
           conn,
           """
           SELECT corpus_id, name, version, kind, covers, merge_fields, body
           FROM template
           ORDER BY name ASC;
           """
         ) do
      {:ok, results} -> {:ok, Enum.map(rows_of(results), &normalize_record/1)}
      {:error, reason} -> {:error, reason}
    end
  end

  def get_template(conn, corpus_id) when is_binary(corpus_id) do
    sql = """
    SELECT * FROM template WHERE corpus_id = $corpus_id LIMIT 1;
    """

    case UserClient.query(conn, sql, %{"corpus_id" => corpus_id}) do
      {:ok, results} ->
        case rows_of(results) do
          [row | _] -> {:ok, normalize_record(row)}
          [] -> {:error, :not_found}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  def list_artifacts(conn) do
    case UserClient.query(
           conn,
           """
           SELECT * FROM answer
           WHERE pack = $pack AND pack_ref = $pack_ref
           ORDER BY answered_at DESC;
           """,
           %{"pack" => @artifact_pack, "pack_ref" => @artifact_pack_ref}
         ) do
      {:ok, results} ->
        {:ok, Enum.map(rows_of(results), &answer_as_artifact/1)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def list_artifacts_for_assessment(conn, assessment_id) when is_binary(assessment_id) do
    {table, key} = split_record_id!(assessment_id)

    sql = """
    SELECT * FROM answer
    WHERE assessment = type::record($table, $key)
      AND pack = $pack
      AND pack_ref = $pack_ref
    ORDER BY answered_at DESC;
    """

    case UserClient.query(conn, sql, %{
           "table" => table,
           "key" => key,
           "pack" => @artifact_pack,
           "pack_ref" => @artifact_pack_ref
         }) do
      {:ok, results} ->
        {:ok, Enum.map(rows_of(results), &answer_as_artifact/1)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def get_artifact(conn, artifact_id) when is_binary(artifact_id) do
    {table, key} = split_record_id!(artifact_id)

    case UserClient.query(conn, "SELECT * FROM type::record($table, $key);", %{
           "table" => table,
           "key" => key
         }) do
      {:ok, results} ->
        case unwrap_one(results) do
          {:ok, row} ->
            if to_string(row["pack_ref"] || "") == @artifact_pack_ref do
              {:ok, answer_as_artifact(row)}
            else
              {:error, :not_found}
            end

          other ->
            other
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  def create_artifact(conn, attrs) when is_map(attrs) do
    org_id = canonicalize_record_id(attrs["org_id"])
    assessment_id = canonicalize_record_id(attrs["assessment_id"])
    {org_table, org_key} = split_record_id!(org_id)
    {assessment_table, assessment_key} = split_record_id!(assessment_id)

    merge_values = Map.get(attrs, "merge_values") || %{}
    question_id = "artifact:" <> "d" <> random_key(16)

    value = %{
      "template_id" => attrs["template_id"],
      "title" => attrs["title"],
      "body" => attrs["body"],
      "format" => "markdown",
      "merge_values" => merge_values
    }

    sql = """
    LET $key = string::concat("d", rand::string(16));
    LET $aid = type::record("answer", $key);
    CREATE $aid SET
      org = type::record($org_table, $org_key),
      assessment = type::record($assessment_table, $assessment_key),
      question_id = $question_id,
      pack = $pack,
      pack_ref = $pack_ref,
      value = $value,
      answered_by = $auth.id,
      answered_at = time::now();
    RETURN SELECT * FROM ONLY $aid;
    """

    vars = %{
      "org_table" => org_table,
      "org_key" => org_key,
      "assessment_table" => assessment_table,
      "assessment_key" => assessment_key,
      "question_id" => question_id,
      "pack" => @artifact_pack,
      "pack_ref" => @artifact_pack_ref,
      "value" => value
    }

    case UserClient.query(conn, sql, vars) do
      {:ok, results} ->
        case unwrap_one(results) do
          {:ok, row} -> {:ok, answer_as_artifact(row)}
          other -> other
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  def delete_artifact(conn, artifact_id) when is_binary(artifact_id) do
    artifact_id = canonicalize_record_id(artifact_id)
    {table, key} = split_record_id!(artifact_id)

    sql = """
    LET $did = type::record($table, $key);
    DELETE evidence WHERE answer = $did;
    DELETE $did;
    RETURN SELECT * FROM ONLY $did;
    """

    case UserClient.query(conn, sql, %{"table" => table, "key" => key}) do
      {:ok, results} ->
        case useful_result(results) do
          row when is_map(row) and not is_struct(row) ->
            {:error, "Artifact could not be deleted (still present)."}

          [row | _] when is_map(row) and not is_struct(row) ->
            {:error, "Artifact could not be deleted (still present)."}

          _ ->
            :ok
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp answer_as_artifact(row) when is_map(row) do
    value =
      case row["value"] do
        %{} = map -> map
        _ -> %{}
      end

    row
    |> normalize_record()
    |> Map.merge(%{
      "template_id" => value["template_id"],
      "title" => value["title"] || value["template_id"] || "Artifact",
      "body" => value["body"] || "",
      "format" => value["format"] || "markdown",
      "merge_values" => value["merge_values"] || %{},
      "created_at" => row["answered_at"] || row["created_at"],
      "created_by" => row["answered_by"] || row["created_by"]
    })
  end

  defp random_key(len) when is_integer(len) and len > 0 do
    :crypto.strong_rand_bytes(len)
    |> Base.url_encode64(padding: false)
    |> binary_part(0, len)
    |> String.downcase()
  end

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value) when is_binary(value), do: String.trim(value)
  defp blank_to_nil(value), do: value

  # Optional cleanup if a compute node has the standalone `artifact` table and
  # leftover rows; ignore "table does not exist" and similar.
  defp best_effort_delete_standalone_artifacts(conn, "org", vars) do
    case UserClient.query(
           conn,
           """
           LET $org = type::record($table, $key);
           DELETE artifact WHERE org = $org;
           """,
           vars
         ) do
      {:ok, _} -> :ok
      {:error, _} -> :ok
    end
  end

  defp best_effort_delete_standalone_artifacts(conn, "assessment", vars) do
    case UserClient.query(
           conn,
           """
           LET $aid = type::record($table, $key);
           DELETE artifact WHERE assessment = $aid;
           """,
           vars
         ) do
      {:ok, _} -> :ok
      {:error, _} -> :ok
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

    # Update in place when the unique key exists so linked `evidence.answer`
    # record ids stay stable across answer edits.
    sql = """
    LET $existing = (
      SELECT VALUE id FROM answer WHERE
        assessment = type::record($assessment_table, $assessment_key)
        AND pack = $pack
        AND pack_ref = $pack_ref
        AND question_id = $question_id
      LIMIT 1
    )[0];
    IF $existing = NONE {
      LET $key = string::concat("a", rand::string(16));
      LET $aid = type::record("answer", $key);
      CREATE $aid SET
        org = type::record($org_table, $org_key),
        assessment = type::record($assessment_table, $assessment_key),
        question_id = $question_id,
        pack = $pack,
        pack_ref = $pack_ref,
        value = $value,
        answered_by = $auth.id,
        answered_at = time::now();
      RETURN SELECT * FROM ONLY $aid;
    } ELSE {
      UPDATE $existing SET
        value = $value,
        answered_by = $auth.id,
        answered_at = time::now();
      RETURN SELECT * FROM ONLY $existing;
    };
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
      {:ok, results} ->
        case unwrap_one(results) do
          {:ok, row} -> {:ok, normalize_record(row)}
          other -> other
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Evidence rows for an assessment, denormalized with `question_id` from the
  linked answer. Used by the wizard and org metrics `evidence_pct`.
  """
  def list_evidence_for_assessment(conn, assessment_id) when is_binary(assessment_id) do
    {table, key} = split_record_id!(assessment_id)

    sql = """
    LET $aids = (
      SELECT VALUE id FROM answer
      WHERE assessment = type::record($table, $key)
        AND pack_ref != $artifact_ref
    );
    SELECT
      id,
      org,
      answer,
      label,
      storage_key,
      content_type,
      uploaded_by,
      uploaded_at,
      answer.question_id AS question_id
    FROM evidence
    WHERE answer IN $aids
    ORDER BY uploaded_at ASC;
    """

    case UserClient.query(
           conn,
           sql,
           %{
             "table" => table,
             "key" => key,
             "artifact_ref" => @artifact_pack_ref
           }
         ) do
      {:ok, results} ->
        rows =
          results
          |> rows_of()
          |> Enum.map(&normalize_evidence/1)

        {:ok, rows}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Attach metadata evidence to an answer.

  `storage_key` holds an external URL in this slice (object-storage keys later).
  Empty optional fields are omitted (Surreal `option<string>` rejects null).
  """
  def create_evidence(conn, attrs) when is_map(attrs) do
    org_id = canonicalize_record_id(attrs["org_id"])
    answer_id = canonicalize_record_id(attrs["answer_id"])
    {org_table, org_key} = split_record_id!(org_id)
    {answer_table, answer_key} = split_record_id!(answer_id)

    label =
      attrs
      |> Map.get("label", "")
      |> to_string()
      |> String.trim()

    if label == "" do
      {:error, "Evidence label is required."}
    else
      content_type =
        attrs
        |> Map.get("content_type", "")
        |> to_string()
        |> String.trim()

      storage_key =
        attrs
        |> Map.get("storage_key", Map.get(attrs, "url", ""))
        |> to_string()
        |> String.trim()

      set_bits = [
        "org = type::record($org_table, $org_key)",
        "answer = type::record($answer_table, $answer_key)",
        "label = $label",
        "uploaded_by = $auth.id",
        "uploaded_at = time::now()"
      ]

      vars = %{
        "org_table" => org_table,
        "org_key" => org_key,
        "answer_table" => answer_table,
        "answer_key" => answer_key,
        "label" => label
      }

      {set_bits, vars} =
        if content_type == "" do
          {set_bits, vars}
        else
          {set_bits ++ ["content_type = $content_type"],
           Map.put(vars, "content_type", content_type)}
        end

      {set_bits, vars} =
        if storage_key == "" do
          {set_bits, vars}
        else
          {set_bits ++ ["storage_key = $storage_key"], Map.put(vars, "storage_key", storage_key)}
        end

      sql = """
      LET $key = string::concat("e", rand::string(16));
      LET $eid = type::record("evidence", $key);
      CREATE $eid SET #{Enum.join(set_bits, ", ")};
      RETURN SELECT
        id, org, answer, label, storage_key, content_type, uploaded_by, uploaded_at,
        answer.question_id AS question_id
      FROM ONLY $eid;
      """

      case UserClient.query(conn, sql, vars) do
        {:ok, results} ->
          case unwrap_one(results) do
            {:ok, row} -> {:ok, normalize_evidence(row)}
            other -> other
          end

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc "Remove one evidence row. Assessors/owners/admins may delete."
  def delete_evidence(conn, evidence_id) when is_binary(evidence_id) do
    evidence_id = canonicalize_record_id(evidence_id)
    {table, key} = split_record_id!(evidence_id)

    sql = """
    DELETE type::record($table, $key);
    """

    case UserClient.query(conn, sql, %{"table" => table, "key" => key}) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp normalize_evidence(row) when is_map(row) do
    row
    |> normalize_record()
    |> Map.update("answer", nil, &canonicalize_record_id/1)
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
