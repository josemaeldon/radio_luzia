import { mkdirSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

// The HTTP client is used for deployed databases; local files remain supported.
export async function openDatabase({
  databaseUrl,
  databasePath = "./data/radio.sqlite",
  databaseAuthToken,
} = {}) {
  let client;
  if (
    databaseUrl &&
    !databaseUrl.startsWith("file:") &&
    databaseUrl !== ":memory:"
  ) {
    const url = new URL(databaseUrl);
    if (!["https:", "libsql:"].includes(url.protocol))
      throw new Error("DATABASE_URL deve usar libsql:// ou HTTPS.");
    const { createClient } = await import("@libsql/client/web");
    client = createClient({ url: databaseUrl, authToken: databaseAuthToken });
  } else {
    let url =
      databaseUrl ||
      (databasePath === ":memory:"
        ? ":memory:"
        : `file:${resolve(databasePath)}`);
    if (url.startsWith("file:")) {
      const filename = url.startsWith("file://")
        ? fileURLToPath(url)
        : resolve(url.slice(5));
      mkdirSync(dirname(filename), { recursive: true });
      url = pathToFileURL(filename).href;
    }
    const { createClient } = await import("@libsql/client");
    client = createClient({ url });
  }
  function wrap(connection) {
    return {
      prepare(sql) {
        const execute = (args) => connection.execute({ sql, args });
        return {
          async get(...args) {
            return (await execute(args)).rows[0];
          },
          async all(...args) {
            return (await execute(args)).rows;
          },
          async run(...args) {
            const result = await execute(args);
            return {
              changes: result.rowsAffected,
              lastInsertRowid: result.lastInsertRowid,
            };
          },
        };
      },
      async exec(sql) {
        await connection.executeMultiple(sql);
      },
      async batch(statements) {
        return connection.batch(statements, "write");
      },
      transaction(callback) {
        return async (...args) => {
          const tx = await connection.transaction("write");
          try {
            const value = await callback(wrap(tx), ...args);
            await tx.commit();
            return value;
          } catch (error) {
            if (!tx.closed) await tx.rollback();
            throw error;
          } finally {
            tx.close();
          }
        };
      },
      close() {
        connection.close();
      },
    };
  }
  return wrap(client);
}

// Atomic counters shared by all function instances, with no background timers.
export class DatabaseRateLimitStore {
  localKeys = false;
  constructor(db, prefix) {
    this.db = db;
    this.prefix = prefix;
  }
  init({ windowMs }) {
    this.windowMs = windowMs;
  }
  async increment(key) {
    const now = Date.now();
    const row = await this.db
      .prepare(
        `INSERT INTO rate_limits (key, hits, resetAt) VALUES (?, 1, ?)
      ON CONFLICT(key) DO UPDATE SET hits=CASE WHEN resetAt<=? THEN 1 ELSE hits+1 END,
      resetAt=CASE WHEN resetAt<=? THEN excluded.resetAt ELSE resetAt END RETURNING hits, resetAt`,
      )
      .get(this.prefix + key, now + this.windowMs, now, now);
    return {
      totalHits: Number(row.hits),
      resetTime: new Date(Number(row.resetAt)),
    };
  }
  async decrement(key) {
    await this.db
      .prepare("UPDATE rate_limits SET hits=MAX(0,hits-1) WHERE key=?")
      .run(this.prefix + key);
  }
  async resetKey(key) {
    await this.db
      .prepare("DELETE FROM rate_limits WHERE key=?")
      .run(this.prefix + key);
  }
}
