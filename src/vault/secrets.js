/**
 * Minimal HashiCorp Vault client (token or AppRole) for reading KV secrets.
 * Uses the Vault HTTP API via fetch — no node-vault dependency.
 */

/** Normalize a Vault API path: strip leading slashes and an optional `v1/` prefix. */
export function normalizeVaultPath(path) {
  return String(path)
    .trim()
    .replace(/^\/+/, "")
    .replace(/^v1\//, "");
}

async function vaultFetch(addr, path, { token, method = "GET", body } = {}) {
  const url = `${addr}/v1/${normalizeVaultPath(path)}`;
  const headers = { "Content-Type": "application/json" };
  if (token) headers["X-Vault-Token"] = token;

  const res = await fetch(url, {
    method,
    headers,
    body: body ? JSON.stringify(body) : undefined,
  });

  const text = await res.text();
  let json;
  try {
    json = text ? JSON.parse(text) : {};
  } catch {
    json = { raw: text };
  }

  if (!res.ok) {
    const msg =
      json?.errors?.join?.("; ") ||
      json?.error ||
      text ||
      res.statusText;
    throw new Error(`Vault ${method} ${path} failed (${res.status}): ${msg}`);
  }

  return json;
}

/** Login with AppRole and return a client token. */
export async function loginAppRole(addr, roleId, secretId) {
  const json = await vaultFetch(addr, "auth/approle/login", {
    method: "POST",
    body: { role_id: roleId, secret_id: secretId },
  });
  const clientToken = json?.auth?.client_token;
  if (!clientToken) {
    throw new Error("Vault AppRole login succeeded but no client_token returned");
  }
  return clientToken;
}

/**
 * Resolve a usable Vault token from config (static token or AppRole).
 */
export async function resolveVaultToken(vaultConfig) {
  if (vaultConfig.token) return vaultConfig.token;
  return loginAppRole(
    vaultConfig.addr,
    vaultConfig.roleId,
    vaultConfig.secretId,
  );
}

/**
 * Read a single field from a KV secret.
 * Supports KV v1 and v2 (auto-detect unless VAULT_KV_VERSION is set).
 */
export async function readSecretField(vaultConfig, token = undefined) {
  const clientToken = token ?? (await resolveVaultToken(vaultConfig));
  const json = await vaultFetch(vaultConfig.addr, vaultConfig.path, {
    token: clientToken,
  });

  const version = vaultConfig.kvVersion
    ? Number(vaultConfig.kvVersion)
    : json?.data?.data && typeof json.data.data === "object"
      ? 2
      : 1;

  const data =
    version === 2
      ? json?.data?.data
      : json?.data;

  if (!data || typeof data !== "object") {
    throw new Error(
      `Vault secret at ${vaultConfig.path} has unexpected shape (is VAULT_SECRET_PATH correct for KV v1 vs v2?)`,
    );
  }

  const value = data[vaultConfig.field];
  if (value == null || value === "") {
    throw new Error(
      `Vault secret at ${vaultConfig.path} is missing field "${vaultConfig.field}"`,
    );
  }

  return String(value);
}

/** Convenience: fetch the SurrealDB password from Vault. */
export async function getSurrealPasswordFromVault(vaultConfig) {
  return readSecretField(vaultConfig);
}
