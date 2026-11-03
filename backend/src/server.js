import { createRuntime } from "./runtime.js";
const { app, db } = await createRuntime();
const server = app.listen(
  Number(process.env.PORT || 3000),
  process.env.HOST || "127.0.0.1",
  () => console.log(`Painel disponível na porta ${process.env.PORT || 3000}`),
);
for (const signal of ["SIGTERM", "SIGINT"])
  process.on(signal, () =>
    server.close(() => {
      db.close();
      process.exit(0);
    }),
  );
