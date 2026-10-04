# Skip markers — credits → Up Next (`AVContentProposal`)

## Today
`WatchProgress` guesses the credits window (8% of runtime, 60–180 s, capped at half). AGENTS: "Skip / outro markers, when they land, feed this type; they do not grow a second threshold." ROADMAP stage 7: "Up Next via `AVContentProposal` / `contextualActions` near the end, driven by the existing next-episode logic" (`EpisodeQueue.next(after:)`).

## Proposal
1. When an outro/credits segment is known (and validated, see [dub-length-validation.md](dub-length-validation.md)), `WatchProgress` uses its start as the credits window instead of the guess. "Finished" and Continue Watching follow automatically.
2. At credits start, present an `AVContentProposal` for `EpisodeQueue.next(after:)` (system Up Next UI); pre-resolve its links (`MediaLinksResolver`) a few seconds earlier.
3. Silo's lesson: Skip Credits opening Next Up must keep the credits playing behind it ([PR #562](https://github.com/Silo-Server/silo-apple/pull/562)). Lume: the outro window replaces the fixed-percent trigger ([PR #188](https://github.com/bilipp/Lume/pull/188)).

## Effort
M · P1.
