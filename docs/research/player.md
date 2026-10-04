# Player (AVKit)

## How we do it now
`AVPlayerViewController` populated with `externalMetadata`, `infoViewActions` (From Beginning, Go to Show) and an Up Next info tab; stock audio/subtitle menus; per-show subtitle memory. No custom transport chrome. No skip markers, no `AVContentProposal`, no chapters.

## What others do
| Repo | What | Link |
|---|---|---|
| Plozz / Lume / strimr / Silo / sashimi | Skip intro/credits/recap — see [upcoming/skip-intro/](upcoming/skip-intro/README.md). | [Plozz PR #65](https://github.com/brandomoore/Plozz/pull/65), [Lume PR #188](https://github.com/bilipp/Lume/pull/188), [strimr PR #134](https://github.com/wunax/strimr/pull/134), [Silo PR #399](https://github.com/Silo-Server/silo-apple/pull/399), [sashimi PR #453](https://github.com/bitstorm-labs/sashimi-apple/pull/453) |
| Rivulet | An "Insights" panel during playback: cast + trivia. | [6ea014b](https://github.com/l984-451/Rivulet/commit/6ea014b) |
| Sodalite | The next episode is warm before the switch. | [PR #150](https://github.com/superuser404notfound/Sodalite/pull/150) |
| Sodalite | Observation altitude: 10 Hz clock reads moved into leaf views, so the overlay doesn't re-evaluate 10×/s. | [06b9941](https://github.com/superuser404notfound/Sodalite/commit/06b9941e2e31f1120847968bcaa839a8eef58c97) |
| Swiftfin | Replaced NativePlayer with `AVMediaPlayerProxy` (one custom UI over AV/VLC/mpv). **Noted only** (custom chrome). | [PR #2046](https://github.com/jellyfin/Swiftfin/pull/2046) |
| Plozz / Rivulet / Sodalite / strimr / Silo | AetherEngine (FFmpeg → HLS-fMP4) for MKV/DV/TrueHD direct play. Not needed for kino.pub HLS. | [AetherEngine](https://github.com/superuser404notfound/AetherEngine) |

## Proposal
1. Skip markers → [upcoming/skip-intro/](upcoming/skip-intro/README.md). M · P1.
2. An Insights-style `customInfoViewControllers` tab: cast (TMDB) + facts (Kinopoisk). M · P2.
3. Pre-resolve the next episode's links (`MediaLinksResolver`) near the credits window. S · P2.
