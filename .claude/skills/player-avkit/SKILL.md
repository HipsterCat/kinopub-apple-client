---
name: player-avkit
description: Working on playback — the AVKit player, its metadata and info panels, skip / Up Next / chapters, subtitles and audio tracks, playback routing, resume, or the macOS player window. Use before adding anything on top of the system player, and before planning a player feature for a platform.
---

# Player and AVKit

**The native controller is the chrome, on every platform.** Custom transport bars fight AirPlay, Now
Playing and accessibility. But using the system player is not the same as **populating** it —
everything the stock TV app shows over video (title, description, artwork, Info tabs, Related, Skip
pill, Up Next card, chapters, speed) is AVKit API you fill in, not chrome you rebuild.

The player draws no chrome of ours: no custom title, no Cancel button, no centre panel. Exit is the
window close button, Done, or Menu.

## What exists where

Verified against the iOS/tvOS 27.0 and macOS 26.0 SDK headers (Aug 2026). The tvOS-only entries are
`API_UNAVAILABLE` elsewhere — a plan that promises them on iOS or macOS is wrong on arrival.

| Surface | API | tvOS | iOS | macOS |
| --- | --- | --- | --- | --- |
| Title / subtitle / description / artwork | `AVPlayerItem.externalMetadata` | yes | 12.2+ | **absent** |
| Info-panel tabs | `customInfoViewControllers` | 15+ | no | no |
| Info-panel actions (max 2) | `infoViewActions` | 15+ | no | no |
| Skip Intro / Recap pill | `contextualActions` | 15+ | no | no |
| Up Next card | `AVContentProposal` + `contentProposalViewController` | 10+ | no | no |
| Chapters | `AVPlayerItem.navigationMarkerGroups` | 9+ | no | no |
| Transport-bar custom menu | `transportBarCustomMenuItems` | 15+ | no | no |
| Overlay hosting / safe layout | `customOverlayViewController`, `unobscuredContentGuide` | 13+ / 11+ | no | no |
| Playback speed | `speeds` / `selectedSpeed` | 16+ | 16+ | `AVPlayerView.speeds` 13+ |
| Picture in Picture | `allowsPictureInPicturePlayback` | 14+ | 9+ | `AVPlayerView` 10.15+ |
| Custom media-selection schemes | `AVCustomMediaSelectionScheme` | 26+ | 26+ | 26+ (no AVKit UI) |

So the rich Info / Related / Up Next experience is a **tvOS deliverable**. On iOS the honest native
scope is `externalMetadata` + speed + PiP. On macOS there is no `AVPlayerViewController` and no
`externalMetadata` at all: the AppKit surface is `AVPlayerView`, the title belongs to the window
title bar and `MPNowPlayingInfoCenter`, and SwiftUI's `VideoPlayer` exposes none of `speeds` /
`controlsStyle` / PiP — that needs an `NSViewRepresentable`.

## Ours

- **One app-scoped `PlaybackSession` / `PlayerManager`.** Do not allocate a manager per route.
- **Leaving the player ends the film.** The session outlives the screen on purpose, so nothing
  stops the stream unless the exit path says so: `PlaybackSession.stop(_:)` takes the manager the
  screen was showing (a route can tear down after the next film already claimed the session) and
  `tearDownForReplacement` does the real work — `replaceCurrentItem(with: nil)`, not `pause()`,
  which leaves a loaded item and a live resource loader behind. The one exception is an active
  PiP window: that is the viewer keeping the film, not closing it.
- **The exit signal is not the same on every platform.** tvOS and macOS use `onDisappear`
  (Menu → `playerViewControllerShouldDismiss`; closing the window). **iOS must not** — the view
  gets `onDisappear` when AVKit presents the player, i.e. on the way *in* — so there the signal is
  the host controller's `viewDidAppear` once the presentation is gone (AVKit's dismissal delegate is
  unavailable in the SDK; see the traps below).
- **iOS presents the player, and that is where the close button comes from.** An embedded
  `AVPlayerViewController` draws a transport bar and nothing else; with the navigation bar hidden
  that is a film you cannot leave. `entersFullScreenWhenPlaybackBegins` was supposed to buy the
  presentation and did not, so `PlayerPresentationController` presents it `.fullScreen` outright.
- 🔴 **No subtitles of ours, anywhere. The system draws them.** tvOS used to fetch the
  sidecar SRT, parse it and render it in a SwiftUI overlay in our own styling, with a custom
  transport-bar "Subtitles" menu beside it and `allowedSubtitleOptionLanguages = []` hiding
  AVKit's own picker — all of it built for a dual-track feature that does not exist. Deleted
  2026-08-25 by explicit decision: **we do not do caption design, the system does**, and it
  knows the viewer's caption styling. `SubtitleCueParser`, `SubtitleOverlayView`,
  `SubtitleTrackPickerView` and `SubtitleTranslatePanel` are gone; do not bring them back.
  Subtitle *settings* live in Settings, never in the player.
- **`TrackResolver` decides which track is selected, on every platform** — that is the whole
  of our involvement. `player.appliesMediaSelectionCriteriaAutomatically` is off, because the
  *Automatic* caption display type puts captions up when the media is **muted**, and the
  resolver reads the system setting itself (`.alwaysOn` means on; system caption languages
  seed the order). The answer reaches the master's own renditions through `SubtitleRenditions`.
- **One language table.** `SubtitleTracks.languageKey` resolves through `LanguageNames`; the second
  shorter copy it used to keep is gone, and it is what made `uzb` and `phi` match nothing while the
  name beside them read correctly.
- **`externalMetadata` is the stock panel, populated — from the *title*, not from what is
  playing.** An `Episode` carries none of its parent's facts, so `PlayerManager.titleContext`
  falls back to the series snapshot `LocalWatchProgressStore` already holds. The mapping is
  `PlaybackMetadata` in `KinoPubBackend`. **No year:** `.commonIdentifierCreationDate` prints
  in the line *above* the title on tvOS, where the stock player puts a channel name, so a film
  read as "2023 / Мятеж".
- **There is no metadata identifier for a capability badge.** 4K / HDR / Atmos in the panel are
  not something `externalMetadata` can carry — the common and iTunes identifier sets are title,
  subtitle, description, genre, date, artwork and the like. On tvOS the supported way to put
  our own facts in that panel is `customInfoViewControllers`, a tab of our own (stage 7).
  Every metadata item is tagged `und`: a real language tag makes AVFoundation filter the item
  against the viewer's locale, and the panel then shows nothing.
- **Off tvOS: present the player, do not push it.** macOS uses its own 16:9 window; iOS lets the
  system controller go full screen for Done. **Every play entry point goes through `PlayerLink`** —
  a `NavigationLink` to the player route puts the film in the macOS detail column with the sidebar
  still visible, which is a bug, not a layout. `NavigationState.push` redirects player routes into
  `PlaybackWindowState` on macOS so future entry points are covered without re-auditing call sites,
  and `RouteDestination` guards the two cases with an `assertionFailure` in DEBUG.
- **Any ambient/preview player outside `PlaybackSession` must be wired to "a real session started
  elsewhere".** It does not get that for free. Off macOS the hero's muted trailer stops because
  pushing the player fires `onDisappear`; macOS opens a *separate window*, so the detail page never
  disappears and the ambient copy kept playing behind it — the Trailer action meant the same clip
  playing twice, unsynced.
- Audio: system picker + master `NAME=` relabel via `HLSAudioLabeler`.
- **Which dub and which subtitles a title opens with is `TrackResolver`, not the player.** One pure
  function over a menu + what the scopes remember + settings; scopes are season → title → `anime`
  class → ladder. Do not add a second selection rule beside it, and do not remember a dub by
  rendition name, index or URL — those differ between two episodes of one season. Rules and reasons:
  `docs/product/playback-tracks.md`. `TrackPreferenceStore` owns the ledgers and writes to every
  scope a play teaches; `PlaybackSession` derives `TitleTrackProfile` because genres and countries
  live on the *item* and an `Episode` is not one. `AudioTrackMemory` / `AudioTrackRanker` are
  **deleted** — do not reintroduce a second ranking ladder beside the resolver.
- **Stream survey:** kino.pub deliveries surveyed were AVFoundation-friendly H.264/AAC — **no FFmpeg
  engine** for core playback. That survey does not globally ban capability badges (4K/HDR) when item
  and device flags support them.
- Detail ambient muted trailer is **off on tvOS** (still + scrims + blurred poster wash). It may
  return with a dedicated hero pass.
- A player rewrite is out of scope. Skips and Up Next are thin conveniences layered on system API.

## Known bugs and traps

- **Resume race:** `PlayerView.onAppear` → `fetchWatchMark` → seek. And resume currently reads the
  wrong episode in `PlayerManager`.
- **The app target's Swift module is `KinoPub`, not `KinoPubAppleClient`.** `PRODUCT_NAME` is
  KinoPub and nothing overrides `PRODUCT_MODULE_NAME`, so a test bundle writes
  `@testable import KinoPub`. The target name is not the module name.
- **A witness to a public protocol from another module must be `public`**, even when the
  conformance is internal and used in one file — `extension AVMediaSelectionOption:
  AudioRendition` needs `public var renditionName`. Trimming it to internal fails only on the
  platforms that compile the conformance.
- **A package that builds under `swift test` can still break the app.** `swift test` runs the
  package on **macOS only**, so a symbol fenced `#if os(macOS)` and used unfenced compiles there and
  fails every simulator build — `MediaCardView`'s `isHovered` did exactly that. The tvOS/iOS
  `xcodebuild` jobs are the only thing that catches it; read them before believing green tests.
- **`playerViewControllerDidEndDismissalTransition` is unavailable in the iOS 26 SDK** —
  implementing it fails the build with "cannot override … which has been marked unavailable",
  so AVKit's delegate has nothing to say about Done on a presented player. The exit signal is
  UIKit's instead: the host controller's `viewDidAppear` after the presentation has gone.
  Re-probe the delegate on the next SDK. (Verified on CI, Xcode 26, Aug 2026.)
- **`AVAudioSession.RouteSharingPolicy.longFormVideo` is `API_UNAVAILABLE(tvos)`** — the
  constant does not compile on tvOS at all, so it cannot merely be attempted and caught. The
  policy is fenced to iOS; tvOS takes the plain `.playback` / `.moviePlayback` category.
- **kino.pub masters repeat every dub once per video rung.** Three dubs across three `AUDIO`
  groups is nine entries in AVKit's Audio menu, all reading "Russian", none of them switching
  to anything different — and no relabelling can help, because they *are* the same dub.
  `HLSAudioLabeler.collapseAudioGroups` keeps the richest group and repoints every variant at
  it before the labels are written. Audio then stops varying with the video rung, which is
  what one audio group means; the stream ladder is untouched.
- **AVKit's Audio menu shows `displayName`, not `NAME=`.** Our relabelling reaches the
  *selection* (via common metadata) but not always the row the viewer reads, which is why the
  menu can still say plain "Russian". Do not add another relabelling pass to fix that; the
  duplication above was the real complaint.
- **SRT fetch needs encoding detection** — Russian subtitles are routinely windows-1251.
- **Cue lookup is a linear scan** over ~2000 cues several times a second; it wants a binary search
  plus a cursor.
- `HLSAudioLabeler` writes a temp `.m3u8` per launch into `tmp/kinopub-hls` and never cleans up.
- Two periodic observers, and `currentPlaybackTime` republished four times a second.
- **An iOS app that sets no audio session category gets `.soloAmbient`, which the Ring/Silent
  switch mutes by definition** — and the volume keys then move the ringer, so there is no sound
  and nothing that turns any on. That was the silent iPhone player, not the stream.
  `PlaybackAudioSession` sets `.playback` / `.moviePlayback` around every stream, and
  `UIBackgroundModes: audio` is declared per-SDK in the pbxproj
  (`INFOPLIST_KEY_UIBackgroundModes[sdk=iphone*]`, so tvOS and macOS keep their own behavior) —
  which is also the prerequisite `allowsPictureInPicturePlayback` was always missing.
- `AVAssetDownloadURLSession` does not give tvOS the iOS downloads UX — **Downloads stay non-TV**.

## Open questions — do not answer them from memory

- Whether `AVPlayerView.controlsStyle` (`.default` / `.floating` / `.minimal` / `.inline`) can
  reproduce what TV.app and Music.app show on macOS, or whether those apps draw outside
  `AVPlayerView`'s documented surface. Needs a real screenshot-by-screenshot comparison; do not
  guess at private API.
- Whether the AVKit audio picker shows relabeled metadata titles or language-only `displayName`.
- Deduplicating triple AUDIO groups in HLS masters without breaking ABR.
- Real Siri Remote behavior: Menu dismiss, Subtitles menu, up-swipe trailer full screen, dual-sub
  focus.
- Auto / live transcription needing decoded PCM from HLS is largely a **tvOS 27+** concern.
