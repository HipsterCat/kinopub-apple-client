# Playback tracks — which dub and which subtitles a title opens with

Audio and subtitles are the first thing a viewer notices and the last thing they want to fix by
hand. This file is what the player is supposed to *decide*; the mechanics live on
`TrackResolver` / `TrackPreferenceLedger`, and the shape of kino.pub's own audio payload is in
[docs/providers/kinopub/video.md](../providers/kinopub/video.md).

kino.pub ships several dubs per episode, and they arrive **over time**: a fresh episode may have a
single two-voice track on Monday and a studio dub on Thursday. Every rule here exists because that
is true.

## Scopes

**prd** — A decision is looked up in this order, first hit wins. The order lives in exactly one
place, `TrackMemoryScope.chain(titleID:season:episode:isAnime:)`:

| Step | Key | Why it exists |
| --- | --- | --- |
| Episode | title id + season + episode | What this very episode last played. A rewatch replays it |
| Season | title id + season number | Studios change between seasons — the team that dubbed S1 may not have done S4 |
| Title | title id | The series or film as a whole |
| Genre | `anime` | *"надо запоминать для аниме его предпочтения, не на тайтл"* — a new anime opens the way the last one did |
| App settings | — | Preferred languages and the dub floor. **Mirrors the system list until it is set** |
| System | — | `Locale.preferredLanguages`, in order |

The last two are not scopes and hold no history: they are the ladder the resolver falls back to when
nothing above answered.

**prd** — A play writes to **every** scope that applies, not only the most specific one. Watching
S2E5 in a studio's multi-voice teaches that episode, the season, the title and — on an anime — the
anime bucket.

**prd** — Only `anime` is a class. It is a kino.pub genre and it is about to be a section of ours;
cartoons (genre 23, `мультфильм`) are **not** anime and do not share the bucket.

## What is remembered

**prd** — A dub is remembered as **language + kind + studio**, never as a rendition name, index or
URL. Those differ between two episodes of one season, so remembering one pre-selects nothing on the
next episode.

**prd** — The weight of a remembered dub is **how many episodes were actually watched with it**, not
how many times a picker was opened. *"Ему похуй, что я одну-две серии так глянул, а 99 других в
нормальной озвучке"* — two episodes of a stopgap must never outrank a season.

**prd** — **A pick in the player is what the next episode opens with.** It is written the moment it
is made — in the system Audio / Subtitles menu as much as in our own — and the scope's latest pick
leads its ladder whatever the counts say, until the viewer picks something else. Counting it as one
play was not enough: a season watched bare is "off" × 9 against "English" × 1, and episode 11 opened
without subtitles again (Sasha, 2026-11-01: *"на второй серии того же сериала … субтитры выключаются
и озвучка меняется"*). Below the pick, entries still rank by count, then recency.

**prd** — A pick is anything on screen that is not what the episode opened with. Picking the
opening track back after another pick is a pick too.

**prd** — Each scope also records **every dub it has ever seen on a menu**. That is what makes a
newly-arrived dub distinguishable from one the viewer has been ignoring all along.

## Choosing

**prd** — With no usable history, the ladder decides: preferred audio languages in order (app
setting, else the system's list), then kind DUB → MVO → DVO → VO → AVO → Orig, audio description
last, studio A–Z, more channels first. This is the same ladder the detail page's Audio column
already sorts by (`AudioTracks.sortKey`).

**prd** — With history, the scope's strongest entry wins, if this episode offers it. If it does not,
the next entry down does — that is the top-1 / top-2 / top-3 fallback. Only when no remembered dub
is on the menu does the ladder decide.

**prd** — **A dub that was never on offer before beats a weak habit.** When a menu contains a dub
this scope has never seen, and it outranks the remembered leader on the ladder, and that leader's
weight is under `TrackPreferenceLedger.confidentWeight` (3), the new dub wins. This is the
"watched the first three episodes before anyone dubbed it properly, came back to five more seasons"
case: the stopgap was never a preference, it was the only thing there.

**prd** — A dub the viewer picked is never that stopgap, whatever its weight.

**prd** — Above that weight the habit wins and the new dub just sits in the menu. A viewer who chose
one studio for ninety-nine episodes does not want a fresh dub from someone else taking over.

**prd** — **A dub floor sends us to the original instead of down the ladder.**
`minimumDubKind` is the worst dub kind still preferred over original audio with subtitles —
*"уж лучше на английском, чем в двухголосой"*. Original and unknown-kind tracks are never filtered
by it: the floor is about dub quality, and an original track is not a dub.

**idea** — `minimumDubKind` ships as `nil` (no floor) so nothing changes silently. Whether the
shipped default should be multi-voice is the owner's call.

## Subtitles

**prd** — **Subtitles are a setting plus the last pick — no counting** (Sasha, 2026-11-01). Whether a
title has subtitles is not a habit that builds over a season; the dub is. The ledger's subtitle
entries are read only where they are picks.

**prd** — The setting is Plex's **Subtitle mode**, because its three answers are the ones a viewer
means:

| Mode | Subtitles come on |
| --- | --- |
| Always enabled | on every title, in the first listed subtitle language it offers |
| Shown with foreign audio | when the audio that plays is in **none of the audio languages** |
| Manually selected | never by themselves |

Until the app's mode is set, the system's captions setting answers it: Accessibility › Subtitles &
Captioning *Always On* is *Always enabled*, anything else *Shown with foreign audio*.

**prd** — **A pick in the player wins over the mode for that title until the next pick** — the latest
one across the episode, season, title and anime scopes. "Off" is a pick like any language. A picked
language the episode does not have falls through to the mode, not to off.

**prd** — **The menu is the master's.** What the subtitles are decided from is the list of
renditions the system player offers, not the API's subtitle list, which can be short or empty for
an episode whose stream has English in it (troubleshooting.md). The API's list only answers
before the stream is open — a card, a Play button.

**prd** — Nothing is written when there was nothing to choose: an item with no subtitle track teaches
nothing.

**prd** — When subtitles are on and none of them are in a listed language, a track the viewer cannot
read still beats nothing. Forced tracks are never a default: they carry signage and alien dialogue
only.

**prd** — Dual subtitles stay where they are (`SubtitlePreferences`, tvOS). They are a deliberate
extra line, not part of what a title opens with.

## Languages

**prd** — Two ordered lists, **audio** and **subtitles**, edited in Settings: add a language
(Ukrainian, say), move it up or down, remove it, or go back to the system's. Until the first change a
list is the system's — preferred languages for audio, caption languages (else the audio list) for
subtitles. The old *Default English subtitles* toggle was written into the subtitle list once, as
English first, where it can now be seen and reordered.

## Anime

**prd** — `animePrefersOriginalAudio` is a global toggle: on an anime, original audio plus subtitles
wins even when a dub exists.

**prd** — The original language is a **heuristic from data we already have** — the countries on the
title against the languages actually on the menu. Japan with a Japanese track means the original is
Japanese. Nothing is fetched for this, and no provider field is added.

## Later

**idea** — Deviating from the system default is a strong signal: a viewer whose system has captions
off and who turns them on here, on title after title, is telling us their app default. Offer to set
it rather than silently accumulating it. The same for audio, once a language keeps being overridden.

**idea** — With English audio and no subtitle track at all, Apple's own generated captions (26/27+)
are the honest filler. **English only** — the quality on other languages does not carry the feature.

## Open

- **Decay.** A ledger entry never ages. If a viewer's taste moves, the new choice has to out-count
  the old one rather than out-date it.
- **Where the answer comes from before the player opens.** The resolver is pure and takes a menu, so
  a card can ask it as soon as it has one — but nothing calls it from outside the player yet. See
  Asana: [Назвать озвучку на кнопке Play](https://app.asana.com/1/1218266299921477/project/1219403693009374/task/1219606561989027).
