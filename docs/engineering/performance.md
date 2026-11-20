# Measuring scroll, hitch and artwork

A repeatable way to put numbers on the lag around Home scrolling and backdrops.
Research that led here: [docs/research/performance.md](../research/performance.md).
This file is the playbook. Numbers in the results table are evidence, not product rules.

**Always label the machine.** Simulator hitch ratios are not device hitch ratios. An
Apple TV 4K 1st gen and an M4 Mac are different instruments.

## 1. Build Release

Instruments and `xctrace` are only honest on a Release binary. Debug keeps the
debug dylibs, disables some inlining, and inflates hitch time.

```bash
xcodebuild \
  -project KinoPubAppleClient.xcodeproj \
  -scheme KinoPubAppleClient \
  -configuration Release \
  -destination 'platform=tvOS Simulator,name=Apple TV' \
  -skipMacroValidation \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Destinations that matter:

| What you are measuring | Destination |
| --- | --- |
| Apple TV 4K (device) | `platform=tvOS,name=Apple TV 4K` (or the device UDID) |
| Apple TV simulator | `platform=tvOS Simulator,name=Apple TV` — **label as simulator** |
| iPhone | `platform=iOS,name=iPhone …` |
| iPhone simulator | `platform=iOS Simulator,name=iPhone 17 Pro` |
| Mac | `platform=macOS,arch=arm64` |

UI performance tests (`PerformanceUITests`) run in **Debug** on purpose: the
fixture roots (`-KINOPUBTemplatesGallery`, `-KINOPUBDetailFixture`) compile out
of Release. Use them for a CI / simulator baseline. Repeat the same walks in
Instruments on a Release device build with a real session.

## 2. Signposts

Subsystem **`com.soda.kinopub.perf`**. Zero cost unless a recording or an
`XCTOSSignpostMetric` is attached (`OSSignposter.isEnabled`).

| Category | Interval name | What it covers | Where |
| --- | --- | --- | --- |
| `artwork` | `artwork.request` | Nuke fetch + decode. End message: `tier pxWxH bytesB` (`memory` / `disk` / `network` / `full` if no target size) | `Artwork.tracedResponse` |
| `artwork` | `artwork.display` | Event: the bitmap was assigned to a view | `Artwork.noteDisplayed` |
| `hero` | `hero.page` | Home hero turned to another title (tvOS `TVPageHeroBackdropView`, iOS/Mac pager) | `TVPageHero.swift`, `HomeHeroCarousel.swift` |
| `hero` | `hero.backdrop` | tvOS title-page backdrop load + crossfade | `PageBackdropHost.show` |
| `scroll` | `scroll.home` | Home / templates vertical shelf scroll | `TVPageCollectionViewController`, `MediaRowsView`, Mac `ScrollMemory` |
| `scroll` | `scroll.season` | tvOS Rivulet season-rail CADisplayLink slide | `RivuletSeasonRail.animatePage` |
| `page` | `page.title` | Title page `onAppear` → first painted item | `MediaItemView` |
| `page` | `page.resize` | iPad / Mac window size bucket changed, then 0.3 s settle | `MediaRowsView` |

Instruments → **os_signpost** instrument → filter subsystem `com.soda.kinopub.perf`.
The Points of Interest template only shows the `.pointsOfInterest` category; ours
are named categories, so add the os_signpost instrument (or Time Profiler with
signposts overlay).

```bash
log stream --predicate 'subsystem == "com.soda.kinopub.perf"' --style compact
```

## 3. Instruments templates (Release, device)

Run each scenario below twice: **cold** (kill the app, empty artwork cache via
Settings › Storage › clear, or a fresh install) and **warm** (same walk again).

| Template | What to read | Confirms |
| --- | --- | --- |
| **Animation Hitches** | Hitch time ratio (ms/s), hitch count, longest hitch. For the worst hitch: commit vs render | User-visible jank |
| **Time Profiler** | Main thread, invert call tree. Look for `ImageIO` / `CGImageSource`, `CA::Layer::prepare_commit`, `UIVisualEffectView`, `AG::Graph` / SwiftUI body | Decode vs layout vs SwiftUI |
| **SwiftUI** | Body counts for `HeroBackdrop`, `CompactHeroPicture`, `MediaItemView`, `PageBackdropHost` during one swipe / one Down | Per-frame rebuild (H3, H5) |
| **Allocations** | Persistent growth; `CG raster data` / ImageIO peaks | Full-res decode (H1) |
| **VM Tracker** | IOSurface / dirty memory while turning the hero 10 times | H1 / H2 resident size |
| **Core Animation** | Color Offscreen-Rendered (or Simulator ▸ Debug ▸ Color Off-screen Rendered) | Shadows without `shadowPath` (H4) |

On a device, also: Xcode Debug ▸ View Debugging ▸ Rendering ▸ Color Offscreen-Rendered.

### What to write down, every run

| Field | Unit |
| --- | --- |
| Machine | `Apple TV 4K 1st gen` / `iPhone 17 Pro` / `Mac Studio 5K` / `tvOS Simulator 27.2` |
| Build | Release / Debug, git SHA |
| Cache | cold / warm |
| Hitch time ratio | ms/s (Animation Hitches) |
| Max hitch | ms, and commit vs render |
| Time to backdrop visible | ms (`hero.page` or `hero.backdrop` or `page.title`) |
| Decoded image memory | MB (`artwork.request` end `bytes`, Allocations `CG raster data`, Settings › Storage) |
| `artwork.request` tier | `memory` / `disk` / `network` on each hero turn — `disk` on every turn is a cache miss |

## 4. Scenarios

Walks are the same as `PerformanceUITests`. On a device, do them with the remote
or a finger, on a signed-in account.

### A. Home shelves — down and back up

- **tvOS:** Watch Now. Focus on a hero button. Down through five rows, Up back.
  Fixture stand-in: `-KINOPUBTemplatesGallery`.
- **iPhone:** Fast vertical flick through Home, then back to the top.
- **Mac:** Trackpad scroll through Home, then back.

Signposts: `scroll.home`. Metrics: hitch ratio on device (Animation Hitches);
on tvOS XCTest, `XCTOSSignpostMetric` duration of `scroll.home` +
`artwork.request`; on iOS also `scrollingAndDecelerationMetric`.

### B. Hero carousel paging × 10

- **tvOS:** Focus Next, Select ten times (or Right past Next). Fixture:
  `-KINOPUBTemplatesGallery -KINOPUBTemplatesHero`.
- **iPhone / Mac:** Swipe the Home hero sideways ten titles.

Signposts: `hero.page`, `artwork.request` (look at `bytes` and `tier`).

### C. Title page open + season / episode rail

- **tvOS:** Open a series. Wait for Play. Down onto the season rail, Right along
  four episodes, Menu back to Play. Fixture: `-KINOPUBDetailFixture seasonStrip`
  and, to hit the CADisplayLink slide, `-featureFlag.rivuletSeasonRail <true/>`
  (plist boolean; a string `YES` is ignored and the flag stays off).
- **iPhone:** Open a series from Home, scroll the episode row.

Signposts: `page.title`, `hero.backdrop`, `scroll.season`.

### D. Mac window resize on Home

Drag the Home window from ~1600×900 to ~1200×740 and back. Signpost: `page.resize`.
Watch whether `artwork.request` fires again (it should not, once size buckets land).

## 5. Headless `xctrace`

Device must be connected and trusted. `--time-limit` is a backstop; stop the
recording when the walk is done.

```bash
# Animation Hitches, 90 s, Apple TV
xcrun xctrace record \
  --template 'Animation Hitches' \
  --device 'Apple TV' \
  --launch com.soda.kinopub \
  --time-limit 90s \
  --output /tmp/kinopub-hitches.trace

# Time Profiler, main thread
xcrun xctrace record \
  --template 'Time Profiler' \
  --device 'Apple TV' \
  --launch com.soda.kinopub \
  --time-limit 90s \
  --output /tmp/kinopub-time.trace

# Allocations
xcrun xctrace record \
  --template 'Allocations' \
  --device 'Apple TV' \
  --launch com.soda.kinopub \
  --time-limit 90s \
  --output /tmp/kinopub-alloc.trace
```

Simulator (label as simulator):

```bash
UDID=$(xcrun simctl list devices available | awk -F '[()]' '/Apple TV \(/ { print $2; exit }')
xcrun simctl boot "$UDID" || true
xcrun xctrace record \
  --template 'Animation Hitches' \
  --device "$UDID" \
  --launch com.soda.kinopub \
  --time-limit 90s \
  --output /tmp/kinopub-hitches-sim.trace
```

Launch arguments for a fixture walk, appended after `--launch com.soda.kinopub --`:

```
-- -ui-testing -KINOPUBTemplatesGallery -KINOPUBTemplatesHero -KINOPUBForceColorScheme dark
```

Export hitch stats from a trace (Instruments 26+):

```bash
xcrun xctrace export --input /tmp/kinopub-hitches.trace --xpath \
  '//trace-toc/run/info' --output /tmp/kinopub-hitches.xml
```

Prefer reading the `.trace` in Instruments; the XML is a fallback.

## 6. XCTest UI performance tests

`KinoPubAppleClientUITests/PerformanceUITests.swift`.

```bash
xcodebuild \
  -project KinoPubAppleClient.xcodeproj \
  -scheme KinoPubAppleClient \
  -destination 'platform=tvOS Simulator,name=Apple TV' \
  -skipMacroValidation \
  CODE_SIGNING_ALLOWED=NO \
  -only-testing:KinoPubAppleClientUITests/PerformanceUITests \
  test
```

| Test | Platform | Fixture / skip |
| --- | --- | --- |
| `testHomeShelfScroll` | tvOS | `-KINOPUBTemplatesGallery` |
| `testHeroCarouselPaging` | tvOS | + `-KINOPUBTemplatesHero` |
| `testTitlePageOpen` | tvOS | `-KINOPUBDetailFixture list`, Select `awaiting` |
| `testSeasonRailScroll` | tvOS | `seasonStrip` + `-featureFlag.rivuletSeasonRail <true/>` |
| `testHomeShelfScroll` | iOS | live session, else `XCTSkip` |
| `testHeroCarouselPaging` | iOS | live session, else `XCTSkip` |
| `testTitlePageOpen` | iOS | live session, else `XCTSkip` |
| `testHomeShelfScroll` | Mac | live session, else `XCTSkip` |
| `testHomeWindowResize` | Mac | live session, else `XCTSkip` |

Pull numbers out of the xcresult:

```bash
xcrun xcresulttool get test-results summary --path "$RESULT" --compact
```

`XCTOSSignpostMetric` for our intervals reports duration (the number XCTest can
record on every platform). `XCTMemoryMetric` is physical memory. iOS also
records `scrollingAndDecelerationMetric` (system hitch during a pan).

tvOS has no Apple hitch metric in XCTest — focus moves are not pan gestures, so
`scrollDecelerationMetric` / `scrollingAndDecelerationMetric` record nothing.
The tvOS hitch stand-in is `XCTOSSignpostMetric` on `scroll.home`,
`scroll.season`, `hero.page`, and `artwork.request` (interval duration while
the walk is in flight). Hitch **ratio** (ms/s) still comes from Instruments
Animation Hitches on a Release device. Simulator rows in the table are
durations, not hitch ratios.

`XCTClockMetric` is not used: the walks wait for the remote / animation to
settle, and a clock metric would measure those waits.

## 7. Results

Fill a row per run. Simulator rows stay tagged **simulator**.

Simulator rows are **interval durations** (`XCTOSSignpostMetric`), not hitch
ratio. Hitch ms/s is a Release device, Animation Hitches.

| Date | SHA | Machine | Build | Cache | Scenario | Hitch ms/s | Max hitch ms | Backdrop ms | Decode MB | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2026-11-20 | *(this change)* | tvOS Simulator 27.x | Debug | fixture | Home shelves | *duration, not hitch* | | | | `PerformanceUITests.testHomeShelfScroll` |
| 2026-11-20 | | tvOS Simulator 27.x | Debug | fixture | Hero paging | *duration, not hitch* | | | | `testHeroCarouselPaging` |
| 2026-11-20 | | tvOS Simulator 27.x | Debug | fixture | Title open | *duration, not hitch* | | | | `testTitlePageOpen` |
| 2026-11-20 | | tvOS Simulator 27.x | Debug | fixture | Season rail | *duration, not hitch* | | | | `testSeasonRailScroll` |
| | | iOS Simulator | Debug | session? | Home scroll | skip unless session | | | | |
| | | Apple TV 4K | Release | cold | Hero ×10 | | | | | device, not yet |
| | | iPhone | Release | cold | Home flick | | | | | device, not yet |
| | | Mac | Release | cold | Home resize | | | | | device, not yet |

Paste the xcresult clock / memory / signpost durations into the *CI xcresult*
cells when the Test app job finishes. Do not copy them onto a device row.

## 8. Hypotheses this playbook is for

From the 2026-11-20 static reading. Treat as unconfirmed until a row above
has numbers:

1. Backdrops decode at full source resolution (`artwork.request` end `full` + tens of MB).
2. tvOS decoded-image cache is 64 MB, smaller than a few 4K backdrops (`tier=disk` on every hero turn).
3. iOS/Mac Home hero rebuilds every page every scroll frame (SwiftUI instrument, `HeroBackdrop`).
4. Hero text/logo shadows without `shadowPath` (Color Offscreen-Rendered).
5. Season rail CADisplayLink + fold blur (`scroll.season` vs native scroll).
6. Prefetch stops at disk; cells decode on first show (`artwork.request` `tier=disk` on cell appear).
