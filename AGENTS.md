# Working agreement

Read this before changing code. The product direction, current state and roadmap live in
[README.md](README.md) — keep it accurate as you go instead of writing separate status documents.

## Priorities

1. **tvOS is the primary platform.** Design for the 10-foot experience and the Siri Remote first.
2. iOS, iPadOS and macOS must keep building, but they are supplementary — a reasonable-looking layout is
   enough, they do not drive design decisions.
3. Match the stock Apple TV app for look, and microiptv for features. When in doubt, do what Apple does.

## Ground rules

- **One target.** `KinoPubAppleClient` is a single multiplatform target. Use `#if os(tvOS)` /
  `#if os(iOS)` / `#if os(macOS)` for differences. Do not add a second app target.
- **No custom chrome where a system control exists.** No site-styled green buttons, no hand-rolled
  transport bars, no iOS-sized controls on TV. Native SwiftUI/AVKit components, HIG defaults.
- **Everything must be focus-navigable on tvOS.** Any `Button`, `NavigationLink` or interactive chip you
  add has to be reachable and visibly focusable with the remote. `.buttonStyle(.plain)` usually breaks
  this — check before shipping.
- **Focus drives the page on TV.** Rows screens describe the focused card in the preview at the top of
  `MediaRowsView` — artwork, title, plot — and hand the remote the first card rather than the tab bar.
  Anything new built out of rows should inherit that by using `MediaRowsView`, not a hand-rolled stack.
  Whatever fills reserved space above a row **must be focusable**: 560 points of inert space swallows
  every press of Up and strands the user with the tab bar out of reach.
- **Colours come from the system.** `Color.KinoPub.background`, `.text` and `.subtitle` resolve to the
  platform's own background and label colours. Don't reintroduce hand-picked greys; accents stay in the
  asset catalogue. **Dark appearance only for now** (scene-root `.preferredColorScheme(.dark)` +
  `UIUserInterfaceStyle = Dark`); do not half-support light until that deliberate pass lands. On tvOS,
  `Color.KinoPub.background` is `Color.black` so Liquid Glass samples a real page, not a clear window.
- **No skeletons.** A screen that is waiting shows nothing, then `LoadingIndicatorView` once the wait
  is long enough to notice, then fades the real content in. Don't reintroduce stand-in cards, shimmer
  or greyed-out text — Apple's own apps don't.
- **No analytics, no crash reporting.** Firebase was deliberately removed; don't reintroduce it or
  anything like it.
- **Downloads is non-TV only.** Don't wire download UI into tvOS surfaces.
- **New API calls go through `KinoPubBackend`.** Add an `Endpoint` in `Requests/`, a model in `Models/`,
  and expose it via the relevant service protocol + mock in `KinoPubAppleClient/Services/`. Keep the mock
  implementations in sync so previews keep compiling.
- **Localization.** User-facing strings go through `Localizable.xcstrings` (`"key".localized` /
  `Text("key")`), Russian and English both.

## Style

- 2-space indentation, matching the existing files.
- SwiftUI views: `@StateObject` view models injected via `@autoclosure @escaping` initializers, the
  pattern used across `Views/`. Follow the surrounding file rather than introducing a new architecture.
- Services are protocol + `…Impl` + `…Mock`; view models are `ObservableObject`, `@MainActor` where they
  touch UI state.
- Keep `PreviewProvider` / `#Preview` blocks working.

### Driving the remote

Only input needs a window; `simctl` has no key-press API.

**There is no Simulator.app on current Xcode.** `tell application "Simulator"` fails with `-1728` and
the process list has no such entry. The simulator window is hosted by **Device Hub**
(`com.apple.dt.Devices`), which also draws an on-screen remote along the bottom edge. If you are using
computer-use, request access to `Device Hub` — asking for "Simulator" returns notInstalled and sends
agents off believing the device cannot be driven at all.

Then: click the window's title bar to focus it, and use arrow keys + Return as the D-pad. **Escape is
not Menu** — it does not go back and does not dismiss a sheet; use the `‹` button on the on-screen
remote for that.

Focus bugs do not show up in previews, so anything focusable gets driven this way before it ships.

## Housekeeping

- Tick the roadmap checkboxes in `README.md` as phases land, and move items out of "Known issues" when
  they're fixed.
- If you find a new defect and aren't fixing it now, add it to "Known issues" with the file path.

## Community fork (technical steals only)

[dungeon-master-xx/kinopub-apple-client](https://github.com/dungeon-master-xx/kinopub-apple-client) is
a sibling fork of the same leoru original. Track it as remote `community` — **never rebase** our UI
onto theirs. Steal Request/Model/Service slices; keep our screens. Details:
[docs/en/community-fork.md](docs/en/community-fork.md).

## Cursor Cloud specific instructions

Cloud agents run in a **Linux** VM, not macOS. That shapes what can and can't be exercised here:

- **The app (`KinoPubAppleClient`) cannot be built or run in this VM.** It is a tvOS/iOS/macOS SwiftUI
  target that needs Xcode; there is no Swift toolchain or Simulator on Linux. The Xcode build and the
  four `swift test` package suites only run on the `macos-15` CI runners (`.github/workflows/ci.yml`).
  Do code review / edits here, but rely on CI (or a local Mac) to compile and test the Swift side —
  don't expect to reproduce a build failure locally.
- **What *is* runnable here:** the `tmdb-proxy` Cloudflare Worker and the standalone Python tools.
- **`workers/tmdb-proxy` (Node/Cloudflare Worker).** `npm --prefix workers/tmdb-proxy install` (done by
  the startup update script), then `npm --prefix workers/tmdb-proxy run dev` to serve on
  `http://127.0.0.1:8787`. Routes: `/3/...` forwards to `api.themoviedb.org` with a Bearer token,
  `/t/p/...` forwards to `image.tmdb.org` (no auth), anything else is a 404 hint. The API branch needs
  `TMDB_READ_TOKEN` — put it in `workers/tmdb-proxy/.dev.vars` (gitignored) and **restart** `wrangler dev`
  to pick it up (it is not hot-reloaded). Without the token the `/3/` branch returns a clean
  `{"error":"misconfigured"}` 500; the image branch still works with no secret. `npm run deploy` needs
  Cloudflare auth and is not runnable here.
- **`tools/kinopub-snapshot` and `tools/kinopoisk-metadata` (Python 3, stdlib only).** No `pip install`
  needed — they import only the standard library. Run directly, e.g.
  `python3 tools/kinopub-snapshot/snapshot.py --help`. Doing real work needs live credentials the VM
  doesn't have (a kino.pub access token via `--token`, a Kinopoisk Unofficial `--api-key`) and writes to
  a gitignored `data/*.db`; without those they only self-check / print usage.
