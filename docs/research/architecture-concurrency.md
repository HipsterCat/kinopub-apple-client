# Architecture and concurrency

## How we do it now
One multiplatform target + 6 SPM packages; `ObservableObject` mostly (8 `@Observable`); **Swift 5 mode in packages**; four stores (`ContentStore`, `MediaLibraryStore`, `Artwork`, `MediaRecordStore`); load generations in `LibraryCatalog` and cancellable banner tasks since #39.

## What others do
| Repo | What | Link |
|---|---|---|
| Silo | Audit-driven fixes with finding ids; superseded fetches no longer clear loading state (we fixed the same in #39); `@MainActor` isolation fixes; one shared API v2 client. | [PR #475](https://github.com/Silo-Server/silo-apple/pull/475), [PR #467](https://github.com/Silo-Server/silo-apple/pull/467), [PR #501](https://github.com/Silo-Server/silo-apple/pull/501), [PR #350](https://github.com/Silo-Server/silo-apple/pull/350) |
| sashimi | Three UI races (stale season episodes, interleaved pages); Swift 6 isolation errors resolved. | [PR #316](https://github.com/bitstorm-labs/sashimi-apple/pull/316), [PR #438](https://github.com/bitstorm-labs/sashimi-apple/pull/438) |
| MyMedia / Parallax | Swift 6 with complete concurrency checking; a Swift 6 core package with test seams. | [fd87a4c](https://github.com/photangralenphie/MyMedia/commit/fd87a4c93f728d665d8feae5b454b873e45999f2), [PR #76](https://github.com/eutialia/Parallax/pull/76) |
| Swiftfin | Factory DI, StatefulMacro, CoreStore. | [Swiftfin](https://github.com/jellyfin/Swiftfin) |

## Proposal — M · P2
1. Move packages to the Swift 6 language mode one at a time (start with `KinoPubMedia` / `KinoPubMetadata`); the 2026-10-02 review's static/race issues were invisible in Swift 5 mode.
2. Mutation generations for optimistic toggles (see [detail-page.md](detail-page.md)).
3. Audit `HomeCatalog` for serial awaits that could be `async let` (Sodalite [0434a21](https://github.com/superuser404notfound/Sodalite/commit/0434a2178154b4e7ce036715bd97410e36e5b7f1)).
