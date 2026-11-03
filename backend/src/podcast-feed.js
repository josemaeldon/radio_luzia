import https from "node:https";
import { lookup } from "node:dns";
import { isIP } from "node:net";
import { createHash } from "node:crypto";
import ipaddr from "ipaddr.js";
import { XMLParser } from "fast-xml-parser";

export function isPublicAddress(address) {
  try {
    let parsed = ipaddr.parse(address);
    if (parsed.kind() === "ipv6" && parsed.isIPv4MappedAddress())
      parsed = parsed.toIPv4Address();
    return parsed.range() === "unicast";
  } catch {
    return false;
  }
}
function publicURL(value) {
  const url = new URL(value);
  const host = url.hostname.replace(/^\[|\]$/g, "");
  if (
    url.protocol !== "https:" ||
    url.username ||
    url.password ||
    (isIP(host) && !isPublicAddress(host))
  )
    throw new Error("URL pública HTTPS obrigatória.");
  return url;
}

export function readPublicFeed(
  value,
  redirects = 0,
  deadline = Date.now() + 8000,
) {
  const url = publicURL(value);
  if (redirects > 3 || Date.now() >= deadline)
    return Promise.reject(new Error("Feed indisponível."));
  return new Promise((resolve, reject) => {
    // Return only validated DNS answers directly to the connection (no second lookup).
    const request = https.get(
      url,
      {
        headers: {
          Accept:
            "application/rss+xml, application/atom+xml, application/xml, text/xml",
          "Accept-Encoding": "identity",
        },
        lookup(host, options, callback) {
          lookup(host, { all: true }, (error, addresses) => {
            if (error) return callback(error);
            if (
              !addresses.length ||
              addresses.some(({ address }) => !isPublicAddress(address))
            )
              return callback(new Error("Endereço de feed não permitido."));
            if (options.all) callback(null, addresses);
            else callback(null, addresses[0].address, addresses[0].family);
          });
        },
      },
      (response) => {
        if (
          [301, 302, 303, 307, 308].includes(response.statusCode) &&
          response.headers.location
        ) {
          response.resume();
          Promise.resolve()
            .then(() =>
              readPublicFeed(
                new URL(response.headers.location, url).href,
                redirects + 1,
                deadline,
              ),
            )
            .then(resolve, reject);
          return;
        }
        if (response.statusCode !== 200) {
          response.resume();
          reject(new Error("Feed indisponível."));
          return;
        }
        const chunks = [];
        let size = 0;
        response.on("data", (chunk) => {
          size += chunk.length;
          if (size > 2 * 1024 * 1024) {
            response.destroy(new Error("Feed muito grande."));
            return;
          }
          chunks.push(chunk);
        });
        response.on("error", reject);
        response.on("end", () =>
          resolve(Buffer.concat(chunks).toString("utf8")),
        );
      },
    );
    const timer = setTimeout(
      () => request.destroy(new Error("Tempo de consulta do feed excedido.")),
      Math.max(1, deadline - Date.now()),
    );
    request.on("error", reject);
    request.on("close", () => clearTimeout(timer));
  });
}
const text = (value) =>
  typeof value === "object" && value !== null
    ? String(value["#text"] ?? "")
    : String(value ?? "");
const decode = (value) =>
  text(value).replace(
    /&(amp|quot|apos|lt|gt);/g,
    (_, entity) =>
      ({ amp: "&", quot: '"', apos: "'", lt: "<", gt: ">" })[entity],
  );
export function parsePodcastFeed(xml, content) {
  if (/<!DOCTYPE|<!ENTITY/i.test(xml))
    throw new Error("Declarações de entidade não são permitidas.");
  const parser = new XMLParser({
    ignoreAttributes: false,
    removeNSPrefix: true,
    parseTagValue: false,
    processEntities: false,
    isArray: (tag) => ["item", "entry", "enclosure", "link"].includes(tag),
  });
  const parsed = parser.parse(xml);
  const channel = parsed.rss?.channel ?? parsed.feed;
  if (!channel) throw new Error("Use um feed RSS ou Atom válido.");
  const entries = channel.item ?? channel.entry ?? [];
  const seen = new Set();
  return entries.slice(0, 500).flatMap((item) => {
    const enclosure =
      (item.enclosure ?? []).find(
        (e) => !e["@_type"] || e["@_type"].startsWith("audio/"),
      ) ??
      (item.link ?? []).find(
        (e) =>
          e["@_rel"] === "enclosure" &&
          (!e["@_type"] || e["@_type"].startsWith("audio/")),
      );
    const value = enclosure?.["@_url"] ?? enclosure?.["@_href"];
    if (!value) return [];
    let url;
    try {
      url = publicURL(new URL(decode(value), content.url).href).href;
    } catch {
      return [];
    }
    const key = decode(item.guid ?? item.id) || url;
    const id = `${content.id}-${createHash("sha256").update(key).digest("hex").slice(0, 24)}`;
    if (seen.has(id)) return [];
    seen.add(id);
    return [
      {
        id,
        title: decode(item.title) || content.title,
        description_short: decode(item.description ?? item.summary).slice(
          0,
          2000,
        ),
        art: null,
        links: { download: url },
      },
    ];
  });
}
