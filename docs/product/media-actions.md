# Media actions — labels and order

Where to look: this file (`docs/product/media-actions.md`), and the live mold
`#Preview("Action chrome")` in `MediaActionButtonStyle.swift`.

White / elevated fill is **focus**, not a permanent Play tint.

## Episode & time format (prd)

| Locale | Episode | Remaining time |
| --- | --- | --- |
| **ru** | `1 сезон, 2 серия` | `34 мин` |
| **en** | `Season 1, Episode 2` | `34 min` |

**Not** `S1, E2`. **Not** `S1, E2 · 34m` on the play capsule.

- Series in progress: progress bar + episode label only.
- Film in progress: progress bar + remaining minutes only.

## Fresh Play title by kind (prd)

| Kind | EN | RU |
| --- | --- | --- |
| Fiction / animation film | Watch Movie | Смотреть фильм |
| Documentary film | Watch Documentary | Смотреть док |
| Concert | Watch Concert | Смотреть концерт |
| Stand-up | Watch | Смотреть |
| Series / show / docuseries | *(episode label only)* | *(episode label only)* |
| Watched (any) | Play Again | Пересмотреть |

## Row order by scenario

Legend: `[pill]` · `(circle)` · `…` = More (tvOS)

### Movie · unwatched
`[Watch Movie / Смотреть фильм]` · `[Trailer / Трейлер]` · `(bookmark)` · `(✓)` · `(download*)` · `(…)`

### Movie · in progress
`[▶ ▬ remaining]` · `[Mark as Watched / Просмотрено]` · `[Trailer]` · `(bookmark)` · `(download*)` · `(…)`

### Movie · watched
`[↻ Play Again / Пересмотреть]` · `[Trailer]` · `(bookmark)` · `(download*)` · `(…)`

### Series · unwatched
`[1 сезон, 1 серия]` · `[Trailer]` · `(bookmark)` · `(bell)` · `(✓)` · `(shuffle†)` · `(…)`  
† Shuffle is a **labelled** pill `Случайно` / `Shuffle` when Mark Watched is not a pill in the row.

### Series · in progress
`[▶ ▬ 1 сезон, 2 серия]` · `[Просмотрено]` · `[Trailer]` · `(bookmark)` · `(bell)` · `(shuffle circle)` · `(…)`

### Series · watched / rewatch
`[↻ Пересмотреть]` · `[Trailer]` · `(bookmark)` · `(bell)` · `[Случайно]` · `(…)`

### Concert / documentary (non-episodic)
Same shape as movie, with the kind-specific Play title above. No follow bell. No shuffle.

### Loading
Same chrome, glyph/title replaced by a fixed-size spinner (row must not reflow).

## Interactions (prd)

- **Mark Watched:** tap = mark current; long-press = episode vs season (series only).
- **Bookmark:** multi-select folders, section **Save to / Добавить в**, New Folder; menu stays open.
- **Shuffle:** random unwatched episode when the title has enough episodes; labelled pill when it is a peer of Trailer, circle when the row is already dense (in progress).
