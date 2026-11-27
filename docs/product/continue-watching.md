# Continue Watching

What the Home row offers, in what order, and what it deliberately leaves out.

The row combines `/v1/watching/movies`, both `/v1/watching/serials` lists, recent bookmarks, and
local viewing activity. Field-level detail of
those payloads is in [docs/providers/kinopub/watching.md](../providers/kinopub/watching.md); the
mechanics are on `ContinueWatchingOrder` and `ContinueWatchingLocalOverlay`.

## What the row is for

**prd** — It is "carry on with what you were doing", not the watching list. On iPhone, iPad and
Mac the row's header opens a longer cut of this same ranking on its own page. It does not switch
to the Library tab or to Catalog. On tvOS the header has no chevron.

**prd** — It is capped (`ContinueWatchingOrder.maxItems`). `/v1/watching/serials` returns every
unfinished serial on the account — hundreds, for a long-lived one — and past the first screen that
is a list of things abandoned years ago. A sideways scroll with no end defeats the point of the row.

**prd** — On tvOS the row is five 16:9 stills across (HIG 5-column). The title stays under the
tile at rest, not only on focus.

## Interaction

**prd** — On iPhone, iPad and Mac the rail scrolls freely during the gesture and aligns
with a card when it settles. A fast swipe can pass multiple cards.

**prd** — A title can appear in both the Home hero and Continue Watching. Loading or updating
the hero keeps the Continue Watching rail and its scroll position.

**prd** — The landscape still (screenshot) opens the **player**, not the title page — Home,
Continue Watching, and Recently Watched, on Mac / iPad / iPhone / tvOS. The play chrome is
there for that reason.

**prd** — Split hit targets on pointer and touch: still / top → play; title area under the
still → title / episode info. Title hover opacity ~0.8; a truncated title shows the full
string as the hover tooltip.

**prd** — The subscribed unwatched count chip on a landscape still hides when the count is 1
(that episode is about to play) and hides on hover / focus. Hovering the digit itself may
expand «2» → «2 серии». Continue Watching never adds a second «N серий» subtitle line under
the title — that line is for Following posters.

## Order

**prd** — Sort descending by the latest qualifying interaction for each title. Use the time this
device last played it, the release of a new episode on kino.pub for a followed series (the title's
`updated_at`), and the time it was added to bookmarks. Kino.pub gives a folder timestamp for
the newest bookmark in that folder. For bookmarks added in the app, use the locally recorded time.

**prd** — A series included only because it was saved says «В закладках» / “Bookmarked”.
Series in progress and followed series with new episodes show the episode the card offers.

**prd** — Undated unfinished titles follow dated ones. Ties go to the smaller unwatched backlog
(`new`, zero for a film), then to the order of the input lists.

## What stays out

**prd** — A title only *local* progress knows about needs `WatchProgress.enterContinueWatchingSeconds`
before it earns a card. The 10 s "has started" floor is for painting a progress bar on a card that is
already there; a card the server never listed has nothing to take it back out again, and a trailer
sampled for a minute is not something to carry on with.

**prd** — A finished film leaves the row. A finished *episode* does not remove the series — it steps
it to the next **on-service** episode. An unreleased placeholder (listed with no file and no
runtime — the season rail's «Через N дней») is not a next episode: when every aired episode is
watched, the series leaves the row the same way a fully watched one does (Replay / Follow on
the detail page), never a card that advertises the future episode number.

**prd** — Dated interactions use the window chosen in Settings (eight weeks by default). A
sample below the entry threshold counts as a viewing event for up to 14 days. Every followed
series is a candidate regardless of its episode backlog or recent activity. Recent releases
supply an activity date. The row offers a followed series when it has a playable unwatched
episode. Up to four bookmark-only titles can fit when the viewer enables bookmarks.

The Library tab still has the whole watching list.

**prd** — The row never pages. "Page 2" of a four-source merge has no meaning on the server.

## Which episode a card offers

**Watched is 85% of the runtime, kino.pub's own rule** (Sasha, 2026-10-16: "the credits are where
people stop; offering their remnant is cringe"). Probed with `marktime` on a 3392 s episode: 84.99%
unwatched, 85.02% watched, recomputed from the current play head every time. `WatchProgress`
uses the same number, so a play head with no flag beside it (this device's, a history row) reads
as the server will.

**The title's own payload decides, with the server's watched flags — the same answer the detail
page gives** (Sasha, 2026-10-16: VisionQuest S1E2 was watched on its page and "in progress" on
Home). `EpisodeQueue.continueTarget` / `Episode.isOnService` is that answer: same gate the season
rail uses for playability (files ladder or runtime ≥ 60 s). The row asks `/v1/items/{id}` for
every series in it, and for every title the server's watching lists do not carry (it came from
history or this device: leaving those lists is the server saying "done"). A payload is reused for
the session until its title moves — the server's counts, its newest history row or this device's
play head — so a refresh after nothing happened costs no request.

History alone only has a play head, and counts span the whole series, so a guess from them
(`ContinueWatchingEpisode.forSeries`, used when a payload could not be had) treats the watched
count as an episode number in the first season only. Before this the guess offered «S3, E30» on
a ten-episode season and the row kept trusting it.

## Refresh

The cached snapshot is a 60 s TTL on the Continue Watching *row*. Watching-list GETs
are shared through `WatchingListCache` (~3 min, coalesced) across Home, Library and the
sidebar badge.

- **Foreground** (Watch Now `scenePhase == .active`) applies local progress immediately
  and refreshes an expired row through the shared watching-list cache if the player is idle.
  During playback only `marktime` and local progress run.
- **Mark watched / hide / follow** on the detail page invalidates the `.watch` family
  (and `WatchingListCache`). That posts `contentStoreDidInvalidateWatch`; Home
  refetches instead of painting the cached cards. Marking a film watched also writes a
  local finished tombstone, so overlay hides the card before the refetch returns —
  without it, overlay re-inserted the in-progress playhead onto a title
  `watching/movies` had already dropped.
- Progress ticks mark Library watchlist / unfinished / history stale for the next
  Library visit. That named-key invalidate does **not** notify Home (Continue Watching
  overlays local progress itself). When the player ends, those keys (and
  `WatchingListCache`) clear once so Library / badge see a fresh list.
- Bookmark folders for this row and Top Bookmarks go through `BookmarkFoldersStore` +
  `ContentStore` folder rows. Confirmed bookmark changes refresh the ranking using the
  watching-list cache.
- The row asks **no `/v1/history`** (Sasha, 2026-11-23). `watching/movies`,
  `watching/serials?subscribed=0` and `subscribed=1` are the source: an unfollowed title
  on those lists can qualify as unfinished without a known date. This
  device's plays and title payloads still date titles. The #110 fix had cut history to 8
  rows, which left every unfollowed title without a date and off the row.
- An in-flight fetch that started **before** an invalidate is discarded (generation).
  Writing `fetchedAt = now` on that decode was why the network log filled with
  requests and the row never moved: Home trusted the old snapshot for another 60 s.
- Local overlay keeps any further progress already on the card and merges plays after the
  snapshot into the saved activity order.

## Open


Exact dates for viewing on other devices are tracked in
[Library](https://app.asana.com/1/1218266299921477/project/1219403693009374/task/1219403704224202).
