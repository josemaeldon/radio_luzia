import test from "node:test";
import assert from "node:assert/strict";
import { createApp } from "../src/application.js";

test("admin protection, publication rules, persistence and native contract", async (t) => {
  const { app, db } = await createApp({
    databasePath: ":memory:",
    adminPassword: "test-password-long-enough",
  });
  const server = app.listen(0, "127.0.0.1");
  await new Promise((r) => server.once("listening", r));
  t.after(() => {
    server.close();
    db.close();
  });
  const base = `http://127.0.0.1:${server.address().port}`;
  let cookie = "",
    csrf = "";
  const request = (path, method = "GET", body, token = csrf) =>
    fetch(base + path, {
      method,
      headers: {
        "Content-Type": "application/json",
        Cookie: cookie,
        "X-CSRF-Token": token,
      },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
  assert.equal((await request("/api/admin/contents")).status, 401);
  assert.equal((await request("/api/v1/nowplaying")).status, 503);
  assert.equal(
    (await request("/api/admin/login", "POST", { password: "bad" })).status,
    401,
  );
  const login = await request("/api/admin/login", "POST", {
    password: "test-password-long-enough",
  });
  cookie = login.headers.get("set-cookie").split(";")[0];
  csrf = (await login.json()).csrf;
  assert.ok(cookie.includes("luzia_session="));
  const content = {
    title: "Reflexão",
    type: "audio",
    url: "https://example.com/audio.mp3",
    description: "Gravação própria",
    published: true,
    primary: true,
    rightsConfirmed: true,
  };
  assert.equal(
    (await request("/api/admin/contents", "POST", content, "bad")).status,
    403,
  );
  assert.equal(
    (
      await request("/api/admin/contents", "POST", {
        ...content,
        rightsConfirmed: false,
      })
    ).status,
    400,
  );
  assert.equal(
    (
      await request("/api/admin/contents", "POST", {
        ...content,
        url: "javascript:alert(1)",
      })
    ).status,
    400,
  );
  assert.equal(
    (
      await request("/api/admin/contents", "POST", {
        ...content,
        url: "http://example.com",
      })
    ).status,
    400,
  );
  assert.equal(
    (
      await request("/api/admin/contents", "POST", {
        ...content,
        type: "public_page",
      })
    ).status,
    400,
  );
  const firstResponse = await request("/api/admin/contents", "POST", content);
  assert.equal(firstResponse.status, 201);
  const first = await firstResponse.json();
  const second = await (
    await request("/api/admin/contents", "POST", {
      ...content,
      title: "Outra reflexão",
    })
  ).json();
  const draft = await (
    await request("/api/admin/contents", "POST", {
      ...content,
      title: "Não publicado",
      published: false,
      primary: false,
      rightsConfirmed: false,
    })
  ).json();
  const config = await (await request("/api/v1/config")).json();
  assert.equal(config.primary.id, second.id);
  assert.equal(config.contents.length, 2);
  assert.ok(!("rightsConfirmed" in config.contents[0]));
  const records = await (await request("/api/admin/contents")).json();
  assert.equal(records.find((c) => c.id === first.id).primary, false);
  assert.ok(records.some((c) => c.id === draft.id));
  const playing = await (await request("/api/v1/nowplaying")).json();
  assert.equal(playing.station.listen_url, content.url);
  assert.equal(playing.station.requests_enabled, false);
  assert.equal((await (await request("/api/v1/podcasts")).json()).length, 2);
  assert.equal(
    (await (await request(`/api/v1/podcast/${first.id}/episodes`)).json())[0]
      .links.download,
    content.url,
  );
  assert.equal(
    (await request(`/api/v1/podcast/${draft.id}/episodes`)).status,
    404,
  );
  assert.equal(
    (await request("/api/admin/contents/999", "PUT", content)).status,
    404,
  );
  assert.equal(
    (await request(`/api/admin/contents/${second.id}`, "DELETE")).status,
    204,
  );
  assert.equal((await request("/api/v1/nowplaying")).status, 503);
  assert.equal((await request("/api/admin/logout", "POST")).status, 204);
  assert.equal((await request("/api/admin/contents")).status, 401);
});

test("SQLite retains settings and contents after reopening", async (t) => {
  const { mkdtempSync, rmSync } = await import("node:fs");
  const { tmpdir } = await import("node:os");
  const { join } = await import("node:path");
  const dir = mkdtempSync(join(tmpdir(), "luzia espaço-"));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const options = {
    databasePath: join(dir, "radio.sqlite"),
    adminPassword: "another-test-password",
  };
  const first = await createApp(options);
  await first.db
    .prepare("UPDATE settings SET json=? WHERE id=1")
    .run(JSON.stringify({ stationName: "Nome persistido" }));
  await first.db
    .prepare(
      'INSERT INTO contents (title,type,url,description,published,"primary",rightsConfirmed,updatedAt) VALUES (?,?,?,?,?,?,?,?)',
    )
    .run(
      "Persistido",
      "audio",
      "https://example.com/a.mp3",
      "",
      1,
      1,
      1,
      new Date().toISOString(),
    );
  first.db.close();
  const second = await createApp(options);
  assert.equal(
    JSON.parse(
      (await second.db.prepare("SELECT json FROM settings").get()).json,
    ).stationName,
    "Nome persistido",
  );
  assert.equal(
    (await second.db.prepare("SELECT title FROM contents").get()).title,
    "Persistido",
  );
  second.db.close();
});

test("independent instances share sessions, contents and login limits", async (t) => {
  const { mkdtempSync, rmSync } = await import("node:fs");
  const { tmpdir } = await import("node:os");
  const { join } = await import("node:path");
  const dir = mkdtempSync(join(tmpdir(), "luzia-instances-"));
  const options = {
    databasePath: join(dir, "shared.sqlite"),
    adminPassword: "shared-admin-password",
    secureCookies: true,
  };
  const instances = [await createApp(options), await createApp(options)];
  const servers = instances.map(({ app }) => app.listen(0, "127.0.0.1"));
  await Promise.all(
    servers.map((s) => new Promise((r) => s.once("listening", r))),
  );
  t.after(async () => {
    await Promise.all(servers.map((s) => new Promise((r) => s.close(r))));
    instances.forEach(({ db }) => db.close());
    rmSync(dir, { recursive: true, force: true });
  });
  const base = servers.map((s) => `http://127.0.0.1:${s.address().port}`);
  const login = await fetch(base[0] + "/api/admin/login", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ password: options.adminPassword }),
  });
  assert.equal(login.status, 200);
  assert.match(login.headers.get("set-cookie"), /Secure/);
  const cookie = login.headers.get("set-cookie").split(";")[0],
    { csrf } = await login.json();
  const headers = {
    "Content-Type": "application/json",
    Cookie: cookie,
    "X-CSRF-Token": csrf,
  };
  const content = {
    title: "Compartilhado",
    type: "audio",
    url: "https://example.com/a.mp3",
    description: "",
    published: true,
    primary: true,
    rightsConfirmed: true,
  };
  const save = await fetch(base[1] + "/api/admin/contents", {
    method: "POST",
    headers,
    body: JSON.stringify(content),
  });
  assert.equal(save.status, 201);
  const config = await (await fetch(base[0] + "/api/v1/config")).json();
  assert.equal(config.primary.title, content.title);
  assert.equal(
    (await fetch(base[1] + "/api/admin/logout", { method: "POST", headers }))
      .status,
    204,
  );
  assert.equal(
    (await fetch(base[0] + "/api/admin/session", { headers })).status,
    401,
  );
  for (let i = 0; i < 9; i++) {
    const response = await fetch(base[i % 2] + "/api/admin/login", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ password: "wrong" }),
    });
    assert.equal(response.status, 401);
  }
  const limited = await fetch(base[1] + "/api/admin/login", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ password: "wrong" }),
  });
  assert.equal(limited.status, 429);
});

test("Vercel requires a remote database and uses secure cookies", async () => {
  const { runtimeOptions } = await import("../src/runtime.js");
  assert.throws(
    () =>
      runtimeOptions({ VERCEL: "1", ADMIN_PASSWORD: "a-valid-test-password" }),
    /TURSO_DATABASE_URL/,
  );
  assert.throws(
    () =>
      runtimeOptions({
        VERCEL: "1",
        TURSO_DATABASE_URL: "file:/tmp/radio.sqlite",
        TURSO_AUTH_TOKEN: "token",
      }),
    /TURSO_DATABASE_URL/,
  );
  const config = runtimeOptions({
    VERCEL: "1",
    TURSO_DATABASE_URL: "libsql://radio.example.com",
    TURSO_AUTH_TOKEN: "token",
    ADMIN_PASSWORD: "a-valid-test-password",
  });
  assert.equal(config.secureCookies, true);
  assert.equal(config.trustProxy, 1);
});

test("serverless entry exports an app, retries failed initialization and serves API and dashboard", async () => {
  const { execFile } = await import("node:child_process");
  const { promisify } = await import("node:util");
  const entry = new URL("../app.js", import.meta.url).href;
  const script = `
    import assert from 'node:assert/strict';
    import app from ${JSON.stringify(entry)};
    const server = app.listen(0, '127.0.0.1');
    await new Promise(r => server.once('listening', r));
    const base = 'http://127.0.0.1:' + server.address().port;
    const initialPage = await fetch(base);
    assert.equal(initialPage.status, 200);
    assert.match(await initialPage.text(), /Conteúdos do app/);
    assert.equal((await fetch(base + '/app.js')).status, 200);
    assert.equal((await fetch(base + '/style.css')).status, 200);
    const unavailable = await fetch(base + '/health');
    assert.equal(unavailable.status, 503);
    assert.equal(unavailable.headers.get('cache-control'), 'no-store');
    const diagnostic = await unavailable.json();
    assert.equal(diagnostic.code, 'BACKEND_CONFIGURATION_INVALID');
    assert.match(diagnostic.details.join(' '), /ADMIN_PASSWORD/);
    process.env.ADMIN_PASSWORD = 'serverless-test-password';
    process.env.DATABASE_URL = 'ftp://private-database-marker';
    const badDatabase = await fetch(base + '/health');
    assert.equal(badDatabase.status, 503);
    const databaseDiagnostic = await badDatabase.text();
    assert.match(databaseDiagnostic, /BACKEND_DATABASE_UNAVAILABLE/);
    assert.ok(!databaseDiagnostic.includes('private-database-marker'));
    process.env.DATABASE_URL = '';
    const health = await fetch(base + '/health');
    assert.equal(health.status, 200);
    assert.equal((await health.json()).status, 'ok');
    const page = await fetch(base);
    assert.equal(page.status, 200);
    assert.match(await page.text(), /Conteúdos do app/);
    assert.equal((await fetch(base + '/api/v1/config')).status, 200);
    server.close();
  `;
  await promisify(execFile)(
    process.execPath,
    ["--input-type=module", "-e", script],
    {
      env: {
        ...process.env,
        VERCEL: "0",
        ADMIN_PASSWORD: "",
        TURSO_DATABASE_URL: "",
        TURSO_AUTH_TOKEN: "",
        DATABASE_URL: "",
        DATABASE_AUTH_TOKEN: "",
        DATABASE_PATH: ":memory:",
      },
      timeout: 15000,
    },
  );
});

test('admin passwords accept ten characters and reject shorter values', async () => {
  const { runtimeOptions } = await import('../src/runtime.js');
  const validPassword = 'senha-1234';
  assert.equal(validPassword.length, 10);
  assert.equal(runtimeOptions({ ADMIN_PASSWORD: validPassword }).adminPassword, validPassword);
  assert.throws(() => runtimeOptions({ ADMIN_PASSWORD: 'senha-123' }), /10 caracteres/);
  await assert.rejects(createApp({ databasePath: ':memory:', adminPassword: 'senha-123' }), /10 caracteres/);
  const { app, db } = await createApp({ databasePath: ':memory:', adminPassword: validPassword });
  const server = app.listen(0, '127.0.0.1');
  await new Promise(resolve => server.once('listening', resolve));
  try {
    const response = await fetch(`http://127.0.0.1:${server.address().port}/api/admin/login`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ password: validPassword }),
    });
    assert.equal(response.status, 200);
  } finally { await new Promise(resolve => server.close(resolve)); db.close(); }
});
