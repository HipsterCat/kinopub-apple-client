# Continue Watching

What the Home row offers, in what order, and what it deliberately leaves out.

The row is one merge of `/v1/watching/movies`, `/v1/watching/serials` (subscribed and not) and
`/v1/history`, plus local resume points the server has not heard about yet. Field-level detail of
those payloads is in [docs/providers/kinopub/watching.md](../providers/kinopub/watching.md); the
mechanics are on `ContinueWatchingOrder` and `ContinueWatchingLocalOverlay`.

## What the row is for

**prd** — It is "carry on with what you were doing", not the watching list. The whole watching list
is the Library tab, which is where the row's header chevron goes.

**prd** — It is capped (`ContinueWatchingOrder.maxItems`). `/v1/watching/serials` returns every
unfinished serial on the account — hundreds, for a long-lived one — and past the first screen that
is a list of things abandoned years ago. A sideways scroll with no end defeats the point of the row.

**prd** — On tvOS the row is five 16:9 stills across (HIG 5-column). The title stays under the
tile at rest, not only on focus.

## Order

**prd** — Buckets first, in this order: played in the last week · on the watchlist with new episodes
· the rest of the watchlist · everything else unfinished.

**prd** — Inside a bucket, most recently played wins. An unstarted *next episode* has no date of
its own: it takes the newest `last_seen` among that series' rows in the `/v1/history` page we
already fetched (finished episodes included). No extra request.

**prd** — Where neither title has a date, **the smaller backlog wins** — `new`, the count of
unwatched episodes. One or two waiting is a title being followed; a hundred and seventy is a title
abandoned. This exists because the watching endpoints carry **no timestamp at all**: the only dates
come from the page of `/v1/history` we fetch, so most of the row is date-less and the tie used to fall
to the server's own list order.

**prd** — A film counts as backlog zero. It has no episode counters, and a half-watched film is one
press from finished, so it belongs above a serial with a season to go.

## What stays out

**prd** — A title only *local* progress knows about needs `WatchProgress.enterContinueWatchingSeconds`
before it earns a card. The 10 s "has started" floor is for painting a progress bar on a card that is
already there; a card the server never listed has nothing to take it back out again, and a trailer
sampled for a minute is not something to carry on with.

**prd** — A finished film leaves the row. A finished *episode* does not remove the series — it steps
it to the next episode.

**prd** — Abandoned titles leave the row. Thresholds (on `ContinueWatchingOrder`):

| Rule | Threshold | Stays if |
| --- | --- | --- |
| Not touched | **90 days** (`abandonedAfter`) | on the watchlist |
| No date in the fetched history page | — | on the watchlist |
| Barely started (`position` < 90 s) | **14 days** (`barelyStartedAfter`) | never — sampling is not continuing |
| Watchlist + new episodes | — | always |

The Library tab still has the whole watching list.

**prd** — The row never pages. "Page 2" of a four-source merge has no meaning on the server.

## Refresh

The cached snapshot is a 60 s TTL. That is not "the row never updates":

- **Foreground** (Watch Now `scenePhase == .active`) refetches Continue Watching even inside the TTL, so progress written on another device lands when the user comes back.
- **Mark watched / hide / follow** on the detail page invalidates the `.watch` family. That posts `contentStoreDidInvalidateWatch`; Home refetches instead of painting the cached cards. Marking a film watched also writes a local finished tombstone, so overlay hides the card before the refetch returns — without it, overlay re-inserted the in-progress playhead onto a title `watching/movies` had already dropped.
- An in-flight fetch that started **before** an invalidate is discarded (generation). Writing `fetchedAt = now` on that decode was why the network log filled with requests and the row never moved: Home trusted the old snapshot for another 60 s.
- Local overlay does not paint a playhead that is **behind** the snapshot (other-device progress already on the card). It still leads the row for progress this device wrote that the server has not heard yet.

## Open

Dates for more of the row would need more of `/v1/history` (`perpage` maxes at 50, and one page of
20 already measured ~96 KB on a cold launch), so it is a payload trade, not a free improvement.
See [ROADMAP.md](../../ROADMAP.md).
