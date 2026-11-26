# Changelog

Notable shipped changes and implementation facts future agents need. Trivial copy/token churn does
not belong here. Detail checklists live in [ROADMAP.md](ROADMAP.md).

Older dated entries live in [docs/archive/changelog-history.md](docs/archive/changelog-history.md) —
do **not** open that file for routine work; append short bullets under Unreleased only.

## Unreleased

- **What's New on Mac:** long notes scroll inside the panel again (visible
  scrollbar); short notes still hug. The dimmed host no longer swallows scroll
  wheels over the panel itself — only outside it, so the page behind stays still.
- **App display name:** home screen and About title is **Piratic**
  (`CFBundleDisplayName`). Swift module / `PRODUCT_NAME` stays `KinoPub` for now.
- **What's New contributions:** new visible-change notes go in isolated files under
  `KinoPubAppleClient/Resources/WhatsNew/entries/` (folder reference; no pbxproj
  edit). `whats-new.json` stays as a frozen legacy archive; the loader and Fastlane
  merge both. See `docs/product/whats-new.md`.
- **Downloads UX (KP-91):** quality labels use pixel height (and Stream Quality
  cap for HLS), not a possibly-inflated `FileInfo.quality` string; every available
  subtitle is fetched while online (HLS legible options + mp4 sidecars); ETA is
  EMA-smoothed; Cancel/Delete swipe is red and Pause/Resume orange (readable in
  light mode); intro/credits skip timings are stored with the download for
  offline play and surfaced when missing; the Downloaded list groups by series
  with seasons as sections.
- **Poster / video context menus (KP-73):** Apple TV–style sneak peek on every
  long-press surface — native poster (2:3) / wide (16:9) aspect with fit (no
  centre-crop), title + secondary line (`year · genre`, duration, or episode
  meta), prefetch and loading spinner. Follow / unfollow flips the menu title
  immediately and toasts success; Watched on series CW cards is a submenu like
  the detail «…» menu (episode · season · unwatched in season · all).
- **tvOS Search first paint:** pre-warm loads the system search stack in a hidden
  scene window at launch. The window stays out of the accessibility tree; after
  the tab takes the stack, later pre-warms do not build a second search UI (a
  visible parking window laid results over the keyboard). First Search body is
  the filter chips; posters wait until the tab has appeared. `page.search`
  signpost is takePrepared → first on-screen layout. Check:
  `TVSearchLayoutUITests.testSearchTabChromeAppearsWhenOpenedFromWatchNow`,
  `PerformanceUITests.testSearchTabFirstPaint` (`-KINOPUBSearchFixtureStartOnWatchNow`).

- **Hover pictures match the title page (macOS):** Continue Watching and History bring up
  the same episode still the title page's season rail draws (worker
  `/img/thumbnail/by/kinopub/{id}?s=&e=&src=`, WebP at the card's drawn width), and a
  film brings up the hero's backdrop. kino.pub's own frame is the fallback.
- **Title open never waits (tvOS):** the previous title's backdrop is dropped at once
  for a blurred copy of the card's poster; the worker backdrop crossfades in when it
  has loaded. Hero logo/backdrop URLs are built immediately from the kino.pub id, not
  after the details call. Below the hero the picture stays as a blurred copy with an
  appearance tint instead of fading to an empty page.
- **Hero buttons:** Play is a solid white capsule with a dark label in every state
  (Replay too), the rest dark see-through bordered buttons on tvOS and macOS; iOS keeps
  glass. The main Play no longer changes control while the page loads, so focus stays
  on it instead of falling onto the synopsis.
- **Series from the listing:** a serial opened from a listing (no seasons yet) shows
  as a series from the first frame (bell, facts). A kept copy whose episode count
  differs from the watching list drops its stale seasons («Replay E1» → «Play E3»).
- **Artwork cache eviction:** decoded images expire after 15 minutes even under
  the RAM budget; memory warning clears them; background keeps a tenth.
  Disk is still LRU by last access with the size cap, plus a 7-day unused
  floor, swept off the main thread at launch and on background.

- **Artwork decode at drawn size:** backdrops, title logos and season-rail stills
  go through Nuke thumbnail + resize at the slot (logos `.fit` so PNG alpha
  stays; never TMDB `/original`). One logo bucket per platform (`w780`/`w1280`).
  Decoded-image RAM cache scales with device memory (192 MB on a 3 GB Apple TV
  4K). Home neighbour warmup, `TitleLogoSession` and the season-rail mark share
  request keys. Follow-ups not in this change: SwiftUI Home hero rebuild,
  `shadowPath`, season-rail CADisplayLink / fold blur.

- **Episode stills / rail labels (KP-75):** `/img/thumbnail` accepts a kino.pub
  catalogue thumb last (document or `?src=` staticpop-only), serves it via
  wsrv.nl `w=` + WebP, and no longer edge-caches thumbnail 404s. Missing stills
  re-check TMDB after 6h (`fetched_at`). Client passes `src=` and asks slot
  pixels (not round-up-to-100). Season-rail captions use one
  `EpisodeText.listItem` / `.episodeTile` ruleset on tvOS, iPhone and macOS
  (`7. Name` / `7 серия`) — numbers no longer live only in invisible
  `secondaryText` or focus chrome.

- **Artwork via wsrv.nl (KP-68):** stamped `/img` bytes prefer
  `https://wsrv.nl/?url=…&w=&q=80&output=webp`, with legacy TMDB/tvoe/Kinopoisk
  resize if weserv fails or `WESERV_DISABLED` is set. Logo / backdrop / poster
  feed the durable original; **thumbnails** feed the TMDB ladder URL so face-crop
  tokens (`w454_and_h254_face`, …) stay in `url=` and weserv only re-encodes
  (kinopub catalogue thumbs pass the staticpop URL as `url=`).
  Stamped answers are edge-cached 24h (`caches.default`);
  `X-KinoPub-Image-Via: weserv|legacy`. Optional `format=webp|jpeg|png`.
  MacBook backdrop `w=` cap **1920 → 2400**. Free-tier care: ~2500 uncached /
  10 min / IP — rely on edge + Nuke coalesce, not a second client-side wrap.

- **CI on Xcode 26 GM:** project file is Xcode 14-compatible `project.pbxproj`
  again (Xcode 26.6 opens it). CI and TestFlight run on `macos-latest` (the
  macos-26 arm64 image) with a stable 26.x GM, not the scarce `xcode-27` pool.
  Full matrix only on `pull_request` and push to `main`. Tests wait for compile;
  package tests are one job; jobs have timeouts and a per-test 180s watchdog.
  iOS/macOS deployment target is 26.5 (Xcode 26.6's SDK). Settings toggles use
  `ToggleStyle.Configuration`; `DownloadManager` is `final` so Swift 6 Release
  archives compile. History event lines keep the day (`27 января в 20:54`).
  Package tests match current `EpisodeText` / Library header copy. Performance UI
  tests require the walk's own signpost, not a cached `artwork.request`.

- **Performance measurement:** `OSSignposter` intervals under subsystem
  `com.soda.kinopub.perf` (artwork request/display, hero page and backdrop,
  Home shelf scroll, season-rail slide, title open, window resize). Zero cost
  unless Instruments or `XCTOSSignpostMetric` is attached. Scroll intervals are
  per gesture (begin on move, end on settle). Empty signpost metrics fail the
  UI test. `URLSessionResumeGuardTests` match `install` restoring pre-Pulse
  `resume` (no Pulse re-enable). Playbook in `docs/engineering/performance.md`.

- **tvOS console quiet (follow-up):** nav zoom no longer drives
  `_TVNavigationZoomAnimator` (that inserted `_UIReplicantView` under hosting
  views) — plain `UIImageView` scale/fade on the navigation controller; snapshots
  use `drawHierarchy(…, afterScreenUpdates: false)`; push/pop direction is
  recorded in `willShow`. Home hero / page stop preferring themselves while they
  already own focus so Up reaches the tab bar. TV Menu `returnToTopRow` retries if
  the cell does not own focus (no hand scroll). TV disk cache URL is injectable
  (tests use a temp file). Dead live on tvOS auto-dismisses with a toast. TSK…
  snapshot lines stay Apple-only.

- **Shared watching-list cache + quieter Home/Search:** `/v1/watching/movies` and
  both `/v1/watching/serials` answers are one in-memory cache (~3 min, coalesced)
  for Continue Watching, Library Unwatched/Following and the sidebar badge.
  Cleared on mark/toggle/follow/hide and when playback ends — not on progress
  ticks (#110). CW / Top Bookmarks / sidebar folders go through
  `BookmarkFoldersStore` + ContentStore folder rows. Foreground only repaints
  local progress (no in-session watching refetch). Search tab re-entry honors the
  5 min TTL instead of force-refreshing every hop.

- **TV tab polish:** channel caption stays the programme when focused (system
  marquee when long) — no channel-name swap under the tile. `GET /v1/tv` is reused
  for an hour (memory + Caches). Navigation path Binding skips no-op writes;
  tvOS nav zoom snapshots are `UIImageView`s (not `_UIReplicantView`); PCM no
  longer logs every `NonFocusablePosterView` clear.

- **TV channel logos from the bundle:** seven sports channels paint from
  `KinoPubUI` `Media.xcassets/tv` as full cards (CDN for the rest).
  `TVPageLogo.bundledMark` / mark+focus-BG compositing stays wired but unused.

- **Playback no longer refreshes Library / Continue Watching shelves:** progress ticks were invalidating watchlist / unfinished / history and notifying Home, which re-hit `/v1/watching/*`, bookmarks and `/v1/history?perpage=50` about every 10 s (ban risk). Named-key invalidate only notifies for `.continueWatching`; Library stale marks wait until the player ends; Home skips network refresh while the player is active; Continue Watching history is capped at 8 and skipped when a warm history cache exists.

- **Download on a title page (iOS):** Pulse's resume swizzle reads `currentRequest`. `AVAggregateAssetDownloadTask` throws `NSGenericException` from that getter, so pressing Download quit on `__NSCFBackgroundAVAggregateAssetDownloadTaskNoChildTask`. `URLSessionResumeGuard` calls the pre-Pulse `resume` for aggregate and asset download tasks and does not enter the swizzle.

- **iOS and Mac skip chip:** Skip no longer presses itself. The default is Apple’s button (a press). Settings › Playback picks the delay, the automatic treatment (countdown, shrinking fill, progress stroke, ring, Picture in Picture with artwork, an Up Next banner) and cancel (an X, or Watch Credits). The chip is ordinary glass, dissolves ahead of the system chrome, and stays down while a subtitle or audio menu is open — the chrome stays up with that menu. tvOS still uses AVKit’s own button.

- **macOS player (KP-35):** window title carries S/E + episode name, or concert show line + part (`PlaybackVariant`); prefers max-quality `hls4`; toasts load failures; retargets in place so the next item does not wipe to black; transparent title bar (no underlay).

- **What's New + film info on iPhone / iPad / Mac:** large / page sheet; hierarchical
  `xmark.circle.fill` close (same as Choose a Version); material toolbar that fades in
  on scroll; «Продолжить» via `.borderedProminent` + `Color.primary` (not `.glassProminent`);
  Mac panel hugs content and blocks scroll behind when dimmed; previous marketing versions
  under the new bullets when present. tvOS keeps the restored wide info / What's New sheet
  from #122 (Choose a Version stays the compact card).

- **Multi-version films: one Play → Choose a Version.** A `subtype: multi` film no longer
  gets a play pill per edition in the hero. One «Смотреть фильм» (or Continue / Play Again)
  opens an Apple TV-style sheet — thumb + name + runtime / quality / audio / subs when
  those differ. The Versions rail stays for browsing. Concerts and multi-part titles keep
  the old pills. (Sasha, 2026-11-14.)
