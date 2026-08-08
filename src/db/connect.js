import { Surreal } from "surrealdb";
import { getSurrealConfig, getVaultConfig } from "../config.js";
import { getSurrealPasswordFromVault } from "../vault/secrets.js";

/**
 * Connect to SurrealDB using credentials whose password is read from Vault.
 *
 * Password is resolved via the SDK `authentication` async callback so reconnects
 * can re-fetch from Vault if needed.
 *
 * @param {object} [overrides]
 * @param {string} [overrides.url]
 * @param {string} [overrides.namespace]
 * @param {string} [overrides.database]
 * @param {string} [overrides.username]
 * @returns {Promise<Surreal>}
 */
export async function connectSurreal(overrides = {}) {
  const surreal = { ...getSurrealConfig(), ...overrides };
  const vault = getVaultConfig();

  // Fail fast with a clear Vault error before opening the WebSocket.
  await getSurrealPasswordFromVault(vault);

  const db = new Surreal();

  await db.connect(surreal.url, {
    namespace: surreal.namespace,
    database: surreal.database,
    authentication: async () => ({
      username: surreal.username,
      password: await getSurrealPasswordFromVault(vault),
    }),
  });

  return db;
}

/**
 * Run a small connectivity probe and return a summary object.
 */
export async function pingSurreal(overrides = {}) {
  let db;
  try {
    db = await connectSurreal(overrides);
    const surreal = { ...getSurrealConfig(), ...overrides };
    // Lightweight round-trip; works on SurrealDB 2.x/3.x cloud instances.
    const result = await db.query("RETURN 'isomer-ok';");
    return {
      ok: true,
      url: surreal.url,
      namespace: surreal.namespace,
      database: surreal.database,
      result,
    };
  } catch (err) {
    if (err?.isInvalidAuth) {
      const wrapped = new Error(
        "SurrealDB authentication failed (InvalidAuth). " +
          "Confirm the password stored in Vault matches a Root user in Surrealist " +
          "(Authentication → Root Authentication), and that SURREAL_USERNAME matches that user.",
      );
      wrapped.cause = err;
      throw wrapped;
    }
    throw err;
  } finally {
    if (db) await db.close();
  }
}
