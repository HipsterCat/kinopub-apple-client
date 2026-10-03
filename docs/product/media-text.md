# Media text — how a fact is worded, per surface

One wording per fact and length, in both languages. Implemented once in `KinoPubMedia`
(`EpisodeText`, `SeasonText`, `RuntimeText`, `RemainingText`); which surface uses which
length is `MediaSurface` — the one table. A difference between two surfaces is a row there,
never a second helper. Everything below is **prd** (user, 2026-10-03) unless tagged.

## Lengths

Every formatter has three: **short** (a chip, a capsule, a corner), **medium** (a subtitle
line), **long** (spelled out). **VoiceOver always reads long**, whatever the screen shows.

## Episode

| | en | ru |
| --- | --- | --- |
| short | `S1, E1` | `1 сезон, 1 серия` |
| medium | `Season 1, Episode 1` · `S1, E1: Name` | `1 сезон, 1 серия` · `1 сезон, 1 серия: Name` |
| long | `Season 1, Episode 1` · `Season 1, Episode 1: Name` | as medium |

**Only one season known, and it is the first** — the season is not said: `E1` /
`Episode 1` / `Episode 1: Name`, `1 серия` / `1 серия: Name`. The same when the season goes
without saying, on a season's own rail. A name that is only the number again («Эпизод 1»)
is no name.

**The detail page's episodes** — the season switch is right beside them, or there is only one
season: `7. Name`, and with no name `Episode 7` / `Серия 7`. **Everywhere else** the season is
said, the name after a colon: `S1, E1: Name` / `1 сезон, 1 серия: Name` (Up Next), `S1, E1` /
`1 сезон, 1 серия` without one. (User's call, 2026-10-03.)

Continue Watching cards and the hero's capsules carry the season count, so a one-season show
says `E2` / `2 серия` there too.

## Season on its own

`Season 2` / `S2`; ru `2 сезон`. kino.pub's own season titles («Сезон 2») stay as kino.pub
writes them on the season tabs.

## Runtime

| | ru | en |
| --- | --- | --- |
| short | `1ч 53м` · `53м` | `1h 53m` · `53m` |
| medium | `1ч 53 мин` · `53 мин` | `1h 53 min` · `53 min` |
| long | `1 час 53 минуты` | `1 hour, 53 minutes` |

Long is the system's (`Duration.UnitsFormatStyle`), so its plural forms and punctuation
are Foundation's. Rounded to the minute; under a minute is one. Past a day short and medium
count days (`1д 12ч 4м`). Time left: `Ещё 53 мин` / `53 min left`.

## Surfaces

| Surface | Episode | Runtime |
| --- | --- | --- |
| Player subtitle | medium | — |
| Hero capsules | short | medium (time left) |
| Continue Watching card | short | short |
| Up Next tile (player) | short + `: Name` | short |
| Episode tile on the detail page | `7. Name` · `Серия 7` | short |
| History row, context menu, settings row | short | — |
| Corner time chip, detail meta line | — | short |

## Follow, bookmarks, progress

- **Follow is a series' alone**; a film is kept with bookmarks, and has no follow or
  watchlist. Hero: «Отслеживать» / «Отслеживаю»; menu: «Отслеживать» / «Не отслеживать».
- **Downloaded is progress, like watched**: a series or a season shows how much of it is
  watched and how much is on the device, as a ring or a percentage (`ViewerState`'s
  `watchedEpisodes` / `downloadedEpisodes`). **Only whole episodes count as watched**, and a
  series or season shows no runtime there; partial downloads count by their progress.
