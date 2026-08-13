# 04 — KinoPub catalog completeness

**Status:** Partial  
**Goal:** Surface what kino.pub already provides — collections, people, photos, similar/related,
payload metadata — before chasing external enrichment or advanced subtitles.

## Accepted behavior

- Detail pages show available native metadata and related rails without pretending we have personal
  recommendations.
- Collections UI uses existing `CollectionsService` (`GET /v1/collections`, `/view`).
- Similar items rail stays (`GET /v1/items/similar`) — prefer this over "same genre" approximations.
- People / cast / crew routes stay first-class.
- Photos / stills when the API or already-wired proxy provides them.
- Decode and preserve quality / AC3 / age / artwork fields even before every chip is designed.

## Checklist

- [x] Similar items rail
- [x] Cast/crew → person credits pages (kino.pub actor/director queries)
- [x] Detail shelves: more from director / more with actor (`LibraryFilter.person`, first credit)
- [x] Multi-country, ratings, synopsis panel, info/audio columns
- [ ] Collections browser + collection detail UI
- [ ] Trailers as items in the detail page's playable rail — not a movies-only section, and not a
      hero takeover alone (see [the playable graph](#the-playable-graph))
- [ ] Vote (`GET /v1/items/vote`) + show own vote state
- [ ] Wire remaining filter chips (4K/HD/AC3/KP/IMDb min — client-side facets exist)
- [ ] Concert / special tracklists when present in payload
- [ ] Explicit **recommendations gap**: document that personal recs are absent; do not fake them
- [ ] Comments endpoint — optional, community has it; port only if we commit to UI

## The playable graph

> User decision, 2026-08-13. This is the data question the detail page kept trying to answer in
> the UI layer, which is why it kept growing per-type sections.

A detail page is ordered by **what the user can play right now**, so the model has to say what a
playable node *is* before any layout does:

```
Media                          e.g. a movie, a series, an anime season
 ├── PlayableItem              episode · trailer · part · extra · the movie itself
 │     └── PlaybackVariant     24 fps · 48 fps · HDR · dub / audio track set
 └── Related media             other titles — a shelf, not a content type
```

- **`PlayableItem`** — id, title, duration, image, playback source, progress, kind. An episode and
  a trailer differ by `kind`, nothing else; they render through one rail
  ([component-catalogue](../policies/component-catalogue.md#one-playable-rail-not-one-section-per-content-type)).
- **`PlaybackVariant`** — the *same* content, encoded differently. kino.pub ships these as fake
  episodes: item **124447** exposes `s0e1` / `s0e2` for 24 fps / 48 fps. Those are not episodes and
  must not reach the episodes rail as siblings of real ones; multi-part films are the other case of
  the same shape.
- **The trailer is needed before the rail is**, because the hero's Trailer button needs it — which
  is another reason it cannot be modelled as a section that only movies get.

**Map the API before designing more UI here.** Blind spots to close, by proxying the real client:

- [ ] `GET /v1/items/{id}` — what actually distinguishes a season/episode from a part from an
      fps variant in the payload (`s0` convention? a flag? naming only?). Use 124447 as the probe
- [ ] How to *request* a specific variant, and what the player has to be handed for it
- [ ] Playback endpoint — streams, qualities, fps, codecs, audio tracks, subtitles, and which of
      those are per-variant vs per-item
- [ ] Trailer source: where it lives in the payload, and whether it needs its own request
- [ ] `GET /v1/items/similar` — measure cost and cacheability. It is slow enough that it must not
      block the hero or the playable rail; check whether a newer API version returns real related
- [ ] Collections / rewards (`/v1/collections`, awards fields) — what they are (curated? franchise?
      recommendations?) before deciding whether they are a shelf on this page
- [ ] Record all of it in a kino.pub sheet the same way external providers are documented
      ([metadata-architecture](../policies/metadata-architecture.md)) — every field, including the
      ones we do not want yet

## Out of scope here

External TMDB/Kinopoisk polish → [06-discovery-and-enrichment.md](06-discovery-and-enrichment.md).
Editorial IMDb tops → same.
