import express from "express";
import helmet from "helmet";
import { rateLimit } from "express-rate-limit";
import { openDatabase, DatabaseRateLimitStore } from "./database.js";
import {
  randomBytes,
  scryptSync,
  timingSafeEqual,
  createHash,
} from "node:crypto";
import { fileURLToPath } from "node:url";
import { z } from "zod";

const httpsUrl = z
  .string()
  .max(2048)
  .url()
  .refine((value) => {
    const u = new URL(value);
    return u.protocol === "https:" && !u.username && !u.password;
  }, "Use uma URL HTTPS sem credenciais.");
const contentSchema = z
  .object({
    title: z.string().trim().min(1).max(150),
    type: z.enum(["stream", "audio", "public_page", "podcast_feed"]),
    url: httpsUrl,
    description: z.string().trim().max(2000).default(""),
    published: z.boolean(),
    primary: z.boolean(),
    rightsConfirmed: z.boolean(),
  })
  .strict()
  .superRefine((value, ctx) => {
    if (value.published && !value.rightsConfirmed)
      ctx.addIssue({
        code: "custom",
        message: "Confirme os direitos antes de publicar.",
      });
    if (
      value.primary &&
      (!value.published || !["stream", "audio"].includes(value.type))
    )
      ctx.addIssue({
        code: "custom",
        message:
          "A reprodução principal deve ser um áudio ou transmissão publicado.",
      });
  });
const settingsSchema = z
  .object({
    stationName: z.string().trim().min(1).max(150),
    azuracastUrl: httpsUrl,
    stationId: z.string().regex(/^[a-zA-Z0-9_-]{1,80}$/),
    recordedOnly: z.boolean(),
  })
  .strict();
const hash = (value) => createHash("sha256").update(value).digest("hex");
const mapRow = (row) =>
  row && {
    ...row,
    published: !!row.published,
    primary: !!row.primary,
    rightsConfirmed: !!row.rightsConfirmed,
  };

export async function createApp({
  databasePath = "./data/radio.sqlite",
  databaseUrl,
  databaseAuthToken,
  adminPassword,
  secureCookies = false,
  trustProxy = false,
} = {}) {
  if (!adminPassword || adminPassword.length < 10)
    throw new Error("Defina ADMIN_PASSWORD com pelo menos 10 caracteres.");
  const db = await openDatabase({
    databasePath,
    databaseUrl,
    databaseAuthToken,
  });
  await db.exec(`CREATE TABLE IF NOT EXISTS contents (id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT NOT NULL, type TEXT NOT NULL, url TEXT NOT NULL, description TEXT NOT NULL, published INTEGER NOT NULL, "primary" INTEGER NOT NULL, rightsConfirmed INTEGER NOT NULL, updatedAt TEXT NOT NULL);
    CREATE UNIQUE INDEX IF NOT EXISTS single_primary ON contents("primary") WHERE "primary" = 1;
    CREATE TABLE IF NOT EXISTS settings (id INTEGER PRIMARY KEY CHECK(id=1), json TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS sessions (token TEXT PRIMARY KEY, csrf TEXT NOT NULL, expires INTEGER NOT NULL);
    CREATE TABLE IF NOT EXISTS rate_limits (key TEXT PRIMARY KEY, hits INTEGER NOT NULL, resetAt INTEGER NOT NULL);`);
  await db.prepare("INSERT OR IGNORE INTO settings VALUES (1, ?)").run(
    JSON.stringify({
      stationName: "Rádio Santa Luzia",
      azuracastUrl: "https://webradio.cloudbr.app",
      stationId: "2",
      recordedOnly: true,
    }),
  );
  const salt = randomBytes(16);
  const passwordHash = scryptSync(adminPassword, salt, 64);
  const settings = async () =>
    JSON.parse(
      (await db.prepare("SELECT json FROM settings WHERE id=1").get()).json,
    );
  const list = async () =>
    (await db.prepare("SELECT * FROM contents ORDER BY id DESC").all()).map(
      mapRow,
    );
  const app = express();
  app.disable("x-powered-by");
  app.set("trust proxy", trustProxy);
  app.use(
    helmet({ strictTransportSecurity: secureCookies ? undefined : false }),
  );
  app.use(express.json({ limit: "32kb" }));
  app.use(
    "/api",
    rateLimit({
      windowMs: 60_000,
      limit: 180,
      standardHeaders: "draft-8",
      legacyHeaders: false,
      store: new DatabaseRateLimitStore(db, "api:"),
    }),
  );
  app.use("/api/admin", (_req, res, next) => {
    res.set("Cache-Control", "no-store");
    next();
  });
  const cookieOptions = {
    httpOnly: true,
    sameSite: "strict",
    secure: secureCookies,
    path: "/api/admin",
    maxAge: 8 * 60 * 60 * 1000,
  };
  const auth = async (req, res, next) => {
    const token = req.headers.cookie
      ?.split(";")
      .map((s) => s.trim())
      .find((s) => s.startsWith("luzia_session="))
      ?.slice(14);
    const session =
      token &&
      (await db
        .prepare("SELECT * FROM sessions WHERE token=? AND expires>?")
        .get(hash(token), Date.now()));
    if (!session)
      return res.status(401).json({ error: "Entre no painel para continuar." });
    if (
      !["GET", "HEAD"].includes(req.method) &&
      req.get("X-CSRF-Token") !== session.csrf
    )
      return res
        .status(403)
        .json({ error: "Sessão inválida. Recarregue o painel." });
    req.session = session;
    next();
  };
  app.post(
    "/api/admin/login",
    rateLimit({
      windowMs: 15 * 60_000,
      limit: 10,
      store: new DatabaseRateLimitStore(db, "login:"),
    }),
    async (req, res) => {
      const password = req.body?.password;
      if (
        typeof password !== "string" ||
        password.length > 1024 ||
        !timingSafeEqual(passwordHash, scryptSync(password, salt, 64))
      )
        return res.status(401).json({ error: "Senha incorreta." });
      await db.batch([
        { sql: "DELETE FROM sessions WHERE expires<?", args: [Date.now()] },
        { sql: "DELETE FROM rate_limits WHERE resetAt<?", args: [Date.now()] },
      ]);
      const token = randomBytes(32).toString("hex"),
        csrf = randomBytes(24).toString("hex");
      await db
        .prepare("INSERT INTO sessions VALUES (?, ?, ?)")
        .run(hash(token), csrf, Date.now() + cookieOptions.maxAge);
      res.cookie("luzia_session", token, cookieOptions).json({ csrf });
    },
  );
  app.get("/api/admin/session", auth, (req, res) =>
    res.json({ csrf: req.session.csrf }),
  );
  app.post("/api/admin/logout", auth, async (req, res) => {
    await db
      .prepare("DELETE FROM sessions WHERE token=?")
      .run(req.session.token);
    res.clearCookie("luzia_session", cookieOptions).sendStatus(204);
  });
  app.get("/api/admin/contents", auth, async (_req, res) =>
    res.json(await list()),
  );
  const save = db.transaction(async (tx, id, content) => {
    if (id && !(await tx.prepare("SELECT id FROM contents WHERE id=?").get(id)))
      return null;
    if (content.primary)
      await tx.prepare('UPDATE contents SET "primary"=0').run();
    const values = [
      content.title,
      content.type,
      content.url,
      content.description,
      +content.published,
      +content.primary,
      +content.rightsConfirmed,
      new Date().toISOString(),
    ];
    if (id)
      await tx
        .prepare(
          'UPDATE contents SET title=?, type=?, url=?, description=?, published=?, "primary"=?, rightsConfirmed=?, updatedAt=? WHERE id=?',
        )
        .run(...values, id);
    else
      id = Number(
        (
          await tx
            .prepare(
              'INSERT INTO contents (title,type,url,description,published,"primary",rightsConfirmed,updatedAt) VALUES (?,?,?,?,?,?,?,?)',
            )
            .run(...values)
        ).lastInsertRowid,
      );
    return mapRow(
      await tx.prepare("SELECT * FROM contents WHERE id=?").get(id),
    );
  });
  const write = async (req, res) => {
    const parsed = contentSchema.safeParse(req.body);
    if (!parsed.success)
      return res
        .status(400)
        .json({ error: parsed.error.issues.map((i) => i.message).join(" ") });
    const result = await save(
      req.params.id ? Number(req.params.id) : null,
      parsed.data,
    );
    if (!result)
      return res.status(404).json({ error: "Conteúdo não encontrado." });
    res.status(req.params.id ? 200 : 201).json(result);
  };
  app.post("/api/admin/contents", auth, write);
  app.put("/api/admin/contents/:id", auth, write);
  app.delete("/api/admin/contents/:id", auth, async (req, res) => {
    if (
      !(
        await db
          .prepare("DELETE FROM contents WHERE id=?")
          .run(Number(req.params.id))
      ).changes
    )
      return res.status(404).json({ error: "Conteúdo não encontrado." });
    res.sendStatus(204);
  });
  app.get("/api/admin/settings", auth, async (_req, res) =>
    res.json(await settings()),
  );
  app.put("/api/admin/settings", auth, async (req, res) => {
    const parsed = settingsSchema.safeParse(req.body);
    if (!parsed.success)
      return res.status(400).json({
        error: "Confira o nome, URL HTTPS e identificador da estação.",
      });
    await db
      .prepare("UPDATE settings SET json=? WHERE id=1")
      .run(JSON.stringify(parsed.data));
    res.json(parsed.data);
  });
  app.get("/api/v1/config", async (_req, res) => {
    const publicContents = (await list())
      .filter((c) => c.published)
      .map(({ rightsConfirmed, ...c }) => c);
    res.set("Cache-Control", "no-store").json({
      version: 1,
      ...(await settings()),
      primary: publicContents.find((c) => c.primary) ?? null,
      contents: publicContents,
    });
  });
  // Compatibility payloads let the existing native players use managed audio
  // without treating HTML pages or RSS feeds as AVPlayer/ExoPlayer media.
  app.get("/api/v1/nowplaying", async (_req, res) => {
    const config = await settings(),
      published = (await list()).filter((c) => c.published);
    const primary = published.find((c) => c.primary);
    res.set("Cache-Control", "no-store");
    if (!primary)
      return res
        .status(503)
        .json({ error: "Nenhum áudio principal publicado." });
    const listeners = { total: 0, unique: 0, current: 0 };
    const playable = [primary];
    res.json({
      station: {
        id: 1,
        name: config.stationName,
        shortcode: config.stationId,
        description: primary.description,
        timezone: "America/Belem",
        listen_url: primary.url,
        public_player_url:
          published.find((c) => c.type === "public_page")?.url ?? null,
        requests_enabled: false,
        mounts: playable.map((c) => ({
          id: c.id,
          name: c.title,
          url: c.url,
          bitrate: 0,
          format: c.type === "audio" ? "audio" : "stream",
          listeners,
          is_default: c.primary,
        })),
      },
      listeners,
      live: {
        is_live: false,
        streamer_name: "",
        broadcast_start: null,
        art: null,
      },
      now_playing: {
        sh_id: primary.id,
        played_at: null,
        duration: 0,
        elapsed: 0,
        remaining: 0,
        playlist: "",
        streamer: "",
        is_request: false,
        song: {
          id: String(primary.id),
          text: primary.title,
          title: primary.title,
          artist: config.stationName,
          album: "",
          art: null,
          genre: "",
          isrc: "",
          lyrics: "",
          custom_fields: {},
        },
      },
      playing_next: null,
      song_history: [],
      is_online: true,
    });
  });
  app.get("/api/v1/podcasts", async (_req, res) =>
    res.set("Cache-Control", "no-store").json(
      (await list())
        .filter((c) => c.published && c.type === "audio")
        .map((c) => ({
          id: String(c.id),
          title: c.title,
          description_short: c.description,
          art: null,
          links: { public_feed: null },
        })),
    ),
  );
  app.get("/api/v1/podcast/:id/episodes", async (req, res) => {
    const content = (await list()).find(
      (c) =>
        String(c.id) === req.params.id && c.published && c.type === "audio",
    );
    if (!content)
      return res.status(404).json({ error: "Áudio não encontrado." });
    res.set("Cache-Control", "no-store").json([
      {
        id: String(content.id),
        title: content.title,
        description: content.description,
        publish_at: 0,
        duration: 0,
        links: { download: content.url },
      },
    ]);
  });
  app.get("/health", (_req, res) => res.json({ status: "ok" }));
  app.use(express.static(fileURLToPath(new URL("../public", import.meta.url))));
  app.use("/api", (_req, res) =>
    res.status(404).json({ error: "Endpoint não encontrado." }),
  );
  app.use((error, _req, res, _next) => {
    res
      .status(
        error.type === "entity.too.large"
          ? 413
          : error instanceof SyntaxError
            ? 400
            : 500,
      )
      .json({ error: "Não foi possível processar a solicitação." });
  });
  return { app, db };
}
