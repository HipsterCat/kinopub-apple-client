# KinoPub Apple Client — agent context

A native client for kino.pub on tvOS, iOS, iPadOS and macOS, built as **one multiplatform
target**. It is an experimental, open-source, personal project: we explore what a media client on
Apple platforms can be, including features kino.pub's own apps do not have.

**Each platform uses its own renderer, on purpose.** SwiftUI is the default on iOS, iPadOS and
macOS. **On tvOS, media surfaces are UIKit + TVUIKit**: collection views, the three system cells
and the focus engine. A heavy tvOS surface still in SwiftUI is a leftover to port, not a base to
build on.

Shared across platforms: models, services, view models, component *semantics*, focus priority,
design tokens, assets. **Not shared: view hierarchy, geometry, point values.** Two renderers for one
semantic component is fine; two components for one idea on one platform is a defect.

## Quick reference

- **Target:** `KinoPubAppleClient` (product `KinoPub`), tvOS · iOS · iPadOS · macOS. Mark
  27-only API explicitly. **tvOS floor 26.5** (the oldest tvOS 26 simulator runtime; packages
  declare `.tvOS("26.5")`), iOS and macOS 26.6 (packages `.v26`).
- **Scope now:** [CURRENT.md](CURRENT.md).
- **Language:** Swift 5 mode in packages (`swift-tools-version: 6.2`).
- **Player:** native `AVPlayerViewController` / `AVPlayerView`, one app-scoped `PlaybackSession`.
  No custom transport chrome.
- **Appearance:** tvOS follows the system light/dark setting (no `.preferredColorScheme` on the
  tvOS shell — even `nil` pinned Dark). iOS and macOS are forced dark until their light pass
  (`LaunchAppearance` in `KinoPubAppleClientApp.swift`). The detail hero's content is forced dark
  everywhere. Shots in both: DEBUG `-KINOPUBForceColorScheme light|dark`.
- **Distribution:** personal builds and internal TestFlight. App Store review is not a target,
  which is what makes isolated private API acceptable.
- **Docs are English.** A vendor's own documentation stays **verbatim in its language**
  (`docs/providers/kinopub/` is Russian) — do not translate or delete it. UI strings are RU + EN
  through `Localizable.xcstrings`. Asana tasks are in Russian.
- **Repo:** `KinoPubAppleClient/` (app), `KinoPubTopShelf/` (extension),
  `Packages/KinoPub{UI,Backend,Kit,Metadata,Media,Logging}/`, `workers/` (Cloudflare), `tools/`.
- **Third-party SPM:** `KeychainAccess`, `PopupView`, `Reachability` (app target); `Nuke`, `Pulse`
  (`KinoPubUI`). See [Dependencies](#dependencies).

### Where things live

| Need | Where |
| --- | --- |
| What is active now, the tvOS layout contract | [CURRENT.md](CURRENT.md) |
| Planned work, open questions, parked defects | Asana — [Kinopub Engineering project plan](https://app.asana.com/1/1218266299921477/project/1219403693009374) ([ROADMAP.md](ROADMAP.md) maps features to tasks) |
| What the product *does* — decided behavior per feature | [docs/product/](docs/product/) |
| Media model: sources, facts, viewer state, presentation | [docs/media-model.md](docs/media-model.md) |
| External sources' fields | [docs/providers/](docs/providers/) |
| Symptom → cause, from this repo's own bugs | [docs/engineering/troubleshooting.md](docs/engineering/troubleshooting.md) |
| Accepted adapters around Apple / package limits | [docs/engineering/adapters.md](docs/engineering/adapters.md) |
| Detail page internals | [docs/engineering/detail-page.md](docs/engineering/detail-page.md) |
| Data, caches, diagnostics — the long form | [docs/engineering/data.md](docs/engineering/data.md) |
| Approaches removed on purpose | [docs/engineering/removed.md](docs/engineering/removed.md) |
| TestFlight pipeline | [docs/testflight.md](docs/testflight.md) |
| Community fork | [docs/community-fork.md](docs/community-fork.md) |
| Research and history — evidence, never law | [docs/research/](docs/research/README.md), [docs/archive/](docs/archive/) |

## Authority

1. Sasha's explicit decision in the conversation.
2. [CURRENT.md](CURRENT.md) on scope; this file on how things are built.
3. [docs/product/](docs/product/) — accepted behavior.
4. `docs/research/`, `docs/archive/`, CHANGELOG — evidence. **Never automatic requirements.**

If sources conflict, stop only the disputed part and ask. Do not invent blockers, do not close open
design questions with "Apple defaults", and do not rewrite docs to rationalize an implementation.

**Preserve user work.** Pre-existing modified or untracked files are Sasha's. Re-read a file right
before patching it; prefer narrow patches; do not revert or reformat unrelated work.

## Constraints are not requirements

A workaround found while implementing is **not** a product rule until Sasha says so. This is what
produced most of what had to be deleted from this repo's docs: *X can't do Y → workaround →
workaround written down as "how the page works" → next agent defends it as law.*

| Label | Needs to be believed | Expires |
| --- | --- | --- |
| **Apple API limitation** | The symbol, from SDK headers, plus what you tried | Next SDK — re-probe |
| **Performance limitation** | A number, from a device or Instruments | Next measurement |
| **Focus / navigation invariant** | A state the user can get stuck in | Never |
| **Product decision** | Sasha said so | When Sasha says otherwise |

Only the last two become durable requirements. The first two become an **adapter**: one named
place, limitation in its doc comment ([list](docs/engineering/adapters.md)). Probe before claiming
an API limitation — `swiftc -typecheck` against the SDK settles most in a minute.

### 🔴 Banned — re-implementing what Apple owns

If a task seems to need one of these, the design is wrong one level up — stop and ask.

| Banned | Instead |
| --- | --- |
| A focus-routing layer of our own (`focusBridge`-shaped), a custom hero focus graph | `.focusSection()`, `defaultFocus`, `indexPathForPreferredFocusedView(in:)`; one connected focus graph |
| `.disabled` on sibling controls to steer Up/Down | Separate `.focusSection()`s + `defaultFocus` |
| One `@FocusState` case bound by several sibling views (froze focus, Menu quit the app) | One case per focusable view, or none |
| Focus timing hacks — `asyncAfter`, same-press guards | React to where focus landed |
| Hand-rolled focus chrome — `scaleEffect` / brightness / shadow / parallax | `.buttonStyle(.card)`, system cells; `.borderless` + `.hoverEffect` only where the label *is* an image |
| Scroll-progress choreography, page-wide fold/wash state | Fixed states; the focus engine scrolls the page |
| Hand-driven scrolling (`CADisplayLink` on `contentOffset`) | Fix layout, or use a collection view |
| A SwiftUI state machine around preview / trailer playback | UIKit, if it is ever built |
| **Screen-specific component variants** — the most violated rule here | One component, configured |

Not requirements, though agents wrote them down as such: a tab bar pinned through scroll; "the
hero must live outside the scroll"; cross-platform geometry parity ("iOS shows two lines, so tvOS
must"); a compact title / floating header logo.

## Focus (tvOS)

The focus engine is Apple's; we do not build a layer on top of it.

- Interactive controls are reachable and visibly focusable. `.buttonStyle(.plain)` often kills
  visible focus — check before using it.
- For a focusable container, `.buttonStyle(.card)` and no focus code (Apple's `DestinationVideo`:
  `#if os(tvOS) .card #else .plain #endif`).
- `.hoverEffect(.highlight)` only where the label *is* the image — on `icon + text` it scales the
  icon alone.
- **Every state keeps a focus escape path.** Empty and error states are focusable sections with a
  Retry control; never drop the hero's focusability; no inert reserved space above the first
  focusable row (it traps focus in the tab bar).
- **A focus dead end is fixed now**, in the change that finds it. Any other defect you notice on
  the way is an Asana subtask, not an inline fix.
- Debug focus the Apple way: `-UIFocusLoggingEnabled YES`, the system log, a fixed remote walk —
  before theorising.

## Components

**Pages are assembled from a fixed catalogue: a page is a list of typed sections, not a
hand-written stack of views.** Two pages showing a shelf show the same shelf — same component,
metrics and focus behavior.

```
allowed                          never
MediaCard                        HomeMediaCard / DetailMediaCard / SearchMediaCard
  configuration: kind / metadata / presentation
```

Platforms may render one component differently; screens may not. While a look is unsettled, 2–4
variants *of one component* behind a switch, in one file, are fine — delete the losers with it.

- Reusable UI lives in `KinoPubUI`; screen composition stays in the app target.
- Semantic tokens only — `Color.KinoPub.*`, `TypeScale`. `Color.KinoPub.background` is **opaque**;
  layer a scrim explicitly.
- **Dynamic Type text styles, never `.system(size:)`** — except where a glyph lines up with fixed
  geometry. Vary weight and colour, not size. One running-text size per page family.
- **tvOS: three cells, one collection per page region** — person, wide 16:9, poster, all TVUIKit.
  The one extension is the HIG *Card* for ratings, reviews, facts, stills and specs
  (`TVPageCellKind.infoCard`, a `TVCardView` wearing `TVPagePlatter`). A hand-assembled tile is a
  defect even when it looks right.
- 🔴 A rule that depends on a title's type or genre lives in `MediaPresentationProfile`, never as
  `if type == …` in a view ([media-presentation.md](docs/product/media-presentation.md)).
- Ship a working `#Preview` (tvOS too when focusable). Previews do not prove focus.

## The detail page

Internals and history: [docs/engineering/detail-page.md](docs/engineering/detail-page.md). Rows:
[docs/product/detail-sections.md](docs/product/detail-sections.md).

- **tvOS backdrop is interim, to be redone** (Sasha, 2026-10-11) — do not defend or build on
  `PageBackdrop`. Decided: one full-screen picture behind the content, not in the scroll; hero and
  sections stay one scroll and one focus graph.
- **On tvOS everything under the hero is one embedded TVUIKit page**, inside the hero's scroll
  view, with its own full-width `.focusSection()`. `MediaItemTVSections.make` is the order and
  content, as data.
- **Play is the entry focus, by name** (`defaultFocus(priority: .userInitiated)`), and the hero
  reclaims it (or Follow when it leads) on return from the player.
- Hero prose on tvOS is a `.borderless` button whose Select opens the info popup — no
  `.focusable()` wrapper on it.
- Hero content is forced dark; the scrim sits where the text is. Light-mode behavior of the hero is
  open (Asana, *Страница тайтла*).
- **No page-wide hero state.** The one scroll the page asks for is back to the top when a hero
  control takes focus. The page body reads no focus.
- **Lead with what can be played:** hero → playable rail → everything else. Episodes, parts,
  versions (and trailers, not built yet) share one rail *component*; versions (`PlaybackVariant`)
  never mix with episodes in one rail.
- Sections are data, empty ones absent, order defined in one place. "Related" uses Home's shelf.

## Chrome

- All `glassEffect` goes through `kinoGlass` / `kinoGlassGroup` (degrades under Reduce
  Transparency). `.buttonStyle(.glass)` / `.glassProminent` are system-owned and stay direct.
- Glass samples what is behind it; a flat page fill degrades it to a slab.
- Navigation bar and tab bar are the system's: system `TabView` (adaptive on iPad), no hiding, no
  custom bar over content, no material stacked behind a page to "help" it.
  `backgroundExtensionEffect` as shell chrome is banned.
- A background change is a fixed backdrop state plus a system material, checked in light **and**
  dark. tvOS has no `systemBackground`.
- Blur: private `variableBlur` over static art only; no blur over video on tvOS/macOS.
- Hero CTAs: `.glassProminent` for Play, `.glass` for the rest; the white fill is focus, not a tint.
- No shadows on tvOS cards, badges or action buttons.

## Data and continuity

- **Watch state is `WatchProgress`**: watched = 85% of runtime (kino.pub's rule). Cards paint
  `resumeFraction`; Up Next timing (`upNextLeadTime`) is a separate question. Skip markers, when
  they land, feed this type.
- **Continuity beats placeholders.** Card → detail carries the known item and artwork; stale local
  data paints first and revalidates underneath. Exact skeletons only on true cold loads.
- **Stores:** `ContentStore` owns Home/Library rows; `MediaRecordStore` owns item facts (one
  `MediaRecord` per `MediaRef`); `MediaLibraryStore` owns optimistic per-item state; `Artwork` owns
  every remote image (use `CachedRemoteImage` / `ArtworkImage`, never `AsyncImage`); bookmarks are
  `BookmarkMembershipStore` + `BookmarkFoldersStore`. No other cache. Local optimistic writes win
  until the server contradicts them.
- A detail page fetches no bookmark list — membership is on the item payload.
- A `nolinks` payload still lists `files` without URLs: ask `hasPlayableURL`, never assume one.
- tvOS purges `Caches/` when the app is not running — lean on in-memory TTLs.
- **New API calls go through `KinoPubBackend`** — Endpoint + model + service protocol + mock.
- **Document an external source before integrating it** — a sheet in `docs/providers/` with every
  field, wanted or not.
- Providers: our Cloudflare worker for owner keys, caching and flaky services; the app for a
  viewer's own account (Kinopoisk key, Trakt). Both land as `MediaFragment`s.
- **No third-party telemetry SDK.** On-device diagnostics (Pulse behind `NetworkDiagnostics`, in
  every build, tokens redacted at capture, API traffic only) are not telemetry.
- **Auth launch is optimistic:** a Keychain token mounts the shell at once; a refresh rejection is
  not a sign-out; `APIClient` retries a content 401 once after recovery.
- **Every flag is a `FeatureFlag` case**, switchable in Settings › Diagnostics in every build; an off
  flag skips the work, not only the UI. Downloads are non-TV only.

## Build, run, verify

```bash
xcodebuild -scheme KinoPubAppleClient -destination 'platform=tvOS Simulator,name=Apple TV' build
```

- **The project file is `KinoPubAppleClient.xcodeproj/project.xcproj`** (Xcode 27 JSON; no
  `project.pbxproj`). A new `.swift` file is not compiled until it is listed in its group's
  `children` with `"target-membership": [ "KinoPubAppleClient/compile-sources" ]` — the symptom is
  `Cannot find 'TypeName' in scope` everywhere it is used.
- **TestFlight:** `.github/workflows/testflight.yml`, at most one automatic upload a day, iOS +
  tvOS + macOS. Details and secrets: [docs/testflight.md](docs/testflight.md). Sasha tests on the
  Apple TV through TestFlight.
- **Shared debug session:** DEBUG builds mirror the session to `~/.kinopub-dev-session.json`
  (`DevSessionMirror`) so reinstalls need no new code — the account has five device slots. Release
  keeps `KinoPubAppleClient.entitlements`; only Debug gets the sandbox exception.
- **Fixtures, not the live account, for UI tests:** `-KINOPUBDetailFixture film`,
  `-KINOPUBLibraryFixture YES`, `-KINOPUBTVChannelsFixture YES`, `-KINOPUBFixtureInTabs YES`. A
  live UI run can rotate the token and kill the dev session. Run tvOS checks on both simulator
  runtimes, 27.2 and 26.5 — they differ.
- The simulator window lives in Device Hub; arrows + Return are the D-pad, Escape is **not** Menu.
- Focus bugs do not show in previews and a screenshot shows no animation — say "not verified on
  device" when it was not.

| Risk | Examples | Before "done" |
| --- | --- | --- |
| Low | Copy, strings, small fixes, docs, CI wiring | Diff review, commit to `main` |
| Medium | Reusable view, layout, model mapping | Build the affected platforms; `#Preview` |
| High | Navigation, focus, player, materials, session/cache lifetime, private API | Build all platforms; screenshots or a recording in the chat and on the Asana task |

Deferred verification is allowed; silent "everything landed" claims are not.

## Key files

| Purpose | File |
| --- | --- |
| Feature flags | `KinoPubAppleClient/Services/Configuration/FeatureFlags.swift` |
| Type scale / shelf sizing / glass | `Packages/KinoPubUI/Sources/KinoPubUI/Layout/{TypeScale,ShelfMetrics}.swift`, `DesignSystem/KinoGlass.swift` |
| tvOS cells, rails, pages | `Packages/KinoPubUI/Sources/KinoPubUI/Components/TVUIKit/` |
| tvOS detail sections | `KinoPubAppleClient/Views/MediaItem/Subviews/MediaItemTVSections.swift` |
| Artwork (the only Nuke import) | `Packages/KinoPubUI/Sources/KinoPubUI/Components/Content/ArtworkPipeline.swift` |
| Rows / per-item library | `KinoPubAppleClient/Services/Cache/ContentStore.swift`, `Services/MediaLibrary/MediaLibraryStore.swift` |
| Network log (the only Pulse import) | `Packages/KinoPubUI/Sources/KinoPubUI/Diagnostics/NetworkDiagnostics.swift` |
| Routes / player / API | `KinoPubAppleClient/States/Navigation/`, `Views/Player/PlayerManager.swift`, `Packages/KinoPubBackend/` |
| In-app What's New | `KinoPubAppleClient/Resources/whats-new.json` |

## Working agreement

1. **Model before layout.** What does the user act on, and what can they do now? A page growing
   per-type sections is a data question answered in the view layer.
2. **Ask which system primitive Apple provides** before reproducing a look. Order: system control →
   system API behind a thin bridge → a pattern from a reference app or library → minimal custom
   (name the missing API and the cost).
3. **Borrow before build.** Code from any watched or reference repo may be used — the project is
   experimental and open; the commit names the source.
4. **Ambiguous visible UI gets 2–3 real variants** in `KinoPubUI/Previews/` behind `#if DEBUG`;
   promote one, delete the file.
5. **Fixes and most changes go straight to `main`**, as small commits with detailed messages. A
   branch or PR only when Sasha asks or the environment cannot push to `main`.
6. **Screenshots go in the chat and on the Asana task**, not into a PR.
7. **Record what you learned where it belongs:** planned work, parked defects, open questions and
   research findings → an Asana subtask of the feature's task (mark it done with the commit); a
   decided product rule → `docs/product/`; an external source → `docs/providers/`; a durable
   engineering rule or trap → this file (short) or `docs/engineering/` (long); notable shipped
   facts → `CHANGELOG.md`. Never a checklist in a `.md` file. **Keep this file short** — a new
   rule replaces or shortens an old one, history goes to `docs/engineering/`.
8. **If a viewer can see the change**, add a ru + en bullet at the top of the current version in
   `KinoPubAppleClient/Resources/whats-new.json` (in-app What's New and TestFlight notes).
9. One reviewable slice at a time; build every platform before calling it done.

### Dependencies

A package is fine when it replaces code we would otherwise own and get wrong. It stays behind our
own type (no call site imports it), is pinned to a major, builds on all four platforms, and is
declared in the package that uses it. Exception: no telemetry SDKs.

### Style

- 2-space indentation.
- **New view models are `@Observable`** (`@MainActor` when touching UI); existing
  `ObservableObject`s migrate type by type. When migrating: `State.init(wrappedValue:)` has no
  autoclosure overload (a naive `@StateObject` → `@State` swap rebuilds the model on every
  `init`), and `@Environment(X.self)` crashes where nothing injected it.
- Services: protocol + `…Impl` + `…Mock`.

### Community fork

[dungeon-master-xx/kinopub-apple-client](https://github.com/dungeon-master-xx/kinopub-apple-client)
is remote `community`. Take Request / Model / Service slices; never rebase our UI onto theirs.
Details: [docs/community-fork.md](docs/community-fork.md).
