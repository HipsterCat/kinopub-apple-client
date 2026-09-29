# Playback info — what the system player is told about what is playing

Implemented by `PlayerInfo` (KinoPubMedia), projected from a `MediaContext`. Where the facts come
from and which source wins is the media model's business (`metadata-service` skill, "The media
model"); this file is only what reaches the screen.

## The fields

Apple's documented set for the system player (AVKit, *Customizing the tvOS Playback Experience*),
the same `externalMetadata` that feeds iOS Now Playing, Control Center, the lock screen and AirPlay:

| Field | Identifier | Shows in |
| --- | --- | --- |
| Title | `commonIdentifierTitle` | title view above the transport bar |
| Subtitle | `iTunesMetadataTrackSubTitle` | title view |
| Artwork | `commonIdentifierArtwork` | Info tab |
| Description | `commonIdentifierDescription` | Info tab |
| Genre | `quickTimeMetadataGenre` | Info tab |
| Age rating | `iTunesMetadataContentRating` | Info tab |

Plus `commonIdentifierCreationDate` (ISO 8601), which is **not** in that documented set — sent
because it costs nothing and other readers of `externalMetadata` may show it.

**Not on the list, deliberately:** scores (IMDb, Kinopoisk, TMDB, per episode or per title). No
identifier carries one — `iTunesMetadataContentRating` is the *age* rating. Scores, capability
badges and the season's facts are our own Info tab (`customInfoViewControllers`, ROADMAP stage 7).

## Rules

**prd — One genre.** The genre field carries the **primary** genre only, never a comma list. Apple
shows one word where space is short — Ted Lasso is *Comedy* on its card though filed under Comedy
and Sport. The primary genre is the first of the title's genres (`MediaEntity.genres`).

**prd — A concert leads with its music genre.** A concert's genres are music genres (Electronic,
Trance…); *Concert* is filed after them, so it is never the one word shown.

**prd — A documentary leads with Documentary**, as Apple files it; its subject (History, Nature…)
follows. (User's call, 2026-09-29.)

**prd — "Эксклюзив" is not a genre, and it is kept.** kino.pub lists it among genres (128, 133);
it says who carries the copy, not what the work is, so it never becomes the one word shown. It is a
`MediaLabel` on the title, with kino.pub's own key (`genre:128`), for badges, filters and sections.
(User's call, 2026-09-29.)

**prd — An episode is its own cover.** The artwork for an episode is **its own still**; the season's
poster, then the show's, only stand in when it has none. (Until 2026-09-28 the series poster always
won — reversed on the user's call.)

**prd — An episode is known by its show.** Title: the show's name. Subtitle: *Сезон 2, Серия 5:
Name* (localized), the name dropped when it only repeats the title line.

**prd — An episode borrows its show's genres and age rating**, and its description when it has
none of its own: a line about the show beats an empty panel. Its **own** description, date and
still come from TMDB when kino.pub has none, which is always.

**idea — Scores are never inherited.** A show's 8.8 on one of its episodes would be a number nobody
gave that episode. (Not in the panel at all today — see above — but the model already refuses it.)

**prd — A trailer describes its film.** Title, description, genre and poster are the film's; the
subtitle says *Трейлер*.

**idea — A version of a film says which.** One of a multi-version film's editions (24/48 fps)
carries its name as the subtitle.

**idea — Nothing empty is sent.** An empty line reserves the space in the panel. Kept from the old
panel.

## Per kind

| Playing | Title | Subtitle | Description | Genre | Artwork |
| --- | --- | --- | --- | --- | --- |
| Film | film | — | film | film's primary | poster → backdrop |
| Film edition | film | edition name | film | film's primary | poster → backdrop |
| Episode | show | Season N, Episode M: name | episode → season → show | show's primary | still → season poster → show poster |
| Trailer | film/show | Trailer | film/show | film/show's primary | trailer frame → film poster |
| Concert | concert | — | concert | first music genre | poster |
| Documentary | film/show | as above | as above | Documentary | as above |
| Download | saved name | — | title, if still cached | title's, if cached | saved poster |

## Not decided

- **idea — an episode's date falls back to its show's first year.** Kept from the old panel; a
  season 5 episode then shows the show's premiere year when neither TMDB nor kino.pub dated it.
- **Where `commonIdentifierCreationDate` shows at all.** Not in Apple's documented set.

## Verification

The **prd** rules above are the user's (2026-09-28), unit-tested field by field (`PlayerInfoTests`, `MediaContextTests`,
`KinoPubMediaMappingTests`) — but none of it has been watched in the tvOS Info tab yet. The genre
fix rests on Apple's documentation, not on a device.
