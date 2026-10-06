//
//  FeatureFlags.swift
//  KinoPubAppleClient
//

import Foundation
import KinoPubUI

/// Single source of truth for user-facing surfaces that are compiled but not yet
/// ready to ship. Flip one flag instead of scattering per-view checks.
///
/// An off flag must skip the work (network, sampling, chrome), not only hide UI.
///
/// **Every flag is switchable in the app** — Settings › Diagnostics › Feature flags, in
/// every build. What ships is `FeatureFlag.defaultValue`; a switch in the app is an
/// override stored on this device. Call sites read these names and never the storage.
enum FeatureFlags {
  /// Contained Home banner shelf. Off pending redesign — when false, Home does
  /// not sample banner cards and does not load wide poster artwork for them.
  static var homeBannerEnabled: Bool { FeatureFlag.homeBanner.isEnabled }

  /// Gates the Downloads tab, the item-detail download action, and any other
  /// downloads-facing UI. `KinoPubKit`'s `DownloadManager` / `DownloadedFilesDatabase`
  /// machinery stays compiled and available either way — this only hides entry points.
  ///
  /// TODO(downloads): when this flips on, add Download to `MediaCardContextMenus`
  /// (single source — do not hand-roll per shelf / banner / rail).
  static var downloadsEnabled: Bool { FeatureFlag.downloads.isEnabled }

  /// "All Bookmarks" overview tab (folder shelves). Off while History / Watchlist /
  /// per-folder tabs carry browsing; when false the tab is omitted and the overview
  /// catalog is not fetched.
  static var allBookmarksEnabled: Bool { FeatureFlag.allBookmarks.isEnabled }

  /// tvOS shelves + grids share one `TVPosterView` / `TVCardView` atom (same
  /// `ShelfMetrics` sizing), drawn by a recycling `UICollectionView` rather than a
  /// Lazy stack — lazy defers creation, it does not reuse cells. SwiftUI
  /// `MediaCardView` remains the fallback. iOS / macOS ignore this flag.
  ///
  /// On since 2026-08-06. **Device Hub focus validation is still outstanding** — this
  /// was turned on to be judged on a real screen, not because that check passed.
  static var tvUIKitPosters: Bool { FeatureFlag.tvUIKitPosters.isEnabled }

  /// tvOS Watch Now / Movies / Series render as **one** `UICollectionView` per page
  /// (`TVPage`: typed sections, HIG column formula, diffable snapshots) instead of one
  /// bridged rail per row inside a SwiftUI `Section` stack (`MediaRowsView`). The old
  /// path stays behind this switch until the page has been driven on a device; then it
  /// is deleted, not kept.
  static var tvPageSections: Bool { FeatureFlag.tvPageSections.isEnabled }

  /// tvOS Search as UIKit (`TVSearchPage`: `UISearchContainerViewController`, native
  /// suggestions with recents and kino.pub's type-ahead, a row of system pull-downs —
  /// type, genre, country, years, facets, sort — sent to `/v1/items/search`, the best
  /// matches as two rows of wide cards, local-first results). Off falls back to the
  /// SwiftUI `.searchable` screen.
  ///
  /// The focus trap of 2026-09-23 (Down from the tab bar skipped the keyboard, Up never
  /// left the results) was `.ignoresSafeArea()` on the search host: the keyboard,
  /// suggestions and scope bar were laid out *under* the tab bar, so the focus engine
  /// had nothing below the bar but the results. Found with `-UIFocusLoggingEnabled YES`;
  /// `testSearchFocusRoundTrip` walks the whole column both ways.
  ///
  /// tvOS 26.5+ again: Down from the Search *tab* while the bar holds focus was a no-op
  /// (Select still entered the field). `TVSearchPageHostViewController` embeds the
  /// container with a tab-bar `UIFocusGuide` into the search chrome; see
  /// `testSearchTabDownFromTabBar`.
  static var tvUIKitSearch: Bool { FeatureFlag.tvUIKitSearch.isEnabled }

  /// tvOS detail page: everything under the hero is **one** `UICollectionView`
  /// (`TVEmbeddedPage`), laid out in columns — Ratings | Reviews, Director | Cast,
  /// Similar, Stills | Facts, Type · Year · Country · Genre, Collections, then
  /// Video | Audio | Subtitles — from the same cells Watch Now and Search use. Off falls
  /// back to the SwiftUI section stack, which stays until the new page has been driven on
  /// a device; then it is deleted, not kept.
  static var tvDetailSections: Bool { FeatureFlag.tvDetailSections.isEnabled }

  /// A series detail page fetches its item with `nolinks=1` and resolves an episode's
  /// links from `/v1/items/media-links` when it is played (`MediaLinksResolver`).
  ///
  /// **Off.** It saves real bytes on a long show — most of that payload is links, and at
  /// most one episode's worth is ever used — but every playback path has to go and get a
  /// link first, and the first attempt shipped with a decoder that could not read a
  /// link-less `files` entry at all, so every series page said "Couldn't Load". The
  /// machinery stays compiled and switchable; kino.pub is making `nolinks=1` the default
  /// in a future API version, so this is what we flip when that lands — after watching a
  /// series actually play with it on.
  static var seriesDetailsWithoutLinks: Bool { FeatureFlag.seriesDetailsWithoutLinks.isEnabled }

  /// The muted trailer that starts by itself behind the detail hero (macOS today —
  /// iPhone is off for legibility, tvOS by the no-blur-over-video policy).
  ///
  /// Off means no second `AVPlayer` is ever built and no trailer stream is fetched, not
  /// a hidden video layer. Up-to-fullscreen then has nothing to open, and the Trailer
  /// button still plays the real thing through the system player.
  static var heroAmbientTrailerEnabled: Bool { FeatureFlag.heroAmbientTrailer.isEnabled }

  /// The artwork behind a detail page: the blurred-poster wash on iOS / macOS, and on
  /// tvOS the full-bleed hero still with its fold material.
  ///
  /// Off means the page sits on the plain app background and neither the wide still nor
  /// the blur buffer is decoded — the hero's own foreground (title, actions, poster) is
  /// untouched. **On tvOS that is the whole picture behind the page**, so expect a bare
  /// page there, not a subtler one.
  static var detailAmbientBackdropEnabled: Bool { FeatureFlag.detailAmbientBackdrop.isEnabled }

  /// The tvOS sidecar-SRT machinery: a custom transport-bar Subtitles menu (dual
  /// tracks), our own cue overlay, and hiding the system's Subtitles control.
  ///
  /// **Off.** Subtitles are the system player's on every platform — the master's own
  /// WebVTT renditions, styled by the system. The machinery stays compiled because the
  /// dual-subtitle stage will want it; flipping this brings the whole path back.
  static var tvOSSidecarSubtitles: Bool { FeatureFlag.tvOSSidecarSubtitles.isEnabled }

  /// Our edits to what the system player lists under Audio and Subtitles: the master
  /// rewrite (`HLSAudioLabeler`) that renames every rendition after the API row
  /// ("Русский ∙ Многоголосый, LostFilm"), numbers look-alikes ("∙ 2"), collapses the
  /// per-quality groups into one and moves `DEFAULT`.
  ///
  /// **Off.** The player gets the CDN's master untouched and AVKit lists and names the
  /// tracks itself — localized, with its own CC / SDH / Forced wording. What we still do
  /// is *choose*: `TrackResolver` picks the dub and subtitles a title opens with, and a
  /// pick made in the system menu is remembered. Both read the master as delivered
  /// (`AudioRenditions.Naming.asDelivered`, `SubtitleRenditions`).
  ///
  /// What the stock menus make of a kino.pub master is in docs/providers/kinopub/hls.md:
  /// AVFoundation merges the per-quality copies by itself (the collapse was not needed),
  /// and names an option after `NAME` only in the viewer's own language. The player logs
  /// both menus as AVFoundation hands them over (`tracks ·` lines). On brings the rewrite
  /// back unchanged.
  static var rewritesStreamTrackMenus: Bool { FeatureFlag.rewritesStreamTrackMenus.isEnabled }

  /// Our own combined IMDb + Kinopoisk score: poster plaque, hero pill, the detail
  /// "Rating" tile, and the card Rating placement / source settings. Off — IMDb and
  /// Kinopoisk show only under their own logos meanwhile.
  ///
  /// Card chrome reads it from inside `KinoPubUI`, so the value is handed to
  /// `RatingFeature.combinedEnabled` once at launch (`FeatureFlag.applyAtLaunch()`).
  static var combinedRatingEnabled: Bool { FeatureFlag.combinedRating.isEnabled }

  /// **TEMPORARY DIAGNOSTIC — DELETE ME.** Synthesises a fake season of episodes onto
  /// *movies*, so the detail page's season rail renders for a title that has none.
  ///
  /// Exists to test one specific hypothesis: that the hero blur / scroll choreography
  /// only behaves because a season rail happens to be the first section below the hero,
  /// and falls apart for movies where it is absent. Comparing a movie with and without
  /// this flag isolates "is it the content or the choreography".
  ///
  /// The fabricated episodes are **not playable** (no `files`) — this is a layout and
  /// focus probe, nothing else. DEBUG-only so it cannot reach a shipping build.
#if DEBUG
  static var fakeSeasonsOnMovies: Bool { FeatureFlag.fakeSeasonsOnMovies.isEnabled }
#else
  static let fakeSeasonsOnMovies = false
#endif
}

/// One switch, what it ships as, and when a change to it takes hold. The in-app list
/// (`FeatureFlagsView`, and the tvOS page in `TVProfileSettingsView`) is built from this.
enum FeatureFlag: String, CaseIterable, Identifiable, Sendable {
  case homeBanner
  case downloads
  case allBookmarks
  case tvUIKitPosters
  case tvPageSections
  case tvUIKitSearch
  case tvDetailSections
  case seriesDetailsWithoutLinks
  case heroAmbientTrailer
  case detailAmbientBackdrop
  case tvOSSidecarSubtitles
  case rewritesStreamTrackMenus
  case combinedRating
#if DEBUG
  case fakeSeasonsOnMovies
#endif

  var id: String { rawValue }

  /// What a build ships with, and what "Reset" returns to.
  var defaultValue: Bool {
    switch self {
    case .homeBanner: true
    case .downloads: false
    case .allBookmarks: true
    case .tvUIKitPosters: true
    case .tvPageSections: true
    case .tvUIKitSearch: true
    case .tvDetailSections: true
    case .seriesDetailsWithoutLinks: false
    case .heroAmbientTrailer: false
    case .detailAmbientBackdrop: true
    case .tvOSSidecarSubtitles: false
    case .rewritesStreamTrackMenus: false
    case .combinedRating: true
#if DEBUG
    case .fakeSeasonsOnMovies: false
#endif
    }
  }

  /// The name in the list. Developer-facing, so the code's own words, not translated.
  var title: String {
    switch self {
    case .homeBanner: "Home banner shelf"
    case .downloads: "Downloads"
    case .allBookmarks: "All Bookmarks tab"
    case .tvUIKitPosters: "UIKit poster shelves"
    case .tvPageSections: "One collection view per page"
    case .tvUIKitSearch: "UIKit Search"
    case .tvDetailSections: "Detail sections in columns"
    case .seriesDetailsWithoutLinks: "Series pages without links (nolinks=1)"
    case .heroAmbientTrailer: "Muted trailer behind the hero"
    case .detailAmbientBackdrop: "Artwork behind the detail page"
    case .tvOSSidecarSubtitles: "Sidecar SRT subtitles (dual)"
    case .rewritesStreamTrackMenus: "Rewrite the player's track menus"
    case .combinedRating: "Combined IMDb + Kinopoisk rating"
#if DEBUG
    case .fakeSeasonsOnMovies: "Fake seasons on movies"
#endif
    }
  }

  /// One line on what flipping it changes — the full story is on `FeatureFlags`.
  var summary: String {
    switch self {
    case .homeBanner: "Wide banner cards at the top of Home."
    case .downloads: "Downloads tab, download actions and storage rows."
    case .allBookmarks: "The folder-shelves overview tab in Library."
    case .tvUIKitPosters: "TVUIKit cells in a recycling collection view; off is SwiftUI cards."
    case .tvPageSections: "Watch Now, Movies and Series as one UICollectionView each."
    case .tvUIKitSearch: "UISearchContainerViewController with native suggestions; off is .searchable."
    case .tvDetailSections: "The detail page under the hero as one UICollectionView in columns; off is the SwiftUI stack."
    case .seriesDetailsWithoutLinks: "Lighter series payload; each episode's links fetched on play."
    case .heroAmbientTrailer: "A second, muted AVPlayer behind the detail hero."
    case .detailAmbientBackdrop: "Blurred poster wash (iOS, macOS) or the hero still (tvOS)."
    case .tvOSSidecarSubtitles: "Our transport-bar Subtitles menu and cue overlay instead of the system's."
    case .rewritesStreamTrackMenus: "Relabel, collapse and re-default the HLS master's audio and subtitles. Off: AVKit names them."
    case .combinedRating: "One weighted score on posters, the hero and the Rating tile."
#if DEBUG
    case .fakeSeasonsOnMovies: "A fake, unplayable season rail on movies. Layout probe."
#endif
    }
  }

  /// Which platforms read it at all — a tvOS-only switch on the Mac is a control that
  /// does nothing.
  var isRelevantHere: Bool {
    switch self {
    case .tvUIKitPosters, .tvPageSections, .tvUIKitSearch, .tvDetailSections, .tvOSSidecarSubtitles:
#if os(tvOS)
      true
#else
      false
#endif
    case .downloads:
#if os(tvOS)
      false
#else
      true
#endif
    default:
      true
    }
  }

  /// Switches that decide how the app shell is built — tabs, pages, card chrome — are read
  /// once per launch, so a flip never leaves half the app built one way and half the other.
  /// The rest are read whenever the thing they gate is next opened.
  var appliesAtLaunch: Bool {
    switch self {
    case .homeBanner, .downloads, .allBookmarks, .tvUIKitPosters, .tvPageSections,
         .tvUIKitSearch, .combinedRating:
      true
    default:
      false
    }
  }

  // MARK: - Value

  var isEnabled: Bool {
    appliesAtLaunch ? (Self.launchValues[self] ?? defaultValue) : storedValue
  }

  /// What the switch says now — for a launch-time flag, what the *next* launch will use.
  var storedValue: Bool {
    UserDefaults.standard.object(forKey: defaultsKey) as? Bool ?? defaultValue
  }

  var isOverridden: Bool {
    UserDefaults.standard.object(forKey: defaultsKey) != nil
  }

  /// A launch-time flag changed since this launch read it.
  var isPendingRelaunch: Bool {
    appliesAtLaunch && storedValue != isEnabled
  }

  /// Storing the default removes the override, so a changed default in a later build
  /// reaches a device that only ever matched it.
  func set(_ value: Bool) {
    if value == defaultValue {
      UserDefaults.standard.removeObject(forKey: defaultsKey)
    } else {
      UserDefaults.standard.set(value, forKey: defaultsKey)
    }
  }

  static func resetAll() {
    allCases.forEach { UserDefaults.standard.removeObject(forKey: $0.defaultsKey) }
  }

  private var defaultsKey: String { "featureFlag.\(rawValue)" }

  private static let launchValues: [FeatureFlag: Bool] = Dictionary(
    uniqueKeysWithValues: allCases.filter(\.appliesAtLaunch).map { ($0, $0.storedValue) }
  )

  /// Called first thing at launch: pins the launch-time values, and hands the one that
  /// lives inside a package to it.
  @MainActor
  static func applyAtLaunch() {
    _ = launchValues
    RatingFeature.combinedEnabled = FeatureFlag.combinedRating.isEnabled
  }
}

/// Defaults keys shared by the diagnostics surfaces, so a toggle and the thing it
/// toggles cannot drift apart. The "Verbose logging" switch this replaces was bound to a
/// `@State` nothing read, under the footer "Demo controls — not saved yet" — a control
/// that does nothing is worse than no control, because it looks like an answer.
enum DiagnosticsSettings {
  /// Shows the in-flight network readout over the whole app.
  static let activityOverlayKey = "diagnostics.activityOverlay"

  /// Streams the network log to the Pulse app on a Mac. Off by default — turning it on
  /// is what asks for local-network permission, and that prompt is the user's to spend.
  static let remoteLoggingKey = "diagnostics.remoteLogging"
}
