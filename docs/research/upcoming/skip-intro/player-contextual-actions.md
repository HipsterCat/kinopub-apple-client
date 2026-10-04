# Skip markers — player integration (contextual actions)

## Mechanism
`AVPlayerViewController.contextualActions` ([Apple docs](https://developer.apple.com/documentation/avkit/avplayerviewcontroller/contextualactions)) shows system-styled buttons (e.g. "Skip Intro") over playback. Set it when the playhead enters a segment and clear it on leaving, with a periodic time observer on the `PlaybackSession` player. This is a system affordance, so it doesn't break the "no custom transport chrome" rule (AGENTS, ROADMAP stage 7: "Skip and Up Next use the system affordances before any custom overlay").

## Modes (Plozz)
Off / On (button) / Auto with delay / Auto instant, per kind (intro, recap, credits, preview). See [Plozz PR #65](https://github.com/brandomoore/Plozz/pull/65). Silo has never/ask/always ([PR #399](https://github.com/Silo-Server/silo-apple/pull/399)).

## Details to get right
- A skip seeks to the segment end minus a small guard. Don't skip if the user scrubbed into the segment on purpose.
- Lume also exposes next/previous in the transport row ([PR #230](https://github.com/bilipp/Lume/pull/230)); for us that's the Up Next tab plus `infoViewActions`.
- Silo: a timeline scrub must not lose focus to skip buttons ([PR #524](https://github.com/Silo-Server/silo-apple/pull/524)).
- tvOS only for the rich surfaces; iOS gets the same via `contextualActions` (iOS 16+); macOS `AVPlayerView` has no equivalent (see the `player-avkit` skill).

## Effort
M · P1. Validation needs a device (focus and timing).
