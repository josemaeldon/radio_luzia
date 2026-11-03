import test from "node:test";
import assert from "node:assert/strict";
import {
  parsePodcastFeed,
  isPublicAddress,
  readPublicFeed,
} from "../src/podcast-feed.js";
import { createApp } from "../src/application.js";

const rss = (url) =>
  `<?xml version="1.0"?><rss version="2.0"><channel><title>Reflexões</title><item><guid>episode-stable</guid><title>Fé &amp; comunidade</title><enclosure url="${url}" type="audio/mpeg"/></item><item><guid>video</guid><enclosure url="https://example.com/video.mp4" type="video/mp4"/></item><item><guid>http</guid><enclosure url="http://example.com/audio.mp3" type="audio/mpeg"/></item></channel></rss>`;
const content = {
  id: 10,
  title: "Podcast",
  url: "https://example.com/feed.xml",
};

test("RSS and Atom return only HTTPS audio and keep stable episode IDs", () => {
  const initial = parsePodcastFeed(
    rss("https://example.com/one.mp3?a=1&amp;b=2"),
    content,
  );
  assert.equal(initial.length, 1);
  assert.equal(initial[0].title, "Fé & comunidade");
  assert.equal(
    initial[0].links.download,
    "https://example.com/one.mp3?a=1&b=2",
  );
  const changed = parsePodcastFeed(rss("https://example.com/two.mp3"), content);
  assert.equal(initial[0].id, changed[0].id);
  assert.equal(changed[0].links.download, "https://example.com/two.mp3");
  const atom = parsePodcastFeed(
    '<feed xmlns="http://www.w3.org/2005/Atom"><entry><id>stable</id><title>Episódio</title><link rel="enclosure" type="audio/mp4" href="https://example.com/a.m4a"/></entry></feed>',
    content,
  );
  assert.equal(atom.length, 1);
  assert.throws(() => parsePodcastFeed("<html>Não é RSS</html>", content));
  assert.throws(() =>
    parsePodcastFeed('<!DOCTYPE rss [<!ENTITY x "hello">]><rss/>', content),
  );
});

test("feed fetcher refuses private networks, mapped IPs, and non-HTTPS sources", () => {
  for (const address of [
    "127.0.0.1",
    "10.1.1.1",
    "169.254.169.254",
    "192.168.0.1",
    "::1",
    "fc00::1",
    "::ffff:127.0.0.1",
  ])
    assert.equal(isPublicAddress(address), false, address);
  assert.equal(isPublicAddress("8.8.8.8"), true);
  for (const url of [
    "https://127.0.0.1/feed",
    "https://[::1]/feed",
    "http://example.com/feed",
    "file:///etc/passwd",
  ])
    assert.throws(() => readPublicFeed(url));
});

test("published feeds populate the native catalog and stop resolving after unpublication", async (t) => {
  let feed = rss("https://example.com/one.mp3");
  const { app, db } = await createApp({
    databasePath: ":memory:",
    adminPassword: "test-feed-password",
    feedReader: async () => feed,
  });
  const server = app.listen(0, "127.0.0.1");
  await new Promise((r) => server.once("listening", r));
  t.after(async () => {
    await new Promise((r) => server.close(r));
    db.close();
  });
  const base = `http://127.0.0.1:${server.address().port}`;
  const login = await fetch(base + "/api/admin/login", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ password: "test-feed-password" }),
  });
  const headers = {
    "Content-Type": "application/json",
    Cookie: login.headers.get("set-cookie").split(";")[0],
    "X-CSRF-Token": (await login.json()).csrf,
  };
  const data = {
    title: "Podcast da paróquia",
    type: "podcast_feed",
    url: "https://example.com/feed.xml",
    description: "",
    published: true,
    primary: false,
    rightsConfirmed: true,
  };
  const created = await fetch(base + "/api/admin/contents", {
    method: "POST",
    headers,
    body: JSON.stringify(data),
  });
  assert.equal(created.status, 201);
  const record = await created.json();
  const catalog = await (await fetch(base + "/api/v1/podcasts")).json();
  assert.equal(catalog[0].id, String(record.id));
  const path = `/api/v1/podcast/${record.id}/episodes`;
  const episodes = await (await fetch(base + path)).json();
  assert.equal(episodes.length, 1);
  feed = rss("https://example.com/two.mp3");
  const changed = await (await fetch(base + path)).json();
  assert.equal(changed[0].id, episodes[0].id);
  assert.equal(changed[0].links.download, "https://example.com/two.mp3");
  feed = "<html>Erro</html>";
  assert.equal((await fetch(base + path)).status, 502);
  await fetch(base + `/api/admin/contents/${record.id}`, {
    method: "PUT",
    headers,
    body: JSON.stringify({ ...data, published: false }),
  });
  assert.equal((await fetch(base + path)).status, 404);
  assert.equal(
    (await (await fetch(base + "/api/v1/podcasts")).json()).length,
    0,
  );
});

test("AzuraCast public podcast pages resolve to RSS feeds", async () => {
  const { azuraPodcastFeedURL } = await import("../src/podcast-feed.js");
  for (const part of ["podcast", "podcasts"]) {
    assert.equal(
      azuraPodcastFeedURL(
        `https://example.com/public/station/${part}/podcast-id`,
      ),
      "https://example.com/public/station/podcast/podcast-id/feed",
    );
  }
  assert.equal(
    azuraPodcastFeedURL(
      "https://example.com/azura/public/2/podcasts/id/?lang=pt#episodes",
    ),
    "https://example.com/azura/public/2/podcast/id/feed?lang=pt",
  );
  assert.equal(azuraPodcastFeedURL("https://example.com/public/station"), null);
});

test("podcast pages can be primary, expose an audio-only circular queue and stop when empty", async (t) => {
  const queried = [];
  let xml =
    '<rss><channel><item><guid>one</guid><title>Primeiro</title><enclosure url="https://example.com/one.mp3" type="audio/mpeg"/></item><item><guid>two</guid><title>Segundo</title><enclosure url="https://example.com/two.mp3" type="audio/mpeg"/></item></channel></rss>';
  const { app, db } = await createApp({
    databasePath: ":memory:",
    adminPassword: "primary-podcast-test",
    feedReader: async (url) => {
      queried.push(url);
      return xml;
    },
  });
  const server = app.listen(0, "127.0.0.1");
  await new Promise((r) => server.once("listening", r));
  t.after(async () => {
    await new Promise((r) => server.close(r));
    db.close();
  });
  const base = `http://127.0.0.1:${server.address().port}`;
  const login = await fetch(base + "/api/admin/login", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ password: "primary-podcast-test" }),
  });
  const headers = {
    "Content-Type": "application/json",
    Cookie: login.headers.get("set-cookie").split(";")[0],
    "X-CSRF-Token": (await login.json()).csrf,
  };
  const content = {
    title: "Série",
    type: "public_page",
    url: "https://example.com/public/station/podcasts/podcast-id",
    description: "",
    published: true,
    primary: true,
    rightsConfirmed: true,
  };
  const saved = await fetch(base + "/api/admin/contents", {
    method: "POST",
    headers,
    body: JSON.stringify(content),
  });
  assert.equal(saved.status, 201);
  const row = await saved.json();
  assert.equal(row.type, "podcast_feed");
  assert.equal(row.primary, true);
  const queueResponse = await fetch(base + "/api/v1/playback");
  assert.equal(queueResponse.status, 200);
  const queue = await queueResponse.json();
  assert.equal(queue.loop, true);
  assert.equal(queue.contentId, String(row.id));
  assert.deepEqual(
    queue.items.map((item) => item.url),
    ["https://example.com/one.mp3", "https://example.com/two.mp3"],
  );
  assert.ok(
    queried.every(
      (url) =>
        url === "https://example.com/public/station/podcast/podcast-id/feed",
    ),
  );
  const playing = await (await fetch(base + "/api/v1/nowplaying")).json();
  assert.equal(playing.station.listen_url, queue.items[0].url);
  assert.deepEqual(playing.playback, queue);
  assert.equal(
    (await (await fetch(base + `/api/v1/podcast/${row.id}/episodes`)).json())
      .length,
    2,
  );
  xml = "<rss><channel/></rss>";
  assert.equal((await fetch(base + "/api/v1/playback")).status, 503);
  assert.equal((await fetch(base + "/api/v1/nowplaying")).status, 503);
  await fetch(base + `/api/admin/contents/${row.id}`, {
    method: "PUT",
    headers,
    body: JSON.stringify({
      ...content,
      type: "podcast_feed",
      primary: false,
      published: false,
    }),
  });
  assert.equal((await fetch(base + "/api/v1/playback")).status, 503);
});

test('the playback feed does not silently truncate published episodes', () => {
  const entries=Array.from({length:501},(_,i)=>`<item><guid>${i}</guid><title>Episódio ${i}</title><enclosure url="https://example.com/${i}.mp3" type="audio/mpeg"/></item>`).join('');
  assert.equal(parsePodcastFeed(`<rss><channel>${entries}</channel></rss>`,content).length,501);
});
