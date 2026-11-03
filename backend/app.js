import express from "express";
import helmet from "helmet";
import { fileURLToPath } from "node:url";
import { createRuntime } from "./src/runtime.js";

export function createServerlessApp({
  initialize = () =>
    createRuntime({ ...process.env, REQUIRE_REMOTE_DATABASE: "true" }),
} = {}) {
  const app = express();
  app.disable("x-powered-by");
  app.use(
    helmet({
      strictTransportSecurity:
        process.env.VERCEL === "1" || process.env.NODE_ENV === "production"
          ? undefined
          : false,
    }),
  );
  // Serve the dashboard even if configuration/database initialization fails.
  // Explicit file routes also support Vercel's handling of the root index.
  const indexFile = fileURLToPath(
    new URL("./public/index.html", import.meta.url),
  );
  const scriptFile = fileURLToPath(new URL("./public/app.js", import.meta.url));
  const styleFile = fileURLToPath(
    new URL("./public/style.css", import.meta.url),
  );
  for (const [route, file] of [
    ["/", indexFile],
    ["/index.html", indexFile],
    ["/app.js", scriptFile],
    ["/style.css", styleFile],
  ]) {
    app.get(route, (_req, res) => res.sendFile(file));
  }
  let initialized;
  app.use(async (req, res, next) => {
    try {
      initialized ??= initialize().catch((error) => {
        initialized = undefined;
        throw error;
      });
      const runtime = await initialized;
      runtime.app(req, res, next);
    } catch (error) {
      next(error);
    }
  });
  app.use((error, _req, res, _next) => {
    const configurationError = error.code === "BACKEND_CONFIGURATION_INVALID";
    const code = configurationError
      ? error.code
      : "BACKEND_DATABASE_UNAVAILABLE";
    // Log only controlled diagnostics; driver messages may contain URLs/secrets.
    console.error(
      JSON.stringify({
        event: "backend_initialization_failed",
        code,
        ...(configurationError
          ? { issues: error.issues }
          : {
              databaseCode: /^[A-Z0-9_]{1,60}$/.test(error.code || "")
                ? error.code
                : "UNKNOWN",
            }),
      }),
    );
    res
      .set("Cache-Control", "no-store")
      .status(503)
      .json({
        code,
        error: configurationError
          ? "Configuração incompleta. Confira as variáveis de ambiente de Production na Vercel e faça um novo deploy."
          : "Não foi possível conectar ao banco. Confira a URL, o token e se o banco é compatível com libSQL.",
        ...(configurationError ? { details: error.issues } : {}),
      });
  });
  return app;
}
export default createServerlessApp();
