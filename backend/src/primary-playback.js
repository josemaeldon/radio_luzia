import { isPodcastContent, podcastEpisodes } from "./podcast-feed.js";

export function playbackUnavailable(message, statusCode = 503) {
  return Object.assign(new Error(message), {
    code: "PLAYBACK_UNAVAILABLE",
    statusCode,
  });
}
export async function resolvePrimaryPlayback(primary, stationName, feedReader) {
  if (!primary)
    throw playbackUnavailable("Nenhum conteúdo principal publicado.");
  let items;
  const podcast = isPodcastContent(primary);
  if (podcast) {
    let episodes;
    try {
      episodes = await podcastEpisodes(primary, feedReader);
    } catch {
      throw playbackUnavailable(
        "Não foi possível carregar os episódios do podcast principal.",
        502,
      );
    }
    items = episodes.map((episode) => ({
      id: episode.id,
      title: episode.title,
      url: episode.links.download,
    }));
  } else if (["audio", "stream"].includes(primary.type)) {
    items = [
      { id: String(primary.id), title: primary.title, url: primary.url },
    ];
  } else
    throw playbackUnavailable(
      "O conteúdo principal não fornece áudio reproduzível.",
    );
  if (!items.length)
    throw playbackUnavailable(
      "O podcast principal não possui episódios de áudio HTTPS disponíveis.",
    );
  return {
    contentId: String(primary.id),
    title: primary.title,
    stationName,
    type: podcast ? "podcast_feed" : primary.type,
    loop: podcast,
    items,
  };
}
