import { createApp } from "./application.js";

export function runtimeOptions(env = process.env) {
  const vercel = env.VERCEL === "1";
  const databaseUrl = env.TURSO_DATABASE_URL || env.DATABASE_URL;
  const databaseAuthToken = env.TURSO_AUTH_TOKEN || env.DATABASE_AUTH_TOKEN;
  if (
    vercel &&
    (!databaseUrl ||
      !/^(libsql|https):\/\//.test(databaseUrl) ||
      !databaseAuthToken)
  ) {
    throw new Error(
      "Na Vercel, configure TURSO_DATABASE_URL (libsql:// ou HTTPS) e TURSO_AUTH_TOKEN. Banco local não é persistente.",
    );
  }
  return {
    databaseUrl,
    databaseAuthToken,
    databasePath: env.DATABASE_PATH || "./data/radio.sqlite",
    adminPassword: env.ADMIN_PASSWORD,
    secureCookies: vercel || env.NODE_ENV === "production",
    trustProxy: vercel ? 1 : env.TRUST_PROXY || false,
  };
}
export const createRuntime = (env = process.env) =>
  createApp(runtimeOptions(env));
