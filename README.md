# kino.pub Apple client

A native client for [kino.pub](https://kino.pub), built as a **real multiplatform Apple app**
(tvOS, iOS, iPadOS, macOS) with a high bar for focus, materials, and system controls. SwiftUI on
iPhone, iPad and Mac; UIKit + TVUIKit where tvOS media surfaces need the focus engine. One target,
shared models and services, native composition per platform.

Fork of [leoru/kinopub-apple-client](https://github.com/leoru/kinopub-apple-client). A sibling fork,
[dungeon-master-xx/kinopub-apple-client](https://github.com/dungeon-master-xx/kinopub-apple-client),
is tracked as read-only remote `community` for **technical steals only** — we do not rebase our UI
onto theirs. See [docs/community-fork.md](docs/community-fork.md).

## What this is

- **Look:** stock Apple TV / TV / Music patterns — rows, native focus lockups, system player, Liquid
  Glass and scroll-edge chrome where they belong.
- **Features:** parity with what people use on Apple TV today (microiptv-class catalog/library), then
  wider: collections, metadata, playback memory, skips, and later language-learning subtitles.
- **Not a website port.** No site-green chrome, no hand-rolled transport bars, no fake focus.

## Current stage

tvOS daily driver in place; iOS, iPadOS and macOS next ([CURRENT.md](CURRENT.md)).
What is planned and open is tracked in Asana — [Kinopub Engineering project plan](https://app.asana.com/1/1218266299921477/project/1219403693009374), one task
per feature ([ROADMAP.md](ROADMAP.md) maps them).

## Broadly working

- Device-code authorization, catalog browse, search, bookmarks, detail, seasons/episodes
- Native `AVPlayerViewController` playback with resume; app-scoped `PlaybackSession`
- Home banner shelf, row-based Home, system `TabView` + `.sidebarAdaptable`
- List-row caching for Home/Library summaries; TMDB / Kinopoisk enrichment plumbing
- Downloads on non-TV platforms only

Verification gaps and unfinished edges are Asana subtasks ([Kinopub Engineering project plan](https://app.asana.com/1/1218266299921477/project/1219403693009374)) — not a list here.

## Requirements

- Xcode with tvOS / iOS / macOS **26** SDKs. tvOS deployment target **26.5**
  (the minimum tvOS 26 simulator runtime; real devices can all update to 26.6,
  but the simulator cannot). iOS and macOS stay at **26.6**.
- Swift 5 language mode in packages (`swift-tools-version: 6.2`)
- Single multiplatform target `KinoPubAppleClient` (product name `KinoPub`)
- tvOS follows the system light/dark setting; iOS and macOS are forced dark until their pass
- **Internal TestFlight:** daily / version bump / Actions → TestFlight (iOS, tvOS,
  macOS). Secrets and first upload: [docs/testflight.md](docs/testflight.md)

```
open KinoPubAppleClient.xcodeproj
# pick an Apple TV / iPhone / Mac destination
```

## Documentation

| Doc | Role |
| --- | --- |
| [AGENTS.md](AGENTS.md) | The whole agent context — defaults, banned patterns, traps |
| [ROADMAP.md](ROADMAP.md) | Retired — maps each feature to its Asana task |
| [CURRENT.md](CURRENT.md) | What is active now |
| [CHANGELOG.md](CHANGELOG.md) | Notable shipped changes |
| [docs/testflight.md](docs/testflight.md) | Internal TestFlight secrets, triggers, first upload |
| [docs/providers/](docs/providers/) | External source capability sheets |
| [docs/community-fork.md](docs/community-fork.md) | Community remote strategy |
| [docs/archive/](docs/archive/) | Frozen plans / research (evidence only) |

API reference: [kinoapi.com](https://kinoapi.com) (verify load-bearing shapes against live JSON).

## App structure

- `KinoPubAppleClient` — app target
- `KinoPubUI` / `KinoPubBackend` / `KinoPubKit` / `KinoPubLogging` / `KinoPubMetadata` — local packages

Third-party today: KeychainAccess, PopupView, Reachability. No analytics or crash-reporting SDK —
crashes come from TestFlight / Xcode Organizer; product analytics is a late-stage item.

## Contributing

Read [AGENTS.md](AGENTS.md) before changing code. Prefer small slices; put detail work in feature
docs; change this README only when positioning, the current macro stage, or a broad capability changes.

- [Feature request](https://github.com/HipsterCat/kinopub-apple-client/issues/new?template=feature_request.md)
- [Bug report](https://github.com/HipsterCat/kinopub-apple-client/issues/new?template=bug_report.md)

## Credits

Built on [leoru/kinopub-apple-client](https://github.com/leoru/kinopub-apple-client) by Kirill Kunst
and contributors.
