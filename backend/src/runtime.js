import { createApp } from "./application.js";
import { createHash } from "node:crypto";

const clean = (value) => (typeof value === "string" ? value.trim() : "");
const canonicalURL = (value) => {
  try {
    const url = new URL(value.replace(/^libsql:/, "https:"));
    url.hash = "";
    return url.href.replace(/\/$/, "");
  } catch {
    return value;
  }
};
export function runtimeOptions(env = process.env) {
  const vercel = env.VERCEL === "1" || !!env.VERCEL_ENV || !!env.VERCEL_URL;
  const requireRemote =
    vercel ||
    env.NODE_ENV === "production" ||
    env.REQUIRE_REMOTE_DATABASE === "true";
  const tursoUrl = clean(env.TURSO_DATABASE_URL),
    aliasUrl = clean(env.DATABASE_URL);
  const databaseUrl = tursoUrl || aliasUrl || undefined;
  const databaseAuthToken =
    clean(tursoUrl ? env.TURSO_AUTH_TOKEN : env.DATABASE_AUTH_TOKEN) ||
    undefined;
  const issues = [];
  if (!env.ADMIN_PASSWORD || env.ADMIN_PASSWORD.length < 10)
    issues.push("Defina ADMIN_PASSWORD com pelo menos 10 caracteres.");
  if (tursoUrl && aliasUrl && canonicalURL(tursoUrl) !== canonicalURL(aliasUrl))
    issues.push(
      "TURSO_DATABASE_URL e DATABASE_URL apontam para bancos diferentes. Mantenha apenas o par de variáveis do banco correto.",
    );
  if (
    requireRemote &&
    (!databaseUrl || !/^(libsql|https):\/\//.test(databaseUrl))
  )
    issues.push(
      "Defina TURSO_DATABASE_URL com a URL libsql:// ou HTTPS do banco remoto persistente.",
    );
  if ((requireRemote || databaseUrl) && !databaseAuthToken)
    issues.push(
      tursoUrl
        ? "Defina TURSO_AUTH_TOKEN para o banco de TURSO_DATABASE_URL."
        : "Defina DATABASE_AUTH_TOKEN para o banco de DATABASE_URL.",
    );
  if (issues.length)
    throw Object.assign(new Error(issues.join(" ")), {
      code: "BACKEND_CONFIGURATION_INVALID",
      issues,
    });
  return {
    databaseUrl,
    databaseAuthToken,
    databasePath: env.DATABASE_PATH || "./data/radio.sqlite",
    adminPassword: env.ADMIN_PASSWORD,
    secureCookies: requireRemote,
    trustProxy: vercel ? 1 : env.TRUST_PROXY || false,
    expectedDatabaseId: clean(env.EXPECTED_DATABASE_ID) || undefined,
    storageInfo: {
      mode: databaseUrl ? "remote" : "local",
      environment: env.VERCEL_ENV || env.NODE_ENV || "development",
      fingerprint: createHash("sha256")
        .update(
          databaseUrl
            ? canonicalURL(databaseUrl)
            : env.DATABASE_PATH || "./data/radio.sqlite",
        )
        .digest("hex")
        .slice(0, 16),
    },
  };
}
export const createRuntime = (env = process.env) =>
  createApp(runtimeOptions(env));
