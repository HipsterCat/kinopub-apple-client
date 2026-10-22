/**
 * GET /v1/title/by/kinopub/{id}/seasons/2-4
 *     /v1/title/by/kinopub/{id}/seasons/2,3,4
 *     /v1/title/by/kinopub/{id}/seasons/2&3&4
 *
 * The screen only needs the season you're in and the one beside it, not all
 * sixty. At most four. Language is Accept-Language: the payload carries that
 * language alone. A Russian viewer does not get the English title beside it.
 *
 * IMDb is { value, votes } when we have it, never a bare score. Skip markers
 * are booleans (tvoe has an intro / has credits), not the timestamps — those
 * stay on the source you ask when playback actually starts. runtime_min comes
 * from TMDB when the catalogue row doesn't have a duration yet.
 */

import { preferredLang, readDocument, writeDocument } from "./title.js";

const MAX_SEASONS = 4;
const HINT = "/v1/title/by/kinopub/{id}/seasons/2-4";
const IMAGE_BASE = "https://image.tmdb.org/t/p/original";

export async function handleSeasons(request, env) {
  const url = new URL(request.url);
  const match = url.pathname.match(/^\/v1\/title\/by\/kinopub\/(\d+)\/seasons\/([^/]+)$/);
  if (!match) return json({ error: "bad_request", hint: HINT }, 400);

  const id = match[1];
  const numbers = parseSeasonSpec(decodeURIComponent(match[2]));
  if (!numbers) return json({ error: "bad_request", hint: HINT }, 400);

  const lang = preferredLang(request);
  const stored = await readDocument(env, id);
  if (!stored) return json({ error: "not_found", hint: "title is not warmed yet" }, 404);

  const document = await fillSeasons(env, stored, numbers, lang);
  if (document !== stored) await writeDocument(env, id, document);

  const seasons = numbers.map((number) => projectSeason(document, number, lang, id));
  const any = seasons.some((season) => season.name || season.overview || season.episodes.length);
  if (!any) return json({ error: "not_found", hint: "no season data" }, 404);

  return json({ id, lang, seasons }, 200, { Vary: "Accept-Language" });
}

export function parseSeasonSpec(spec) {
  const text = String(spec || "").trim().replaceAll("&", ",");
  if (!text || text.length > 32) return null;
  let numbers = null;
  if (/^\d+$/.test(text)) numbers = [Number(text)];
  else if (/^\d+-\d+$/.test(text)) {
    const [start, end] = text.split("-").map(Number);
    if (end < start) return null;
    numbers = [];
    for (let n = start; n <= end; n++) numbers.push(n);
  } else if (/^\d+(,\d+)+$/.test(text)) {
    numbers = text.split(",").map(Number);
  }
  if (!numbers || numbers.length === 0 || numbers.length > MAX_SEASONS) return null;
  if (numbers.some((n) => n > 200)) return null;
  if (new Set(numbers).size !== numbers.length) return null;
  return numbers;
}

async function fillSeasons(env, document, numbers, lang) {
  const tvId = tmdbTvId(document);
  if (!tvId || !env.TMDB_READ_TOKEN) return document;
  const missing = numbers.filter((number) => !hasLang(document, number, lang));
  if (!missing.length) return document;

  let next = document;
  for (const number of missing) {
    let payload = null;
    try {
      payload = await fetchSeason(env, tvId, number, lang);
    } catch {
      payload = null;
    }
    if (!payload) continue;
    next = mergeSeason(next, number, lang, payload);
  }
  return next;
}

function hasLang(document, number, lang) {
  const season = findSeason(document, number);
  return Boolean(season?.fetched_langs?.includes(lang));
}

function tmdbTvId(document) {
  const value = document?.ids?.tmdb?.value || "";
  const match = /^tv\/(\d+)$/.exec(String(value));
  return match ? match[1] : null;
}

async function fetchSeason(env, tvId, number, lang) {
  const language = lang === "en" ? "en-US" : "ru-RU";
  const url = `https://api.themoviedb.org/3/tv/${tvId}/season/${number}?language=${language}`;
  const response = await fetch(url, {
    headers: {
      Accept: "application/json",
      Authorization: `Bearer ${env.TMDB_READ_TOKEN}`,
    },
  });
  return response.ok ? await response.json() : null;
}

function mergeSeason(document, number, lang, payload) {
  const seasons = [...(document.seasons || [])];
  const index = seasons.findIndex((season) => Number(season.number) === number);
  const previous = index >= 0 ? seasons[index] : { number, episodes: [] };
  const episodes = (payload.episodes || []).map((episode) => mergeEpisode(
    (previous.episodes || []).find((item) => Number(item.number) === episode.episode_number),
    episode,
    lang,
  ));
  const fetched = new Set(previous.fetched_langs || []);
  fetched.add(lang);
  const next = {
    ...previous,
    number,
    name: mergeLangText(previous.name, lang, clean(payload.name)),
    overview: mergeLangText(previous.synopsis ?? previous.overview, lang, clean(payload.overview)),
    episodes,
    fetched_langs: [...fetched],
  };
  if (index >= 0) seasons[index] = next;
  else seasons.push(next);
  return { ...document, seasons };
}

function mergeEpisode(previous, episode, lang) {
  const still = episode.still_path ? IMAGE_BASE + episode.still_path : null;
  return {
    number: episode.episode_number,
    name: mergeLangText(previous?.name, lang, clean(episode.name)),
    overview: mergeLangText(previous?.overview, lang, clean(episode.overview)),
    runtime_min: episode.runtime ?? previous?.runtime_min ?? null,
    air_date: episode.air_date ?? previous?.air_date ?? null,
    thumbnail: still || previous?.thumbnail || null,
    imdb: previous?.imdb ?? null,
    skip_intro: Boolean(previous?.skip_intro),
    skip_credits: Boolean(previous?.skip_credits),
  };
}

function mergeLangText(existing, lang, text) {
  const base = existing && typeof existing === "object" ? { ...existing } : {};
  if (typeof existing === "string") base.ru = existing;
  if (text) base[lang] = text;
  return base;
}

function projectSeason(document, number, lang, id) {
  const season = findSeason(document, number);
  const episodes = (season?.episodes || []).map((episode) => (
    projectEpisode(episode, lang, id, number)
  ));
  return {
    number,
    name: textIn(season?.name, lang),
    overview: textIn(season?.overview ?? season?.synopsis, lang),
    episodes,
  };
}

function projectEpisode(episode, lang, id, seasonNumber) {
  const thumb = episode.thumbnail ? String(episode.thumbnail) : "";
  const still = thumb && !thumb.includes("staticpop.net")
    ? `/img/thumbnail/by/kinopub/${id}?s=${seasonNumber}&e=${episode.number}`
    : null;
  // Timestamps stay on the source. The flag only says the marker exists.
  return {
    number: Number(episode.number),
    name: textIn(episode.name, lang),
    overview: textIn(episode.overview, lang),
    runtime_min: episode.runtime_min ?? null,
    air_date: episode.air_date ?? null,
    still,
    imdb: episode.imdb?.votes != null ? { value: episode.imdb.value, votes: episode.imdb.votes } : null,
    skip_intro: Boolean(episode.skip_intro),
    skip_credits: Boolean(episode.skip_credits),
  };
}

function textIn(value, lang) {
  if (!value) return null;
  // A bare string is the Russian overview TMDB gave us on the title resolve.
  if (typeof value === "string") return lang === "ru" ? value : null;
  return value[lang] || null;
}

function findSeason(document, number) {
  return (document.seasons || []).find((season) => Number(season.number) === number) || null;
}

function clean(value) {
  const text = typeof value === "string" ? value.trim() : "";
  return text || null;
}

function json(body, status, extra = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "public, max-age=300",
      "Access-Control-Allow-Origin": "*",
      ...extra,
    },
  });
}
