# The media model — one place every surface answers to

What the app knows about a title, what the viewer has done with it, and how a surface turns
both into words and pictures. Decided direction (user, 2026-10-03): **facts from every source
are kept and pinned to the fact they state; product rules decide what a surface shows, in one
layer, by scenario — not per view.** The player's info panel ([playback-info.md](product/playback-info.md)) is the first
surface on it.

Architecture and plan, not product rules: what a surface *says* is decided in
[docs/product/](product/); this file is where those decisions plug in.

Status of each part: **done**, **next**, **later**. Open product questions are numbered
**D1…** at the end; the code carries the same numbers as `TODO(decision)`.

## Layers

Each layer reads only the one below it. A layer is a package or a folder of plain types, all
`Codable` and `Sendable`, tested without a device.

| # | Layer | Answers | Lives in | State |
| --- | --- | --- | --- | --- |
| 0 | **Sources** | "what did kino.pub / TMDB / Kinopoisk say" | `KinoPubBackend` (kino.pub), `KinoPubMetadata` (TMDB, Kinopoisk); later our server `/v1/title` | done |
| 1 | **Facts** | "what is this thing, according to whom" | `KinoPubMedia`: `MediaFragment` → `MediaAggregator` → `MediaEntity` / `MediaContext` | done |
| 2 | **Identity** | "which thing" — one key every store agrees on | `KinoPubMedia`: `MediaRef` | next |
| 3 | **Viewer state** | "what has the viewer done with it" | app stores, read through one `ViewerState` value | next |
| 4 | **Selection** | "which things belong in this list, in what order" | pure functions: Continue Watching, Up Next, Unwatched, History, Watchlist, Bookmarks, shelves, banners | later |
| 5 | **Presentation** | "what does this surface say about it, in which words" | `MediaPresenter` + formatters + one surface table | next |
| 6 | **Views** | drawing | `KinoPubUI`, `Views/` — no string building, no source knowledge | — |

### 0 · Sources — adapters only

A source maps its payload into `MediaFragment`s and decides nothing else. Precedence,
inheritance and wording are not an adapter's business. New providers land on our server,
not in the app (AGENTS.md); the server document then becomes one more source of fragments.

### 1 · Facts — nothing a source said is lost (done 2026-10-03)

- `MediaFragment` is one source's statement about one entity, with the **language** its text
  is in.
- `MediaAggregator` merges fragments into a `MediaEntity`. Its stored fields are the
  **default answer** per field, chosen by `MediaPrecedence`. `provenance` says who gave it.
- **`MediaEntity.claims` keeps every fragment.** A surface that wants a particular source's
  fact asks for it:

  ```swift
  show.synopsis.tagline                                   // the default tagline
  show.claims(for: .tagline) { $0.synopsis.tagline }       // every source's, best first
  show.value(from: .kinopoisk) { $0.synopsis.short }       // Kinopoisk's short description
  ```

- Plot, short description and tagline are **three facts**, ranked separately
  (`.synopsis`, `.shortSynopsis`, `.tagline`).
- `MediaContext` holds the inheritance rules (episode → season → show; scores never inherit).
- Everything is `Codable`: the merged model can be stored and read back as is.

Fixed alongside: `MetadataService` merged sources in **arrival order** (whoever answered
first won the gap-filled overlay); it now merges in configured order and keeps each source's
own part. Kinopoisk's details payload — Russian title, plot, short description, slogan, age
rating, scores, genres, countries — was decoded and dropped; it is now Kinopoisk's own
fragment.

### 2 · Identity — `MediaRef` (next)

Today every store keys a thing its own way:

| Store | Key |
| --- | --- |
| `LocalWatchProgressStore` / `WatchRecord` | `"itemID:season:episode"` string |
| `MediaLibraryStore` watched | `itemId` for films, **episode id** for episodes |
| `MediaLibraryStore` downloads | `"id-video-season"` string |
| `DownloadMeta` | `"S4E4"` marker in a name |
| `MediaCard` | `id`, `itemID`, `video`, `season`, `mediaID` — five ints, meaning per card kind |
| `/v1/watching/toggle` | item id + video number + season |

`MediaRef` = kino.pub item id + optional season + episode/video number, `Codable`,
`Hashable`. Every store reads and writes through it; each store's own key becomes a
private encoding of it. The episode's kino.pub `id` stays a fact on the entity, not a key.

### 3 · Viewer state — one value, owners unchanged (next)

The owners stay as AGENTS.md assigns them (`LocalWatchProgressStore`, `MediaLibraryStore`,
`BookmarkMembershipStore`, `BookmarkFoldersStore`). What is new is **one read**:

```swift
struct ViewerState: Codable, Hashable {
  var progress: WatchProgress?      // the one watch-state type
  var isWatched: Bool               // server flag or local finished, optimistic overlay applied
  var isInWatchlist: Bool           // kino.pub "Я смотрю" — the series subscription
  var bookmarkFolderIDs: [Int]
  var download: DownloadStatus
  var vote: Bool?
  var lastWatchedAt: Date?          // history
}
```

A card, a list and a button all ask `ViewerState(for: ref)`; none reads four stores. Today
`MediaCard` copies this state in at build time (`isWatched`, `progress`, `isInWatchlist`,
`isBookmarked`, `bookmarkFolderIDs`) and `ContentStore` persists those copies to disk, so a
row painted from cache shows yesterday's state until the next fetch overlays it.

### 4 · Selection — lists are queries (later)

| List | Today | Becomes |
| --- | --- | --- |
| Continue Watching | `HomeCatalog` + `ContinueWatchingEpisode.forSeries` + `ContinueWatchingLocalOverlay` | `Selection.continueWatching(records, state)` |
| Up Next (player) | `PlaybackMediaContext.nextUnwatched` + CW cards | same function as Continue Watching's "next episode" |
| Next episode for a series | `NextPlayableEpisode`, `ContinueWatchingEpisode.forSeries`, `nextUnwatched` — three answers | one `Selection.nextEpisode(series, state)` |
| History | `HistoryView` from `/v1/history` | query over records + `lastWatchedAt` |
| Watchlist / subscriptions | `WatchlistView` | query |
| Bookmarks | `PersonalLibraryCatalog` | query |
| Unwatched | — | query: episodes with `!isWatched` |
| Catalog shelves, banners | `HomeCatalog` shortcuts, `LibrarySectionCatalog`, `CollectionsModel` | server order kept; items become records |

### 5 · Presentation — one rule table, named styles (next)

**Inputs:** a `MediaContext` (facts), a `ViewerState`, a **surface**. **Output:** a
descriptor with semantic slots — title, subtitle, episode reference, meta line, badges,
primary action, artwork role — already worded. Views draw slots; they do not compose.

- **Surfaces**, one enum: poster card, landscape card, focus preview, Home banner, detail
  hero, season rail tile, Up Next tile, history row, player info, Now Playing, Top Shelf,
  context menu, settings row.
- **Styles**, one vocabulary for every formatter: `compact` / `short` / `full`.
- **Formatters**, one each: episode reference, runtime, remaining time, release, genre
  (primary / up to *n*), country, season count, score, action titles. Strings in one table.
- **One table** says which surface shows which slot in which style. A difference between
  two surfaces is a row in that table, visible and deliberate, never a second helper.

Duplicates this replaces (audit 2026-10-03):

| Concept | Separate implementations today | Differences |
| --- | --- | --- |
| Episode reference | `ContinueWatchingEpisode.overlayLabel` ("S2, E5", not localized), `HistoryView` ("S2, E5"), `MediaActionCopy.episodeLabel` (RU «2 сезон, 5 серия»), `PlaybackMediaContext.labels` (RU «Сезон 2, Серия 5»), `SeasonsRailView.episodeLabel` / `SeasonView` / `PlayerManager` («Серия 5»), `TrackMemorySections` + `TVSettingsCatalog` + `TVProfileSettingsView` ("S2E5", three copies), `SeasonDownloadManager` / `MediaItem.downloadableItems` ("S2E5" file names), `MediaItemHeroView` ("S2, E5") | four formats for one thing → **D6** |
| "Episode 1" is not a name | `EpisodeTitle` (KinoPubMedia), `MediaCard.isOwnNumber` (KinoPubUI) | different word lists |
| Runtime | `Duration.compact` (KinoPubBackend), `MediaActionCopy.compactDuration`, `LandscapeTimeBadge.compactLabel`, `MediaCard.durationLabel` | «53 мин» vs «53m» → **D8** |
| Time left | `MediaActionCopy.remainingLabel` (`MediaAction_TimeLeft`), `LandscapeTimeBadge` (`"%@ left"`) | two string keys |
| Genres on a line | `MediaItem.metadataLine` (two, comma-joined), `MediaCard.genreLine` (two), `PlayerInfo` (one, primary) | **D7** |
| Is it a series | `isSeries`, `isEpisodicType`, `type.contains("serial")`, `MediaKind`, `MediaPresentationKind` | five tests of one fact |
| Meta line | `MediaItem.metadataLine`, `releaseLine`, `MediaCard.metaLine`, Home banner short meta, `withContinueWatching` overriding `metaLine` with the overlay label | five compositions |

### 6 · Views

`MediaCard` today is 40 pre-worded fields built by ~20 call sites, persisted to disk by
`ContentStore`. It becomes the presenter's output, built at paint time from records and
state; the cache stores records, not words.

## Plan

Each step is one reviewable slice with tests, merged before the next.

1. **done** — Facts kept: claims, per-part synopsis, fragment language, `Codable`; Kinopoisk
   details as a fragment; deterministic metadata merge.
2. **next** — `MediaRef` + `ViewerState` read façade over the existing stores. No visible
   change.
3. **next** — Presentation vocabulary: surfaces, styles, the formatters above, one strings
   table. Every duplicate in the audit routes through it **keeping today's output**; each
   difference becomes a row marked with its decision number. No visible change until a
   decision lands.
4. `MediaItem` / `Episode` / `Season` → `MediaContext` everywhere through
   `KinoPubMediaMapping` (already used by the player); a `MediaRecordStore` keyed by
   `MediaRef` replaces `TitleSnapshot` payloads and the card snapshots in `ContentStore`.
5. Selection functions, starting with the single "next episode" answer (three today).
6. Surfaces move one at a time, each with its rows in the surface table: player (done) →
   Up Next → Continue Watching → History → Watchlist → Bookmarks → catalog shelves → Home
   banner → detail hero → Top Shelf.
7. Server `/v1/title` document carries claims per source (document v3); the app's
   enrichment becomes one call, and providers stop being app clients.

## Decisions needed

| # | Question | Today |
| --- | --- | --- |
| D1 | Text fields (title, plot, short, tagline): **viewer's language first**, source order only as tie-break? | source order only |
| D2 | Plot: Kinopoisk's `description` (often fuller) above kino.pub's plot? | kino.pub first |
| D3 | Age rating: one per title by viewer region, or keep RU and US side by side? | one; Kinopoisk's RU first |
| D4 | Poster: Kinopoisk's Russian one-sheet vs TMDB's for a Russian-speaking viewer? | TMDB first |
| D5 | Keep `.apple` in precedence lines while no Apple source exists? | listed, never runs |
| D6 | Episode reference: one format per style. Proposal — compact `S2, E5` / `2 сезон, 5 серия`; full `Season 2, Episode 5` / `Сезон 2, Серия 5`; file names `S02E05` | four formats |
| D7 | Genres outside the player: one (primary) everywhere, or two on the focus preview? | two on cards, one in the player |
| D8 | Runtime words: «53 мин» or «53m», «1 ч 24 мин» or «1ч 24м» — one per style | both |
| D9 | Precedence lines the user disagrees with — which? (each line is commented in `MediaPrecedence.standard`) | — |
| D10 | A title with no IMDb id gets no TMDB enrichment at all. Match by title + year instead? | none |
