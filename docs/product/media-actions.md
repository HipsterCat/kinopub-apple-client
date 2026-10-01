# Media actions — labels and order

Where to look: this file (`docs/product/media-actions.md`), and the live mold
`#Preview("Action chrome")` in `MediaActionButtonStyle.swift`.

White / elevated fill is **focus**, not a permanent Play tint.

## Episode & time format (prd)

| Locale | Episode            | Remaining time |
|--------|--------------------|----------------|
| **ru** | `1 сезон, 2 серия` | `34 мин`       |
| **en** | S1, E2             | `34 min`       |

**Not** `S1, E2`. **Not** `S1, E2 · 34m` on the play capsule.

- Series in progress: progress bar + episode label only.
- Film in progress: progress bar + remaining minutes only.

## Fresh Play title by kind (prd)

| Kind                       | EN                     | RU                     |
|----------------------------|------------------------|------------------------|
| Fiction / animation film   | Watch Movie            | Смотреть фильм         |
| Documentary film           | Watch Movie            | Смотреть фильм         |
| Concert                    | Watch Now              | Смотреть               |
| Stand-up                   | Watch Now              | Смотреть               |
| Series / show / docuseries | *(episode label only)* | *(episode label only)* |
| Watched (not series)       | Play Again             | Пересмотреть           |

## Row order by scenario

Legend: `[pill]` · `(circle)` · `…` = More (tvOS)

### Movie · unwatched
`[Watch Movie / Смотреть фильм]` · `[Trailer / Трейлер]` · `(bookmark)` · `(✓)` · `(download*)` · `(…)`

### Movie · in progress
`[▶ ▬ 53 min left / Ещё 53 мин / Ещё 1ч 24м / 1h 24m left]` · `[Mark as Watched / Просмотрено]` · `[Trailer]` · `(bookmark)` · `(download*)` · `(…)`

### Movie · watched
`[↻ Play Again / Пересмотреть]` · `[Trailer]` · `(bookmark)` · `(download*)` · `(…)`

### Series · unwatched
`[1 сезон, 1 серия / Play S1, E1]` · `[Trailer]` · `(bookmark)` · `(bell)` · `(✓)` · `(shuffle†)` · `(…)`  
† Shuffle is a **labelled** pill `Случайно` / `Random` when Mark Watched is not a pill in the row.

### Series · in progress
`[▶ ▬ 1 сезон, 2 серия / S1, E2]` · `[Просмотрено / Mark Watched]` · `[Трейлер / Trailer]` · `(bookmark)` · `(bell)` · `(shuffle circle)` · `(…)`

### Series · watched / rewatch
`[↻ 1 сезон, 1 серия / Replay S1, E1]` ·  `[Случайно/Random]` ·`[Трейлер/Trailer]` · `(bookmark)` · `(bell)` · `(…)`

### Concert / documentary (non-episodic)
Same shape as movie, with the kind-specific Play title above. No follow bell. No shuffle.

### Loading
Same chrome, glyph/title replaced by a fixed-size spinner (row must not reflow).

## Interactions (prd)

- **Mark Watched:** tap = mark current; long-press = episode vs season (series only).
- **Bookmark:** multi-select folders, section **Bookmarks / Закладки**, New Folder; menu stays open.
- **Shuffle:** random unwatched episode when the title has enough episodes; labelled pill when it is a peer of Trailer, circle when the row is already dense (in progress).
