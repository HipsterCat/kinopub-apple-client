# Playback info — what the system player is told about what is playing

Implemented by `PlayerInfo` (KinoPubMedia), projected from a `MediaContext`. Where the facts come
from and which source wins is the media model's business ([docs/media-model.md](../media-model.md)); this file is only what reaches the screen.

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

**prd — no year on an episode** (Sasha, 2026-10-20: not before the episode line in the title
view). AVKit has one date slot and draws it in both the title view and the Info tab's line, so
the episode's goes from both; a film and a trailer keep theirs. **Apple API limitation:** a
string under `iTunesMetadataReleaseDate` lands in the same slot, `quickTimeMetadataYear` in
neither (tvOS 26.5 simulator, 2026-10-20). Re-probe on the next SDK.

**Not on the list, deliberately:** scores (IMDb, Kinopoisk, TMDB, per episode or per title). No
identifier carries one — `iTunesMetadataContentRating` is the *age* rating. Scores, capability
badges and the season's facts are our own Info tab (`customInfoViewControllers`, Asana task [Player](https://app.asana.com/1/1218266299921477/project/1219403693009374/task/1219403704224201)).

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

**prd — An episode is known by its show.** Title: the show's name. Subtitle: the episode at
medium length ([media-text.md](media-text.md)) — *S2, E5: Name* / *2 сезон, 5 серия: Name*,
*Season 2, Episode 5* without a name, and *Episode 1: Name* / *1 серия: Name* when the show has
only its first season. The name is dropped when it only repeats the title line. (User's spec,
2026-10-03; was «Сезон 2, Серия 5: Name».)

**prd — An episode borrows its show's genres and age rating**, and its description when it has
none of its own: a line about the show beats an empty panel. Its **own** description, date and
still come from TMDB when kino.pub has none, which is always.

**idea — Scores are never inherited.** A show's 8.8 on one of its episodes would be a number nobody
gave that episode. (Not in the panel at all today — see above — but the model already refuses it.)

**prd — A trailer is its film or show.** Title, description, genre, rating and poster are the
title's, and there is **no subtitle**: the Info tab's heading is the subtitle when there is one, and
«Trailer» there said nothing (user's call, 2026-10-01). Its Info tab has one button, *Go to Movie /
Show* — no *From Beginning*.

**Apple API limitation, unprobed — the trailer's own runtime and HD/CC badges.** «1 min 57 sec · HD ·
CC» in a trailer's Info tab is what AVKit reads off the trailer *stream*; no `externalMetadata`
identifier sets or hides a runtime or those badges. Not probed beyond that — re-check
`AVPlayerItem`'s presentation options on the next SDK before calling it settled.

**idea — A version of a film says which.** One of a multi-version film's editions (24/48 fps)
carries its name as the subtitle.

**idea — Nothing empty is sent.** An empty line reserves the space in the panel. Kept from the old
panel.

## Per kind

| Playing | Title | Subtitle | Description | Genre | Artwork |
| --- | --- | --- | --- | --- | --- |
| Film | film | — | film | film's primary | poster → backdrop |
| Film edition | film | edition name | film | film's primary | poster → backdrop |
| Episode | show | SN, EM: name (media-text.md) | episode → season → show | show's primary | still → season poster → show poster |
| Trailer | film/show | — | film/show | film/show's primary | trailer frame → film poster |
| Concert | concert | — | concert | first music genre | poster |
| Documentary | film/show | as above | as above | Documentary | as above |
| Download | saved name | — | title, if still cached | title's, if cached | saved poster |

**prd — A number spelled out is not a name.** «Эпизод 1», «Серия 3», "Episode 12", "S01E01" in
the title field are the episode's number, not its name (`EpisodeTitle`): they lose to a real name
from any source, and with none the line is just *Season 1, Episode 1*. Same on the episode rail.
(User's call after the device check, 2026-09-29.)

## Seen on device (2026-09-29)

- Poster, description, one genre, runtime and age rating show for films and episodes; the episode
  shows its own still.
- **A number where the year should be** — «Action · 12175 · 1 hr 38 min · 16+», and in the title
  view «12171 • Season 1, Episode 1». Reproduced and fixed on the tvOS 27.2 simulator
  (2026-09-30): AVKit does not read a date-shaped *string* as a date — `"2025"` rendered
  **2026**, `"2025-01-01"` rendered **12169**. A string with a time, an `NSDate`, and the same
  under `quickTimeMetadataCreationDate` all render 2025; omitting it drops the year. It is now
  sent as an `NSDate` at **noon UTC** — the panel formats in the viewer's time zone, and midnight
  showed 2024 under `Pacific/Honolulu`. A year-only release becomes 1 January of that year in
  `PlayerInfo.metadataItems()` and nowhere else; the model keeps year precision. Not yet seen
  on a physical Apple TV.
- No *Next Episode* and no *Go to Show / Go to Movie* — built 2026-09-30, see below.

## Info tab buttons (tvOS)

`AVPlayerViewController.infoViewActions`, the system's own buttons. iOS and macOS have no such
surface and get no substitute.

- *Go to Show* (an episode, or a series' trailer) / *Go to Movie* (a film or its trailer) —
  decided by the media model's context, not by what Swift type is playing. Leaves the player for
  the title's page. When the page is already the route under the player it is a plain pop; otherwise the
  page takes the player's place.
- *From Beginning* (the system's own) stays on top. **prd** — *Next Episode* is not an Info button:
  the Up Next tab carries it (user's call, 2026-09-30).
- **Apple API limitation — two buttons at most.** The SDK header says "up to 2", and on the tvOS
  27.2 simulator a third was dropped whatever its order. Two is what this needs. Re-probe on the
  next SDK.

**Season tab (tvOS).** After Up Next, a series only.

- **prd** — A series' Info strip is **Info**, **Up Next** / **Далее**, then **Season N** / **Сезон N**:
  the season playing, alone — no season pills, no other seasons (those are on the title page).
  Same episode cells as the page (`MediaCard(episode:in:)`), in one `TVUIKitMediaItemRail`, so the
  tab is exactly as tall as Up Next and the strip does not move between them. The rail opens parked
  on the episode playing and Down from the tab lands on it. Select plays that episode in place. A
  film has no Season tab. (Sasha, 2026-10-20; replaces the 2026-10-15 Episodes tab before Up Next.)
- **prd** — The episode playing is marked: its still dimmed, a ring round it at rest (hidden while
  focused, so the high-contrast focus style never doubles it), its caption in the primary colour,
  its runtime instead of a progress bar. (Sasha, 2026-10-20.)
- Watched and part-watched on these tiles are this device's progress over the payload
  (`ViewerStateReading`): the series snapshot is the one cached when the player opened, so after
  auto-play went through episodes 2–4 it still said only episode 1. The tab is built for every
  episode the player swaps in, so it is read once per episode — nothing is recounted while one plays.
- **Platter.** Up Next and Season sit on the same platter AVKit draws under its own Info tab: player
  glass (`kinoPlayerGlass`), corners ≈ 46 pt, on the strip's margins, clipping the rail at its edges
  so a tile scrolled off the side shows a sliver. Measured off the tvOS 27.2 simulator.

**Up Next tab (tvOS).** Right after Info; the Apple-TV way.

- **prd** — First, **this show's next unwatched episode**, when there is one, flagged *Next episode*.
  Then **Continue Watching** — Home's own list, the same cards, minus the title playing now.
  **Never anything watched.** (User's call, 2026-10-01; replaces "the next six episodes".)
- The episode tile's name and frame are the media model's, the same as the Info tab's: kino.pub's,
  then TMDB's once it answers; «Эпизод 3» never shows as a name. The frame is kino.pub's when it has
  one (full-size, the file that plays), TMDB's otherwise (`MediaPrecedence` `.still`).
- Selecting a tile plays it in place — a Continue Watching card through the same resolution Home's
  Play uses (`MediaCardMenuCoordinator.resolve`). **Apple API limitation:** nothing native
fills a tab with next-episode cards; AVKit draws only the tab strip (`customInfoViewControllers`),
so the content is a hosted `TVUIKitMediaItemRail`. Seen working in the tvOS simulator with the real
app (2026-09-30): tab, tiles, badge, swap. Not seen on a physical Apple TV.

## End of playback

**prd** — A film always dismisses when the stream ends.

**prd** — A series follows Settings › Video & audio (Sasha, 2026-10-13):

- **Auto-Play Next Episode** (default on) plays the next episode in the **same season**.
- **Continue to Next Season** (default off) also plays the next season's opener when this
  one was the finale. Ignored while auto-play is off.
- Auto-play off: the player dismisses at episode end, including mid-season.

**prd** — A next episode missing from the payload, or listed with an empty files ladder,
is unavailable: dismiss, do not skip past it to a later season. (`nolinks=1` still names
the ladder, so it auto-plays.)

The tvOS Up Next `AVContentProposal` (10 s countdown) offers the same next episode the
end-of-stream path would play. Accepting swaps in place; rejecting pops the player.

## Not decided

- **A "Next Episode" prompt during playback.** The Up Next `AVContentProposal` at the credits
  already exists (10 s countdown) and follows the Settings above. Whether `contextualActions`
  should also offer it earlier (proposed: the last 60 s, or the credits once markers exist)
  is the user's call.

- **Where `commonIdentifierCreationDate` shows at all.** Not in Apple's documented set.

## Verification

**Player cases** (DEBUG: tvOS Settings → Diagnostics, iOS/macOS Settings → Advanced → UI Lab) lists
every case above on live titles, each row showing what we send and what this file expects, one press
from the real player. Check a case there, not by hunting for a title.

The **prd** rules above are the user's (2026-09-28), unit-tested field by field (`PlayerInfoTests`, `MediaContextTests`,
`KinoPubMediaMappingTests`) — but none of it has been watched in the tvOS Info tab yet. The genre
fix rests on Apple's documentation, not on a device.
