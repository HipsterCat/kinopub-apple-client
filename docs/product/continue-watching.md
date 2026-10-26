# Continue Watching

What the Home row offers, in what order, and what it deliberately leaves out.

**kino.pub already has Continue Watching.** The row is that data, with the least extra
machinery. Field-level detail of the payloads is in
[docs/providers/kinopub/watching.md](../providers/kinopub/watching.md); the mechanics are on
`ContinueWatchingOrder` and `ContinueWatchingLocalOverlay`.

## Native lists are the backbone

**prd** — Membership comes from the watching API, in this order of trust:

| List | What it is | On the row |
| --- | --- | --- |
| `/v1/watching/movies` | Unfinished films | Always (native) |
| `/v1/watching/serials?subscribed=1` | Series marked «Буду смотреть» / Following | Always (native) |
| `/v1/watching/serials?subscribed=0` | Every unfinished series on the account | Only if still touched within **90 days** |
| `/v1/history` | Per-play dates, and a title the lists missed | Dates; gap-fill under the same 90-day rule |
| This device's resume | Dates the server has not heard yet | Same as history; never overwrites a newer history date |

**prd** — History is not the backbone. The watching lists are capped and drop a series
once every episode is watched, so a next-up title can be missing from them: history (and
this device) may add that title, dated by the newest play of the series. That is the
supplement, not a second watching list.

**prd** — The watching list payloads carry **no timestamp**. Ranking uses the newest of
history `last_seen` (collapsed per title, so an unstarted next episode inherits the
series' last watch) and this device's resume `updatedAt`. A stale Apple TV date must not
beat a later watch on the phone.

## What the row is for

**prd** — It is "carry on with what you were doing", not the watching list. The whole
watching list is the Library tab, which is where the row's header chevron goes.

**prd** — It is capped at 20 (`ContinueWatchingOrder.maxItems`). `subscribed=0` returns
every unfinished serial — hundreds, for a long-lived account — and past the first screen
that is a list of things abandoned years ago.

**prd** — On tvOS the row is five 16:9 stills across (HIG 5-column). The title stays under
the tile at rest, not only on focus.

## Order

**prd** — Newest play first, using that max date. A title with a date outranks a native
list member that has none in the history page we fetched. On a tie, a native member
(`movies` / `subscribed=1`) beats `subscribed=0`. Then the smaller backlog (`new`), then
the list's own order.

**prd** — A film counts as backlog zero. It has no episode counters, and a half-watched
film is one press from finished, so it belongs above a serial with a season to go when
neither has a date.

## What stays out

**prd** — A title only *local* progress knows about needs
`WatchProgress.enterContinueWatchingSeconds` before it earns a card. The 10 s "has started"
floor is for painting a progress bar on a card that is already there; a card the server
never listed has nothing to take it back out again.

**prd** — A finished film leaves the row. A finished *episode* does not remove the series —
it steps it to the next episode.

**prd** — Abandoned titles leave the row. Thresholds (on `ContinueWatchingOrder`):

| Rule | Threshold | Stays if |
| --- | --- | --- |
| Not touched | **90 days** (`abandonedAfter`) | on a native list (`movies` or `subscribed=1`) |
| No date in history / this device | — | on a native list |
| Barely started (`position` < 90 s) | **14 days** (`barelyStartedAfter`) | never — sampling is not continuing |
| `subscribed=0` | same 90 / 14-day rules | recently touched |

The Library tab still has the whole watching list. Bookmarks are not mixed into this row.

**prd** — The row never pages. "Page 2" of a native-list merge has no meaning on the server.

## Which episode a card offers

**Watched is 85% of the runtime, kino.pub's own rule** (Sasha, 2026-10-16: "the credits are where
people stop; offering their remnant is cringe"). Probed with `marktime` on a 3392 s episode: 84.99%
unwatched, 85.02% watched, recomputed from the current play head every time. `WatchProgress`
uses the same number, so a play head with no flag beside it (this device's, a history row) reads
as the server will.

**The title's own payload decides, with the server's watched flags — the same answer the detail
page gives** (Sasha, 2026-10-16: VisionQuest S1E2 was watched on its page and "in progress" on
Home). The row asks `/v1/items/{id}` for every series in it, and for every title the server's
watching lists do not carry (it came from history or this device: leaving those lists is the
server saying "done"). A payload is reused for the session until its title moves — the server's
counts, its newest history row or this device's play head — so a refresh after nothing happened
costs no request.

History alone only has a play head, and counts span the whole series, so a guess from them
(`ContinueWatchingEpisode.forSeries`, used when a payload could not be had) treats the watched
count as an episode number in the first season only.

## Refresh

The cached snapshot is a 60 s TTL. That is not "the row never updates":

- **Foreground** (Watch Now `scenePhase == .active`) refetches Continue Watching even inside the TTL, so progress written on another device lands when the user comes back.
- **Mark watched / hide / follow** on the detail page invalidates the `.watch` family. That posts `contentStoreDidInvalidateWatch`; Home refetches instead of painting the cached cards. Marking a film watched also writes a local finished tombstone, so overlay hides the card before the refetch returns — without it, overlay re-inserted the in-progress playhead onto a title `watching/movies` had already dropped.
- An in-flight fetch that started **before** an invalidate is discarded (generation). Writing `fetchedAt = now` on that decode was why the network log filled with requests and the row never moved: Home trusted the old snapshot for another 60 s.
- Local overlay does not paint a playhead that is **behind** the snapshot (other-device progress already on the card). It still leads the row for progress this device wrote that the server has not heard yet.

## Open

Dates for more of the row would need more of `/v1/history` (`perpage` maxes at 50, and one page of
20 already measured ~96 KB on a cold launch), so it is a payload trade, not a free improvement.
Tracked in Asana: [Library](https://app.asana.com/1/1218266299921477/project/1219403693009374/task/1219403704224202).
