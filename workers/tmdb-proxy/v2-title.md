# `/v2/title` — the one title call

Base: `https://kinopub-tmdb-proxy.traneblow1nd.workers.dev`

```
GET /v2/title/by/kinopub/{id}
```

One request. The page reads this. Do not also call `/v1/title`. That route is the old raw document. `/v1/card/by/kinopub/{id}` is the same body as `/v2/title`; call v2.

No query. No `Accept-Language`. The id is the kino.pub item id. `200` is the card. `404` means we have no card for that id yet. Cache is 60 seconds.

The call does **not** search TMDB. `title`, `original`, `year`, and `runtime` are not parameters. A show with no IMDb and no Kinopoisk id is matched only if that link was already stored.

## Body

```json
{
  "kinopub_id": 83959,
  "type": "serial",
  "title": { "ru": "…", "original": "…" },
  "year": 2022,
  "status": "Returning Series",
  "tagline_ru": null,
  "synopsis_ru": "…",
  "ids": {
    "imdb": "tt14986406",
    "tmdb": "tv/30984",
    "tvdb": "74796",
    "kinopoisk": "4789626",
    "kinopoisk_hd": null,
    "tvoe": null,
    "wikidata": "Q5362638",
    "myshows": null
  },
  "ratings": {
    "imdb": { "value": 9.0, "votes": 1000 },
    "kinopoisk": null,
    "tmdb": { "value": 8.4, "votes": 2323 },
    "tvoe": null
  },
  "billing": {
    "star": [],
    "director": [],
    "writer": [],
    "regular": []
  },
  "counts": { "featured": 7, "star": 3, "regular": 4, "guest": 74 },
  "images": [],
  "top_episodes": [],
  "networks": [],
  "seasons": []
}
```

`status` is TMDB's: `Released`, `Returning Series`, `Ended`, `Canceled`, or null. A missing rating is `null`, not a zero.

`billing` is only the people to draw. Sections that are empty are absent. Each person:

| field | |
| --- | --- |
| `person_id` | TMDB person id |
| `name_ru`, `name_en` | |
| `character` | the part, for an actor |
| `job` | `Director`, `Creator`, `Writer`, `Screenplay`, … |
| `episode_count` | how many episodes, series only |
| `popularity` | TMDB's number. This is the order inside a section |
| `gender` | TMDB's number |
| `profile_url` | face |
| `roles` | every part: `character`, `job`, `episode_count`, `credit_id` |

`star` is the faces (at most three). `director` is one person (`Director`, or the show's `Creator` when there is no director). `writer` is at most three. `regular` is two or three more names under the count, not the whole list.

`counts` is everyone we did not put in `billing`. `regular` and `guest` are the rest of the cast. `producer`, `executive_producer`, `co-producer` are counts only. Sound, camera, and the rest of the crew are not in this payload. "See all" is a later fetch by the ids above. It is not this call.

`images[]`: `kind` is `poster`, `backdrop`, `logo`, `cover`, `photo`, `still`, or `network`. `lang` is `ru`, `en`, or null. `url` is the file. `source` is where it came from (`tmdb`, `tvoe`, `kinopoisk`, `card`). `person_id` is set on a face, `season` / `episode` on a season poster or a still. Use these urls. Do not also call `/img/…` for the same picture.

`networks[]`: `tmdb_id`, `name`, `logo_url`, `origin_country`.

`seasons[]`: `number`, `name`, `episode_count`, `air_date`, `end_date`, `poster`, and `episodes[]`. Every episode we have is in that list, not only the highlights. An episode has `number`, `name_ru`, `name_en`, `runtime_min`, `air_date`, `still`, `tmdb_id`, `tmdb_value`, `tmdb_votes`, `imdb_id`, `imdb_value`, `imdb_votes`, `season_finale` (`1` or `0`). `episode_count` on the season is the season's own count and can be older than `episodes.length`.

`top_episodes[]` is the short list already ranked (`rank` 1…5), same rating fields. The full list is `seasons[].episodes`.

A movie has no `guest` count and no episode list. `top_episodes` is empty.
