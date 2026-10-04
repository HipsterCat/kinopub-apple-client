# Media actions — labels and order

Where to look: this file (`docs/product/media-actions.md`), and the live mold
`#Preview("Action chrome")` in `MediaActionButtonStyle.swift`.

White / elevated fill is **focus**, not a permanent Play tint.

## Episode & time format (prd)

| Locale | Episode (with progress bar) | Fresh unwatched Play | Remaining time |
| --- | --- | --- | --- |
| **ru** | `1 сезон, 2 серия` | `1 сезон, 1 серия` | `Ещё 53 мин` · `Ещё 1ч 24 мин` |
| **en** | `S1, E2` | `Play S1, E1` | `53 min left` · `1h 24 min left` |

Episode and time wording come from [media-text.md](media-text.md) (short episode, medium time).

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

### Movie · several versions (`videos` > 1)
`[▶ 24 fps]` · `[▶ 48 fps]` · `[Трейлер]` · `(bookmark)` · `(✓)` · `(…)`

One play pill per version, for the **first two** in number order; a third version is
not a button (the Versions rail under the hero has it). Play icon, labelled with the
version's name; without names `[Смотреть]` · `[Вторая версия]`. Each pill carries **its own**
version's state: progress bar when started, `↻` and the quieter pill when watched. The
first stays the filled play pill. `(✓)` stays a circle here even mid-title.
(Sasha, 2026-10-03.)

### Series · unwatched
`[1 сезон, 1 серия]` / `[Play S1, E1]` · `[Трейлер]` · `(bookmark)` · `(bell)` · `(✓)` · `(…)`  
Shuffle (icon before `…`) only when seasons > 5 and not subscribed — see below.

### Series · in progress
`[▶ ▬ 1 сезон, 2 серия]` · `[Просмотрено]` · `[Трейлер]` · `(bookmark)` · `(bell)` · `(…)`

### Series · watched / rewatch
`[↻ 1 сезон, 1 серия]` · `[Трейлер]` · `(bookmark)` · `(bell)` · `(…)`

### Series · awaiting next episode (promote Follow)
When the series is **ongoing**, **everything watched**, and the **next episode of the
last season on kino.pub has a date** on TMDB — ahead (any distance) or already aired and
not uploaded yet. The next episode opening another season does not count. (Sasha,
2026-10-03; was "airs within ~2 weeks".)

`[🔔 Отслеживать]` · `[Трейлер]` · `[↻ Пересмотреть]` · `(bookmark)` · `(…)`

Follow is the labelled primary; Play is demoted to Replay beside Trailer.

**Focus:** the page opens on the row's main control (Follow here, else Play — Replay
included) and comes back to it from the player, even when the row changed meanwhile
(the last episode watched turns Play into Follow + Replay).

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
- **Shuffle:** interim — icon circle immediately before More, only when the series has
  **more than 5 seasons** and is **not** on the watchlist. Never a labelled pill (that
  taller focus plate lifted the whole hero). Finer unwatched-count rules deferred.
- **Follow:** circle by default; **labelled primary** in the awaiting-next-episode case above.
