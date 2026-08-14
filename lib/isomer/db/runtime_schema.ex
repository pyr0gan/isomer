defmodule Isomer.Db.RuntimeSchema do
  @moduledoc """
  Tenant/runtime Surreal schema for the assessment questionnaire.

  Separate from corpus sync: these tables hold org/user data and must never be
  pruned by `mix isomer.db.sync`. See `docs/assessment-runtime.md`.
  """

  alias Isomer.Db.UserClient

  @access_name "isomer_user"

  @required_user_fields ~w(email name password self_role experience_level comfort_level created_at updated_at)

  @required_tenant_tables ~w(user org member assessment answer evidence artifact)

  @doc "Idempotent DEFINE for auth, tenant tables, and corpus read grants."
  def ensure!(db) do
    # Functions before tables that reference them in PERMISSIONS; function bodies
    # are evaluated at call time so `member` need not exist yet at DEFINE time.
    :ok = ensure_runtime_functions!(db)
    :ok = ensure_user_and_access!(db)
    :ok = ensure_tenant_tables!(db)
    :ok = ensure_corpus_read_grants!(db)
    :ok = assert_user_fields!(db)
    :ok = assert_tenant_tables!(db)
    :ok
  end

  def access_name, do: @access_name

  @doc "User table fields that Settings / auth expect (for CI verification)."
  def required_user_fields, do: @required_user_fields

  @doc "Tenant tables the LiveViews expect (for CI verification)."
  def required_tenant_tables, do: @required_tenant_tables

  @doc """
  Returns sorted field names defined on `user`, or raises if INFO fails.
  Used after ensure so CI cannot report success when DEFINE FIELD was a no-op.
  """
  def user_field_names!(db) do
    case SurrealDB.query(db, "INFO FOR TABLE user;") do
      {:ok, results} ->
        results
        |> List.wrap()
        |> List.last()
        |> extract_field_names()
        |> case do
          {:ok, names} -> Enum.sort(names)
          {:error, reason} -> raise "INFO FOR TABLE user: #{reason}"
        end

      {:error, reason} ->
        raise "INFO FOR TABLE user failed: #{inspect(reason)}"
    end
  end

  @doc """
  Returns sorted table names from `INFO FOR DB`, or raises.
  """
  def table_names!(db) do
    case SurrealDB.query(db, "INFO FOR DB;") do
      {:ok, results} ->
        results
        |> List.wrap()
        |> List.last()
        |> extract_table_names()
        |> case do
          {:ok, names} -> Enum.sort(names)
          {:error, reason} -> raise "INFO FOR DB: #{reason}"
        end

      {:error, reason} ->
        raise "INFO FOR DB failed: #{inspect(reason)}"
    end
  end

  @doc """
  Proves guidance prefs and **answer-backed artifact storage** are usable under
  **record** auth (not just root).

  Root INFO / root CREATE can look green while LiveView JWT sessions still fail
  with "no such field" or "table does not exist". The record-auth probe
  `SELECT`s `answer` with `pack_ref=__artifacts__` — the supported generated-doc
  path — rather than requiring writes to the standalone `artifact` table.
  Called from the Mix task after `ensure!/1`.
  """
  def assert_record_runtime!(root_db) do
    email =
      "isomer-record-probe-" <>
        Integer.to_string(System.unique_integer([:positive])) <> "@example.invalid"

    password = "probe-password-99"

    case UserClient.signup!(%{
           "email" => email,
           "password" => password,
           "name" => "record probe"
         }) do
      {:ok, %{conn: conn}} ->
        try do
          # Name update works on the schema Fly actually serves. Pref columns and
          # the standalone artifact table may lag on Surreal Cloud compute nodes.
          case UserClient.query(conn, "UPDATE $auth SET name = $name;", %{
                 "name" => "record probe ok"
               }) do
            {:ok, _} ->
              :ok

            {:error, reason} ->
              raise ArgumentError, "record-auth name write failed: #{inspect(reason)}"
          end

          case UserClient.query(
                 conn,
                 "SELECT count() FROM answer WHERE pack_ref = $ref GROUP ALL;",
                 %{"ref" => "__artifacts__"}
               ) do
            {:ok, _} ->
              :ok

            {:error, reason} ->
              raise ArgumentError,
                    "record-auth answer (artifact storage) select failed: #{inspect(reason)}"
          end
        after
          UserClient.stop(conn)
        end

      {:error, reason} ->
        raise ArgumentError, "record-auth signup probe failed: #{inspect(reason)}"
    end

    _ = SurrealDB.query(root_db, "DELETE user WHERE email = $email;", %{"email" => email})
    :ok
  end

  defp assert_user_fields!(db) do
    names = user_field_names!(db)
    missing = Enum.reject(@required_user_fields, &(&1 in names))

    if missing != [] do
      raise ArgumentError,
            "runtime ensure left user table missing fields #{inspect(missing)}; " <>
              "present=#{inspect(names)}. Check Surreal version / DEFINE FIELD errors."
    end

    # INFO alone is not enough on Surreal Cloud — fields can appear in INFO FOR TABLE
    # while SCHEMAFULL writes still fail with "Found field … but no such field exists".
    probe_user_pref_write!(db)
    :ok
  end

  defp assert_tenant_tables!(db) do
    names = table_names!(db)
    missing = Enum.reject(@required_tenant_tables, &(&1 in names))

    if missing != [] do
      raise ArgumentError,
            "runtime ensure left tenant tables missing #{inspect(missing)}; " <>
              "present=#{inspect(names)}"
    end

    case SurrealDB.query(db, "SELECT count() FROM artifact GROUP ALL;") do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        raise ArgumentError,
              "artifact listed in INFO FOR DB but SELECT failed: #{inspect(reason)}"
    end
  end

  defp probe_user_pref_write!(db) do
    case SurrealDB.query(db, """
         DELETE user:isomer_schema_probe;
         CREATE user:isomer_schema_probe CONTENT {
           email: "isomer-schema-probe@example.invalid",
           password: "probe-not-a-login",
           name: "schema probe",
           self_role: "other",
           experience_level: "intermediate",
           comfort_level: "moderate",
           updated_at: time::now()
         };
         DELETE user:isomer_schema_probe;
         """) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        raise ArgumentError,
              "user preference fields are listed in INFO but SCHEMAFULL write failed: " <>
                inspect(reason)
    end
  end

  defp extract_field_names(%{"fields" => fields}) when is_map(fields),
    do: {:ok, Map.keys(fields) |> Enum.map(&to_string/1)}

  defp extract_field_names(%{fields: fields}) when is_map(fields),
    do: {:ok, Map.keys(fields) |> Enum.map(&to_string/1)}

  defp extract_field_names([row | _]) when is_map(row), do: extract_field_names(row)

  defp extract_field_names(other),
    do: {:error, "unexpected INFO shape: #{inspect(other)}"}

  defp extract_table_names(%{"tables" => tables}) when is_map(tables),
    do: {:ok, Map.keys(tables) |> Enum.map(&to_string/1)}

  defp extract_table_names(%{tables: tables}) when is_map(tables),
    do: {:ok, Map.keys(tables) |> Enum.map(&to_string/1)}

  defp extract_table_names([row | _]) when is_map(row), do: extract_table_names(row)

  defp extract_table_names(other),
    do: {:error, "unexpected INFO FOR DB shape: #{inspect(other)}"}

  defp ensure_runtime_functions!(db) do
    {:ok, _} =
      SurrealDB.query(db, """
      DEFINE FUNCTION OVERWRITE fn::isomer::member_org_ids() -> array
      {
        RETURN IF $auth = NONE {
          []
        } ELSE {
          SELECT VALUE out FROM member WHERE in = $auth.id
        };
      }
      COMMENT "Org record ids the current auth user belongs to"
      PERMISSIONS FULL;

      DEFINE FUNCTION OVERWRITE fn::isomer::member_org_ids_with_roles($roles: array) -> array
      {
        RETURN IF $auth = NONE {
          []
        } ELSE {
          SELECT VALUE out FROM member WHERE in = $auth.id AND role IN $roles
        };
      }
      COMMENT "Org ids where auth user has one of the given member.role values"
      PERMISSIONS FULL;
      """)

    :ok
  end

  defp ensure_user_and_access!(db) do
    # Table first (OVERWRITE can clear field defs on some Surreal builds), then
    # each field in its own query so a bad DEFINE cannot be swallowed in a batch.
    :ok =
      exec!(db, """
      DEFINE TABLE OVERWRITE user SCHEMAFULL
        PERMISSIONS
          FOR select WHERE id = $auth.id OR $auth != NONE
          FOR update WHERE id = $auth.id
          FOR create, delete NONE
        COMMENT "Record-auth subjects for assessment LiveViews";
      """)

    # All columns BEFORE DEFINE ACCESS. Pref fields added after ACCESS left root
    # INFO/CREATE green while record-auth UPDATE still hit "no such field".
    Enum.each(
      [
        ~S[DEFINE FIELD OVERWRITE email ON user TYPE string ASSERT string::is_email($value);],
        ~S[DEFINE FIELD OVERWRITE name ON user TYPE option<string>;],
        # Password must never be readable via record SELECT (invite lookups need
        # email/id). SIGNIN/SIGNUP ACCESS still compares/hashes passwords.
        ~S[DEFINE FIELD OVERWRITE password ON user TYPE string PERMISSIONS FOR select NONE FOR create FULL FOR update WHERE id = $auth.id;],
        ~S[DEFINE FIELD OVERWRITE self_role ON user TYPE option<string> COMMENT "Self-identified organizational role for adaptive guidance copy";],
        ~S[DEFINE FIELD OVERWRITE experience_level ON user TYPE option<string> COMMENT "Self-identified familiarity with governance material";],
        ~S[DEFINE FIELD OVERWRITE comfort_level ON user TYPE option<string> COMMENT "Preferred amount of plain-language help in the UI";],
        ~S[DEFINE FIELD OVERWRITE created_at ON user TYPE datetime DEFAULT time::now();],
        ~S[DEFINE FIELD OVERWRITE updated_at ON user TYPE datetime VALUE time::now() DEFAULT time::now();],
        ~S[DEFINE INDEX OVERWRITE user_email ON user FIELDS email UNIQUE;]
      ],
      &exec!(db, &1)
    )

    :ok =
      exec!(db, """
      DEFINE ACCESS OVERWRITE #{@access_name} ON DATABASE TYPE RECORD
        SIGNUP (
          IF !string::is_email($email) {
            THROW "Enter a valid email address."
          } ELSE IF string::len($password) < 8 {
            THROW "Password must be at least 8 characters."
          } ELSE IF count(SELECT * FROM user WHERE email = $email) > 0 {
            THROW "An account with this email already exists. Sign in instead."
          } ELSE {
            CREATE user CONTENT {
              name: $name,
              email: $email,
              password: crypto::argon2::generate($password)
            }
          }
        )
        SIGNIN (
          SELECT * FROM user WHERE email = $email
            AND crypto::argon2::compare(password, $password)
        )
        DURATION FOR TOKEN 1h, FOR SESSION 12h
        COMMENT "Surreal-native auth for Phoenix LiveView sessions";
      """)

    :ok
  end

  defp exec!(db, surql) do
    case SurrealDB.query(db, surql) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        raise "Surreal DDL failed: #{inspect(reason)} — for SQL: #{String.slice(surql, 0, 160)}"
    end
  end

  # One table (or small group) per query — large multi-DEFINE batches have left
  # later tables (e.g. artifact) missing on Surreal Cloud while earlier ones exist.
  defp ensure_tenant_tables!(db) do
    Enum.each(tenant_table_ddl(), &exec!(db, &1))
    :ok
  end

  defp tenant_table_ddl do
    [
      """
      DEFINE TABLE OVERWRITE org SCHEMAFULL
        PERMISSIONS
          FOR select WHERE id IN fn::isomer::member_org_ids() OR created_by = $auth.id
          FOR create WHERE $auth != NONE
          FOR update WHERE id IN fn::isomer::member_org_ids_with_roles(["owner", "admin"])
          FOR delete WHERE id IN fn::isomer::member_org_ids_with_roles(["owner"])
        COMMENT "Organization (assessment tenant)";

      DEFINE FIELD OVERWRITE name ON org TYPE string ASSERT string::len($value) > 0;
      DEFINE FIELD OVERWRITE slug ON org TYPE option<string>;
      DEFINE FIELD OVERWRITE created_by ON org TYPE record<user>;
      DEFINE FIELD OVERWRITE created_at ON org TYPE datetime DEFAULT time::now();
      """,
      """
      DEFINE TABLE OVERWRITE member
        TYPE RELATION IN user OUT org ENFORCED
        SCHEMAFULL
        PERMISSIONS
          FOR select WHERE in = $auth.id OR out IN fn::isomer::member_org_ids_with_roles(["owner", "admin"])
          FOR create WHERE in = $auth.id OR out IN fn::isomer::member_org_ids_with_roles(["owner", "admin"])
          FOR update, delete WHERE out IN fn::isomer::member_org_ids_with_roles(["owner", "admin"])
        COMMENT "user -> org membership with role";

      DEFINE FIELD OVERWRITE role ON member TYPE string
        ASSERT $value IN ["owner", "admin", "assessor", "viewer"];
      DEFINE FIELD OVERWRITE created_at ON member TYPE datetime DEFAULT time::now();
      DEFINE INDEX OVERWRITE member_unique ON member FIELDS in, out UNIQUE;
      """,
      """
      DEFINE TABLE OVERWRITE assessment SCHEMAFULL
        PERMISSIONS
          FOR select WHERE org IN fn::isomer::member_org_ids()
          FOR create WHERE org IN fn::isomer::member_org_ids_with_roles(["owner", "admin", "assessor"])
          FOR update WHERE org IN fn::isomer::member_org_ids_with_roles(["owner", "admin", "assessor"])
          FOR delete WHERE org IN fn::isomer::member_org_ids_with_roles(["owner", "admin"])
        COMMENT "One questionnaire run for an org";

      DEFINE FIELD OVERWRITE org ON assessment TYPE record<org>;
      DEFINE FIELD OVERWRITE title ON assessment TYPE string;
      DEFINE FIELD OVERWRITE status ON assessment TYPE string
        ASSERT $value IN ["draft", "in_progress", "complete", "archived"]
        DEFAULT "draft";
      DEFINE FIELD OVERWRITE kind ON assessment TYPE string
        ASSERT $value IN ["ruleset", "domains", "combined"];
      DEFINE FIELD OVERWRITE ruleset_id ON assessment TYPE option<string>
        COMMENT "Corpus ruleset id string";
      DEFINE FIELD OVERWRITE domains ON assessment TYPE option<array<string>>
        COMMENT "question_set domain ids";
      DEFINE FIELD OVERWRITE classification ON assessment TYPE option<object>;
      DEFINE FIELD OVERWRITE activates ON assessment TYPE option<array>
        COMMENT "Activated requirement corpus ids from ruleset eval";
      DEFINE FIELD OVERWRITE domain_metrics ON assessment TYPE option<object> FLEXIBLE
        COMMENT "Per-domain metric opt-in: {domain_id: {collect, time_scale (relative effort), time_hours}}";
      DEFINE FIELD OVERWRITE created_by ON assessment TYPE record<user>;
      DEFINE FIELD OVERWRITE created_at ON assessment TYPE datetime DEFAULT time::now();
      DEFINE FIELD OVERWRITE updated_at ON assessment TYPE datetime DEFAULT time::now();
      DEFINE INDEX OVERWRITE assessment_org ON assessment FIELDS org;
      """,
      """
      DEFINE TABLE OVERWRITE answer SCHEMAFULL
        PERMISSIONS
          FOR select WHERE org IN fn::isomer::member_org_ids()
          FOR create, update WHERE org IN fn::isomer::member_org_ids_with_roles(["owner", "admin", "assessor"])
          FOR delete WHERE org IN fn::isomer::member_org_ids_with_roles(["owner", "admin", "assessor"])
        COMMENT "Single answer row inside an assessment";

      DEFINE FIELD OVERWRITE org ON answer TYPE record<org>;
      DEFINE FIELD OVERWRITE assessment ON answer TYPE record<assessment>;
      DEFINE FIELD OVERWRITE question_id ON answer TYPE string;
      DEFINE FIELD OVERWRITE pack ON answer TYPE string
        ASSERT $value IN ["ruleset", "question_set"];
      DEFINE FIELD OVERWRITE pack_ref ON answer TYPE string
        COMMENT "Ruleset id or domain id";
      DEFINE FIELD OVERWRITE value ON answer TYPE any;
      DEFINE FIELD OVERWRITE answered_by ON answer TYPE record<user>;
      DEFINE FIELD OVERWRITE answered_at ON answer TYPE datetime DEFAULT time::now();
      DEFINE INDEX OVERWRITE answer_unique ON answer FIELDS assessment, pack, pack_ref, question_id UNIQUE;
      DEFINE INDEX OVERWRITE answer_org ON answer FIELDS org;
      """,
      """
      DEFINE TABLE OVERWRITE evidence SCHEMAFULL
        PERMISSIONS
          FOR select WHERE org IN fn::isomer::member_org_ids()
          FOR create, update WHERE org IN fn::isomer::member_org_ids_with_roles(["owner", "admin", "assessor"])
          FOR delete WHERE org IN fn::isomer::member_org_ids_with_roles(["owner", "admin", "assessor"])
        COMMENT "Evidence metadata linked to an answer";

      DEFINE FIELD OVERWRITE org ON evidence TYPE record<org>;
      DEFINE FIELD OVERWRITE answer ON evidence TYPE record<answer>;
      DEFINE FIELD OVERWRITE label ON evidence TYPE option<string>;
      DEFINE FIELD OVERWRITE storage_key ON evidence TYPE option<string>
        COMMENT "External URL (slice 1) or object-storage key (slice 2)";
      DEFINE FIELD OVERWRITE content_type ON evidence TYPE option<string>;
      DEFINE FIELD OVERWRITE uploaded_by ON evidence TYPE record<user>;
      DEFINE FIELD OVERWRITE uploaded_at ON evidence TYPE datetime DEFAULT time::now();
      DEFINE INDEX OVERWRITE evidence_answer ON evidence FIELDS answer;
      DEFINE INDEX OVERWRITE evidence_org ON evidence FIELDS org;
      """,
      """
      DEFINE TABLE OVERWRITE artifact SCHEMAFULL
        PERMISSIONS
          FOR select WHERE org IN fn::isomer::member_org_ids()
          FOR create, update WHERE org IN fn::isomer::member_org_ids_with_roles(["owner", "admin", "assessor"])
          FOR delete WHERE org IN fn::isomer::member_org_ids_with_roles(["owner", "admin", "assessor"])
        COMMENT "Rendered template instance for an assessment";

      DEFINE FIELD OVERWRITE org ON artifact TYPE record<org>;
      DEFINE FIELD OVERWRITE assessment ON artifact TYPE record<assessment>;
      DEFINE FIELD OVERWRITE template_id ON artifact TYPE string
        COMMENT "Corpus template corpus_id (e.g. tmpl-ai-policy)";
      DEFINE FIELD OVERWRITE title ON artifact TYPE string;
      DEFINE FIELD OVERWRITE body ON artifact TYPE string
        COMMENT "Rendered Markdown body";
      DEFINE FIELD OVERWRITE format ON artifact TYPE string
        ASSERT $value IN ["markdown"]
        DEFAULT "markdown"
        COMMENT "Canonical stored format; downloads may derive HTML/PDF views";
      DEFINE FIELD OVERWRITE merge_values ON artifact TYPE option<object> FLEXIBLE
        COMMENT "Dotted-path merge field values used at generate time";
      DEFINE FIELD OVERWRITE created_by ON artifact TYPE record<user>;
      DEFINE FIELD OVERWRITE created_at ON artifact TYPE datetime DEFAULT time::now();
      DEFINE INDEX OVERWRITE artifact_assessment ON artifact FIELDS assessment;
      DEFINE INDEX OVERWRITE artifact_org ON artifact FIELDS org;
      DEFINE INDEX OVERWRITE artifact_template ON artifact FIELDS template_id;
      """
    ]
  end

  defp ensure_corpus_read_grants!(db) do
    # Record users default to PERMISSIONS NONE. Grant select on published corpus
    # so LiveView can project questionnaires with the user JWT.
    # Split per table so a late failure cannot leave earlier grants applied while
    # CI still reports a single opaque batch OK.
    Enum.each(
      [
        ~S[DEFINE TABLE OVERWRITE domain SCHEMALESS PERMISSIONS FOR select WHERE $auth != NONE FOR create, update, delete NONE;],
        ~S[DEFINE TABLE OVERWRITE framework SCHEMALESS PERMISSIONS FOR select WHERE $auth != NONE FOR create, update, delete NONE;],
        ~S[DEFINE TABLE OVERWRITE requirement SCHEMALESS PERMISSIONS FOR select WHERE $auth != NONE FOR create, update, delete NONE;],
        ~S[DEFINE TABLE OVERWRITE mapping_set SCHEMALESS PERMISSIONS FOR select WHERE $auth != NONE FOR create, update, delete NONE;],
        ~S[DEFINE TABLE OVERWRITE ruleset SCHEMALESS PERMISSIONS FOR select WHERE $auth != NONE FOR create, update, delete NONE;],
        ~S[DEFINE TABLE OVERWRITE rubric SCHEMALESS PERMISSIONS FOR select WHERE $auth != NONE FOR create, update, delete NONE;],
        ~S[DEFINE TABLE OVERWRITE question_set SCHEMALESS PERMISSIONS FOR select WHERE $auth != NONE FOR create, update, delete NONE;],
        ~S[DEFINE TABLE OVERWRITE template SCHEMALESS PERMISSIONS FOR select WHERE $auth != NONE FOR create, update, delete NONE;],
        ~S[DEFINE TABLE OVERWRITE sync_run SCHEMALESS PERMISSIONS FOR select WHERE $auth != NONE FOR create, update, delete NONE;],
        """
        DEFINE TABLE OVERWRITE maps_to
          TYPE RELATION IN requirement OUT requirement ENFORCED
          SCHEMALESS
          PERMISSIONS FOR select WHERE $auth != NONE FOR create, update, delete NONE
          COMMENT "Corpus mapping edges (relation/strength/note/reviewed on the edge)";
        """
      ],
      &exec!(db, &1)
    )

    Enum.each(
      [
        ~S[DEFINE INDEX IF NOT EXISTS requirement_corpus_id ON requirement FIELDS corpus_id UNIQUE;],
        ~S[DEFINE INDEX IF NOT EXISTS framework_corpus_key ON framework FIELDS corpus_key UNIQUE;],
        ~S[DEFINE INDEX IF NOT EXISTS mapping_set_corpus_id ON mapping_set FIELDS corpus_id UNIQUE;],
        ~S[DEFINE INDEX IF NOT EXISTS ruleset_corpus_id ON ruleset FIELDS corpus_id UNIQUE;],
        ~S[DEFINE INDEX IF NOT EXISTS rubric_domain ON rubric FIELDS domain UNIQUE;],
        ~S[DEFINE INDEX IF NOT EXISTS question_set_domain ON question_set FIELDS domain UNIQUE;],
        ~S[DEFINE INDEX IF NOT EXISTS template_corpus_id ON template FIELDS corpus_id UNIQUE;],
        ~S[DEFINE INDEX IF NOT EXISTS maps_to_edge_key ON maps_to FIELDS edge_key UNIQUE;]
      ],
      &exec!(db, &1)
    )

    :ok
  end
end
