# Data, continuity and diagnostics — full notes

The long form of [AGENTS.md › Data and continuity](../../AGENTS.md#data-and-continuity): measured numbers and the reasons behind each rule.


- **Watch state is `WatchProgress`.** Fraction, unwatched / inProgress / finished live in
  that one type, and **watched is 85% of the runtime** — kino.pub's own rule, probed live
  (`watchedFraction`, Sasha's call to match it, 2026-10-16). So a bare play head (this
  device's, a history row) reads the same as the server's flag on the same title.
  `Episode` / `Video`.isWatched is the server flag *or* `isFinished`. A card paints
  `resumeFraction`, never a 0.95 / 0.02 of its own. When the player's Up Next panel
  appears is a different question (`upNextLeadTime`, the last 60–180 s), not "watched".
  Skip / outro markers, when they land, feed this type; they do not grow a second threshold.
- **Continuity beats placeholders.** Stale local data and already-loaded artwork beat blank screens.
  Card → detail carries the known item, artwork handle and palette; detail paints from that snapshot
  and enriches — it must not blank-reload what the card already had. Exact-layout skeletons only on
  true cold loads, and only when the geometry matches what arrives.
- Deduplicate in-flight work; stale paints first, revalidation runs underneath. Never reuse eternal
  grey as both loading and failure.
- **One store ownership model.** `ContentStore` owns Home/Library *rows*; `MediaLibraryStore`
  owns per-item optimistic library state (watchlist / watched / votes, plus a download
  façade); `Artwork` owns remote images; `MediaRecordStore` owns item facts — one
  `MediaRecord` (merged model) per `MediaRef`, which `ContentStore` rows refer to
  (docs/media-model.md step 4). Do not invent a fifth cache beside those. Bookmarks stay on `BookmarkMembershipStore` /
  `BookmarkFoldersStore` — the library store does not replace them. **All remote images go
  through `Artwork`** — one decoded memory
  cache keyed by target size, one disk entry per URL, coalescing and prefetch, on every platform.
  Use `CachedRemoteImage`, or `ArtworkImage` when the states need different geometry. `AsyncImage`
  is a regression and no longer appears anywhere in this repo. Local optimistic writes (hide, watched, bookmark) are
  authoritative until the server contradicts them.
- **Bookmarks are answered locally.** `BookmarkMembershipStore` (item → folder ids) and
  `BookmarkFoldersStore` (the folder list, persisted across launches) draw every bookmark control.
  `GET /v1/bookmarks` belongs to the screens that list folders — Library, Bookmarks, the sidebar,
  which hand their result back with `adopt(_:)` — and to the moment a folder is created or deleted.
  **A detail page fetches neither**: membership is already on the item payload (`bookmarks`), and
  `get-item-folders` is gone on purpose.
- **`nolinks=1` on a series detail page is off** (`FeatureFlags.seriesDetailsWithoutLinks`).
  It is built and switchable — `MediaItemModel` asks without links when it knows the card is
  episodic (`isEpisodicType`), and `MediaLinksResolver` fills one `Episode` from
  `/v1/items/media-links?mid=` when it is played — and kino.pub will make it the default, so
  it is what we flip then. **A `nolinks` payload still lists `files`, with no link bag under
  any key**: never assume a file carries a URL, ask `hasPlayableURL` (requiring one failed
  every series page with `keyNotFound 'urls'`). Films always come with links.
- tvOS purges `Caches/` when the app is not running — lean on longer in-memory TTLs, don't fight it,
  and don't pretend offline parity exists.
- **New API calls go through `KinoPubBackend`** — Endpoint + model + service protocol + mock.
- **Document an external source before integrating or extending it** — every method, field and
  model, including ones we do not want, into a sheet in `docs/providers/` *first*. Store every
  detail the API gives; decide what is redundant later, from evidence.
- **Providers: our worker when it helps, the app for a viewer's own connection.** The
  Cloudflare worker proxies, caches and aggregates with built-in or owner keys, or when a
  service is flaky or rate-limited; a viewer's own key or account (Kinopoisk, Trakt) is called
  by the app. Either way it lands as `MediaFragment`s. See [docs/media-model.md](../media-model.md).
- **Telemetry:** no third-party SDK. TestFlight / Xcode Organizer already deliver crashes. Do not
  add Firebase, Sentry or similar without an explicit decision. **This is a rule about *sending*
  data somewhere.** On-device diagnostics that leave nothing behind — `Pulse`'s local store behind
  `NetworkDiagnostics` — are not telemetry and are not covered by it.
- **Diagnostics are shipped, not DEBUG-only.** The launches worth reading a log for happen on a
  physical Apple TV running TestFlight, with no Xcode attached, so Settings › Diagnostics › Network
  log is in every build. Capture goes through `NetworkDiagnostics.start()` once at launch (it
  swizzles `URLSession`, so it catches every client and shows tasks still in flight). Tokens are
  redacted **at capture**, because the store is exported and shared.
- **The log records API traffic only.** Artwork and media are excluded by host *and* extension,
  and `NetworkDiagnostics.store` is ours rather than `LoggerStore.shared` because Pulse's defaults
  — 256 MB of store, 8 MB per body — are what produced 50 MB log files. Ours: 32 MB store, 512 KB
  per body, in `Caches/`. Adding a media host to the app means adding it to `excludedHosts`.
- **"What are we waiting for" is `NetworkActivity`** (`KinoPubLogging`), hooked once in
  `URLSessionImpl` so no call site has to remember to report. Pulse logs completed tasks; this is
  the live one. It feeds the debug overlay (and `LaunchStatusLabel` where a surface wants the same
  copy). Entries carry a **localization key**, never a path: a raw `/v1/items/…` on a user's TV is
  worse than saying less, so an unmapped endpoint reads "Загружаем" and keeps the path for the
  overlay only. Add a key to `Localizable.xcstrings` (RU + EN) when you add an endpoint family, not
  a string at the call site.
- **Auth launch is optimistic.** A Keychain token mounts the main shell immediately; token refresh
  is driven by the stored access-token expiry (proactive ~90s early) and by content 401s. Do **not**
  reintroduce a full-screen gate that waits on `refreshToken` — that splash ("Signing in") was the
  hostile cold-launch wait. `APIClient` must await recovery and retry a content 401 once — failing
  the caller's request while refresh is in flight replaces painted pages with Try Again. Only a
  real grant rejection sends the user to activation; network blips keep the session and back off.
- **Downloads are non-TV only.** Feature-gate incomplete surfaces (`FeatureFlags`) rather than
  inventing half-UI. An off flag must skip the work — network, sampling — not only hide UI.
  **Every flag is a `FeatureFlag` case** (default, title, one-line summary, platforms, launch-time
  or not) and so is switchable in Settings › Diagnostics › Feature flags in every build — a
  `static let` flag can only be judged by rebuilding, and there is no Xcode next to a TV.

