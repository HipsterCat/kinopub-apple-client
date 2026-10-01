# Media actions — labels and order

Where to look: this file (`docs/product/media-actions.md`), and the live mold
`#Preview("Action chrome")` in `MediaActionButtonStyle.swift`.

White / elevated fill is **focus**, not a permanent Play tint.

## Episode & time format (prd)

| Locale | Episode (with progress bar) | Fresh unwatched Play | Remaining time |
| --- | --- | --- | --- |
| **ru** | `1 сезон, 2 серия` | `1 сезон, 1 серия` | `Ещё 53 мин` · `Ещё 1ч 24м` |
| **en** | `S1, E2` | `Play S1, E1` | `53 min left` · `1h 24m left` |

- Compact `S1, E2` / bare episode phrase is **only** when the progress bar is on the capsule.
- Unwatched series EN is `Play S1, E1` — not bare `S1, E1`.
- Series in progress: progress bar + episode label only (no time on the capsule).
- Film in progress: progress bar + remaining time only (`Ещё …` / `… left`).

## Fresh Play title by kind (prd)

| Kind | EN | RU |
| --- | --- | --- |
| Fiction / animation / documentary film | Watch Movie | Смотреть фильм |
| Concert / stand-up | Watch Now | Смотреть |
| Series / show / docuseries (unwatched) | `Play S1, E1` | `1 сезон, 1 серия` |
| Series watched (replay) | `Replay S1, E1` | `↻ 1 сезон, 1 серия` |
| Film watched | Play Again | Пересмотреть |

## Row order by scenario

Legend: `[pill]` · `(circle)` · `…` = More (tvOS)

### Movie · unwatched
`[Смотреть фильм]` · `[Трейлер]` · `(bookmark)` · `(✓)` · `(download)` · `(…)`

### Movie · in progress
`[▶ ▬ Ещё 53 мин]` · `[Просмотрено]` · `[Трейлер]` · `(bookmark)` · `(download)` · `(…)`

### Movie · watched
`[↻ Пересмотреть]` · `[Трейлер]` · `(bookmark)` · `(download*)` · `(…)`  
\* download only while not yet on disk — see Download below.

### Series · unwatched
`[1 сезон, 1 серия]` / `[Play S1, E1]` · `[Трейлер]` · `(bookmark)` · `(bell)` · `(✓)` · `[Случайно]†` · `(…)`  
† labelled Shuffle/Random when Mark Watched is not already a pill in the row.

### Series · in progress
`[▶ ▬ 1 сезон, 2 серия]` · `[Просмотрено]` · `[Трейлер]` · `(bookmark)` · `(bell)` · `(shuffle circle)` · `(…)`

### Series · watched / rewatch
`[↻ 1 сезон, 1 серия]` · `[Случайно]` · `[Трейлер]` · `(bookmark)` · `(bell)` · `(…)`

### Series · awaiting next episode (promote Follow)
When the series is **ongoing**, **everything watched**, and the **next episode airs within ~2 weeks** (same season / next to air):

`[🔔 Отслеживать]` · `[Трейлер]` · `[↻ Пересмотреть]` · `(bookmark)` · `(…)`

Follow is the labelled primary; Play is demoted to Replay beside Trailer.

### Concert / documentary (non-episodic)
Same shape as movie, with the kind-specific Play title. No follow. No shuffle.

### Loading
Same chrome; glyph/title swapped for a fixed-size spinner (row must not reflow).

## Download (prd)

Available on **any** title (when downloads are enabled on the platform) — not a series-only control.

| Phase | Button | More (`…`) |
| --- | --- | --- |
| Not downloaded | `(download)` circle | — |
| Downloading | same slot: **circular progress + pause** | — |
| Downloaded | **gone** from the row | **Delete download** |

Tap idle download = start current title/episode.  
**Long-press** on series download: whole season · all unwatched in season · all episodes.

## Interactions (prd)

- **Mark Watched:** tap = mark current episode/film. **Long-press** (series): current episode · whole season · all unwatched in season · all episodes.
- **Bookmark:** multi-select folders, section **Bookmarks / Закладки**, New Folder; menu stays open.
- **Shuffle:** random unwatched episode when the title has enough episodes; labelled pill as a Trailer peer, circle when the row is mid-title.
- **Follow:** circle by default; **labelled primary** in the awaiting-next-episode case above.
