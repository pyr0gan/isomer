import { config as loadEnv } from "dotenv";

loadEnv();

function required(name) {
  const value = process.env[name];
  if (value == null || String(value).trim() === "") {
    throw new Error(
      `Missing required env var ${name}. Copy .env.example to .env and fill values ` +
        `(or run via \`op run --env-file=.env -- …\` for 1Password op:// references).`,
    );
  }
  return String(value).trim();
}

function optional(name, fallback = undefined) {
  const value = process.env[name];
  if (value == null || String(value).trim() === "") return fallback;
  return String(value).trim();
}

/** Reject unresolved 1Password references so we fail clearly. */
function assertResolved(name, value) {
  if (typeof value === "string" && value.startsWith("op://")) {
    throw new Error(
      `${name} still looks like a 1Password reference (${value}). ` +
        `Run with \`npm run db:ping:op\` (or \`op run --env-file=.env -- …\`) so the CLI injects secrets.`,
    );
  }
  return value;
}

export function getSurrealConfig() {
  const url = assertResolved("SURREAL_URL", required("SURREAL_URL"));
  const namespace = assertResolved(
    "SURREAL_NAMESPACE",
    required("SURREAL_NAMESPACE"),
  );
  const database = assertResolved(
    "SURREAL_DATABASE",
    required("SURREAL_DATABASE"),
  );
  const username = assertResolved(
    "SURREAL_USERNAME",
    optional("SURREAL_USERNAME", "root"),
  );

  return { url, namespace, database, username };
}

export function getVaultConfig() {
  const addr = assertResolved(
    "VAULT_ADDR",
    optional("VAULT_ADDR", "https://v.omega-agent.cloud"),
  ).replace(/\/$/, "");
  const token = optional("VAULT_TOKEN");
  const roleId = optional("VAULT_ROLE_ID");
  const secretId = optional("VAULT_SECRET_ID");
  const path = assertResolved("VAULT_SECRET_PATH", required("VAULT_SECRET_PATH"));
  const field = assertResolved(
    "VAULT_SECRET_FIELD",
    optional("VAULT_SECRET_FIELD", "password"),
  );
  const kvVersion = optional("VAULT_KV_VERSION");

  if (token) assertResolved("VAULT_TOKEN", token);
  if (roleId) assertResolved("VAULT_ROLE_ID", roleId);
  if (secretId) assertResolved("VAULT_SECRET_ID", secretId);

  if (!token && !(roleId && secretId)) {
    throw new Error(
      "Vault auth missing: set VAULT_TOKEN, or both VAULT_ROLE_ID and VAULT_SECRET_ID, in .env",
    );
  }

  return { addr, token, roleId, secretId, path, field, kvVersion };
}
