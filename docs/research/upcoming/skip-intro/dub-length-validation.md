# Skip markers — dub-length validation

## Problem
Community markers are timed against the releases their contributors watched. kino.pub encodes (especially Russian dubs/voice-overs) can differ: studio logos added at the start, a cut or extended intro, different frame rates (23.976 vs 25 fps PAL speed-up shifts every timestamp by ~4%). A wrong skip hides content, which is worse than no skip.

## Proposal — S · P1 (gate for everything else)
1. Compare the marker DB's reported runtime (when present) with the kino.pub file duration. Accept within a tolerance (e.g. ±2% or ±20 s). For a ~4% difference, try a 25/23.976 rescale and accept only if both ends land within tolerance.
2. Drop open-ended segments when the runtime is unknown (as Plozz does).
3. Per-title outcome log in Settings › Diagnostics (accepted/rejected + reason) to measure the hit rate before shipping UI on by default.
4. The default mode is "button" (not auto) until the hit rate is known.
5. Choose per audio track only if needed. Markers are per video file, and all kino.pub audio tracks share one video timeline, so a single check per file should do.

## Evidence to collect first
A sample of ~50 episodes / films from Sasha's history: DB hit rate, runtime deltas, and a manual spot-check of 10 intros.
