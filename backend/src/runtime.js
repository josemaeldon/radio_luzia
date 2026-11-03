import { createApp } from "./application.js";

export function runtimeOptions(env = process.env) {
  const vercel = env.VERCEL === "1";
  const databaseUrl = env.TURSO_DATABASE_URL || env.DATABASE_URL;
  const databaseAuthToken = env.TURSO_AUTH_TOKEN || env.DATABASE_AUTH_TOKEN;
  const issues = [];
  if (!env.ADMIN_PASSWORD || env.ADMIN_PASSWORD.length < 10) {
    issues.push("Defina ADMIN_PASSWORD com pelo menos 10 caracteres.");
  }
  if (vercel && (!databaseUrl || !/^(libsql|https):\/\//.test(databaseUrl))) {
    issues.push(
      "Defina TURSO_DATABASE_URL com a URL libsql:// ou HTTPS do banco remoto.",
    );
  }
  if (vercel && !databaseAuthToken) {
    issues.push("Defina TURSO_AUTH_TOKEN com um token válido do banco.");
  }
  if (issues.length) {
    const error = new Error(issues.join(" "));
    error.code = "BACKEND_CONFIGURATION_INVALID";
    error.issues = issues;
    throw error;
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
