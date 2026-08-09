defmodule Isomer.Db.RuntimeSchema do
  @moduledoc """
  Tenant/runtime Surreal schema for the assessment questionnaire.

  Separate from corpus sync: these tables hold org/user data and must never be
  pruned by `mix isomer.db.sync`. See `docs/assessment-runtime.md`.
  """

  @access_name "isomer_user"

  @doc "Idempotent DEFINE for auth, tenant tables, and corpus read grants."
  def ensure!(db) do
    # Functions before tables that reference them in PERMISSIONS; function bodies
    # are evaluated at call time so `member` need not exist yet at DEFINE time.
    :ok = ensure_runtime_functions!(db)
    :ok = ensure_user_and_access!(db)
    :ok = ensure_tenant_tables!(db)
    :ok = ensure_corpus_read_grants!(db)
    :ok
  end

  def access_name, do: @access_name

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
    {:ok, _} =
      SurrealDB.query(db, """
      DEFINE TABLE OVERWRITE user SCHEMAFULL
        PERMISSIONS
          FOR select, update WHERE id = $auth.id
          FOR create, delete NONE
        COMMENT "Record-auth subjects for assessment LiveViews";

      DEFINE FIELD OVERWRITE email ON user TYPE string ASSERT string::is_email($value);
      DEFINE FIELD OVERWRITE name ON user TYPE option<string>;
      DEFINE FIELD OVERWRITE password ON user TYPE string;
      DEFINE FIELD OVERWRITE created_at ON user TYPE datetime DEFAULT time::now();
      DEFINE INDEX OVERWRITE user_email ON user FIELDS email UNIQUE;

      DEFINE ACCESS OVERWRITE #{@access_name} ON DATABASE TYPE RECORD
        SIGNUP (
          CREATE user CONTENT {
            name: $name,
            email: $email,
            password: crypto::argon2::generate($password)
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

  defp ensure_tenant_tables!(db) do
    {:ok, _} =
      SurrealDB.query(db, """
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
      DEFINE FIELD OVERWRITE created_by ON assessment TYPE record<user>;
      DEFINE FIELD OVERWRITE created_at ON assessment TYPE datetime DEFAULT time::now();
      DEFINE FIELD OVERWRITE updated_at ON assessment TYPE datetime DEFAULT time::now();
      DEFINE INDEX OVERWRITE assessment_org ON assessment FIELDS org;

      -- org is denormalized onto answer/evidence so PERMISSIONS stay simple
      DEFINE TABLE OVERWRITE answer SCHEMAFULL
        PERMISSIONS
          FOR select WHERE org IN fn::isomer::member_org_ids()
          FOR create, update WHERE org IN fn::isomer::member_org_ids_with_roles(["owner", "admin", "assessor"])
          FOR delete WHERE org IN fn::isomer::member_org_ids_with_roles(["owner", "admin"])
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

      DEFINE TABLE OVERWRITE evidence SCHEMAFULL
        PERMISSIONS
          FOR select WHERE org IN fn::isomer::member_org_ids()
          FOR create, update WHERE org IN fn::isomer::member_org_ids_with_roles(["owner", "admin", "assessor"])
          FOR delete WHERE org IN fn::isomer::member_org_ids_with_roles(["owner", "admin"])
        COMMENT "Evidence metadata linked to an answer";

      DEFINE FIELD OVERWRITE org ON evidence TYPE record<org>;
      DEFINE FIELD OVERWRITE answer ON evidence TYPE record<answer>;
      DEFINE FIELD OVERWRITE label ON evidence TYPE option<string>;
      DEFINE FIELD OVERWRITE storage_key ON evidence TYPE option<string>;
      DEFINE FIELD OVERWRITE content_type ON evidence TYPE option<string>;
      DEFINE FIELD OVERWRITE uploaded_by ON evidence TYPE record<user>;
      DEFINE FIELD OVERWRITE uploaded_at ON evidence TYPE datetime DEFAULT time::now();
      DEFINE INDEX OVERWRITE evidence_answer ON evidence FIELDS answer;
      DEFINE INDEX OVERWRITE evidence_org ON evidence FIELDS org;
      """)

    :ok
  end

  defp ensure_corpus_read_grants!(db) do
    # Record users default to PERMISSIONS NONE. Grant select on published corpus
    # so LiveView can project questionnaires with the user JWT.
    {:ok, _} =
      SurrealDB.query(db, """
      DEFINE TABLE OVERWRITE domain SCHEMALESS
        PERMISSIONS FOR select WHERE $auth != NONE FOR create, update, delete NONE;
      DEFINE TABLE OVERWRITE framework SCHEMALESS
        PERMISSIONS FOR select WHERE $auth != NONE FOR create, update, delete NONE;
      DEFINE TABLE OVERWRITE requirement SCHEMALESS
        PERMISSIONS FOR select WHERE $auth != NONE FOR create, update, delete NONE;
      DEFINE TABLE OVERWRITE mapping_set SCHEMALESS
        PERMISSIONS FOR select WHERE $auth != NONE FOR create, update, delete NONE;
      DEFINE TABLE OVERWRITE ruleset SCHEMALESS
        PERMISSIONS FOR select WHERE $auth != NONE FOR create, update, delete NONE;
      DEFINE TABLE OVERWRITE rubric SCHEMALESS
        PERMISSIONS FOR select WHERE $auth != NONE FOR create, update, delete NONE;
      DEFINE TABLE OVERWRITE question_set SCHEMALESS
        PERMISSIONS FOR select WHERE $auth != NONE FOR create, update, delete NONE;
      DEFINE TABLE OVERWRITE template SCHEMALESS
        PERMISSIONS FOR select WHERE $auth != NONE FOR create, update, delete NONE;
      DEFINE TABLE OVERWRITE sync_run SCHEMALESS
        PERMISSIONS FOR select WHERE $auth != NONE FOR create, update, delete NONE;

      DEFINE TABLE OVERWRITE maps_to
        TYPE RELATION IN requirement OUT requirement ENFORCED
        SCHEMALESS
        PERMISSIONS FOR select WHERE $auth != NONE FOR create, update, delete NONE
        COMMENT "Corpus mapping edges (relation/strength/note/reviewed on the edge)";

      DEFINE INDEX IF NOT EXISTS requirement_corpus_id ON requirement FIELDS corpus_id UNIQUE;
      DEFINE INDEX IF NOT EXISTS framework_corpus_key ON framework FIELDS corpus_key UNIQUE;
      DEFINE INDEX IF NOT EXISTS mapping_set_corpus_id ON mapping_set FIELDS corpus_id UNIQUE;
      DEFINE INDEX IF NOT EXISTS ruleset_corpus_id ON ruleset FIELDS corpus_id UNIQUE;
      DEFINE INDEX IF NOT EXISTS rubric_domain ON rubric FIELDS domain UNIQUE;
      DEFINE INDEX IF NOT EXISTS question_set_domain ON question_set FIELDS domain UNIQUE;
      DEFINE INDEX IF NOT EXISTS template_corpus_id ON template FIELDS corpus_id UNIQUE;
      DEFINE INDEX IF NOT EXISTS maps_to_edge_key ON maps_to FIELDS edge_key UNIQUE;
      """)

    :ok
  end
end
