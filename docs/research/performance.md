# Performance practice

## How we do it now
UIKit for heavy tvOS surfaces; fixture-driven `TVDetailPageUITests`. CURRENT/AGENTS want numbers, but there is no repeatable perf harness.

## What others do
| Repo | What | Link |
|---|---|---|
| Plozz | Measures Home presentation hitches with a guarded remote driver; an on-device memory sampler; `docs/performance-debugging.md`. | [26bf55b](https://github.com/brandomoore/Plozz/commit/26bf55ba6068e3d655d35d55ec88ff6679a6f63c) |
| Lume | A benchmark suite, signposts and field telemetry; audit-driven PR series. | [PR #152](https://github.com/bilipp/Lume/pull/152), [#263](https://github.com/bilipp/Lume/pull/263), [#264](https://github.com/bilipp/Lume/pull/264), [#265](https://github.com/bilipp/Lume/pull/265) |
| Sodalite | Cut per-tick re-evaluation (observation altitude) and right-sized Home artwork; parallel top-row fetch. | [06b9941](https://github.com/superuser404notfound/Sodalite/commit/06b9941e2e31f1120847968bcaa839a8eef58c97), [0434a21](https://github.com/superuser404notfound/Sodalite/commit/0434a2178154b4e7ce036715bd97410e36e5b7f1) |
| sashimi | Home did 4× the work it needed (oversized decodes, serial round trips). | [PR #334](https://github.com/bitstorm-labs/sashimi-apple/pull/334) |
| Unwatched | Flattened player glass; `glassEffectContainer`; stopped decoding cover art 4×. | [936b63b](https://github.com/fer0n/Unwatched/commit/936b63b), [5ba2dbe](https://github.com/fer0n/Unwatched/commit/5ba2dbe) |

## Proposal — M · P2
`os_signpost` around `TVPage` apply, banner apply and detail first paint, plus an XCUITest remote walk on the fixture build that logs hitch and memory numbers in CI. This turns the review's "PARTLY" perf verdicts into numbers.
