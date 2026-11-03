import express from "express";
import { createRuntime } from "./src/runtime.js";

// Native Vercel Express entry point; no port listener or writable local files.
const app = express();
let initialized;
app.use(async (req, res, next) => {
  try {
    initialized ??= createRuntime().catch((error) => {
      initialized = undefined;
      throw error;
    });
    const runtime = await initialized;
    runtime.app(req, res, next);
  } catch (error) {
    next(error);
  }
});
app.use((_error, _req, res, _next) =>
  res
    .status(503)
    .json({
      error:
        "Backend indisponível. Confira as variáveis de ambiente e a conexão com o banco.",
    }),
);
export default app;
