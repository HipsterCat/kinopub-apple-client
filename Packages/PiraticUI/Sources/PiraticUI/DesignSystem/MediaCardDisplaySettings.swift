//
//  MediaCardDisplaySettings.swift
//  PiraticUI
//
//  The card settings as one observable snapshot, read by every MediaCardView.
//

import Foundation
import Observation

/// Every catalog card used to carry an `@AppStorage` per setting — 24 of them, each a
/// `UserDefaults` lookup and a defaults observer per card, re-read whenever the card's body
/// ran. In a Mac trace of a scrolling title page (2026-11-28) those `CFPrefs` lookups were a
/// visible part of `MediaCardView.body`, the heaviest app frame. One snapshot, refreshed when
/// `UserDefaults` changes and published only when a card setting actually differs.
/// Settings keep writing with `@AppStorage`; this only reads.
@MainActor
@Observable
public final class MediaCardDisplaySettings {
  public static let shared = MediaCardDisplaySettings()

  public struct Snapshot: Equatable, Sendable {
    public var ratingPlacementRaw: String
    public var ratingSourceRaw: String
    public var ratingVisibilityRaw: String
    public var showVoteCount: Bool
    public var showIMDbRating: Bool
    public var showKinopoiskRating: Bool
    public var sortRatingsByVotes: Bool
    public var fadedRatingIcons: Bool
    public var capabilityPlacementRaw: String
    public var show4K: Bool
    public var showHDR: Bool
    public var showHD: Bool
    public var show3D: Bool
    public var showCC: Bool
    public var editorialPlacementRaw: String
    public var showOriginalTitle: Bool
    public var showYear: Bool
    public var showDuration: Bool
    public var showGenre: Bool
    public var showCountry: Bool
    public var showBookmarkSymbol: Bool
    public var progressVisibilityRaw: String
    public var watchedStyleRaw: String
    public var coverLanguage: String
  }

  public private(set) var snapshot: Snapshot

  @ObservationIgnored private var observer: NSObjectProtocol?

  private init() {
    snapshot = Self.read()
    observer = NotificationCenter.default.addObserver(
      forName: UserDefaults.didChangeNotification, object: nil, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.refresh() }
    }
  }

  private func refresh() {
    let fresh = Self.read()
    if fresh != snapshot { snapshot = fresh }
  }

  private static func read() -> Snapshot {
    let d = UserDefaults.standard
    return Snapshot(
      ratingPlacementRaw: d.string(MediaCardDisplayPreferences.ratingPlacementKey, MediaCardDisplayPreferences.defaultRatingPlacement.rawValue),
      ratingSourceRaw: d.string(MediaCardDisplayPreferences.ratingSourceKey, MediaCardDisplayPreferences.defaultRatingSource.rawValue),
      ratingVisibilityRaw: d.string(MediaCardDisplayPreferences.ratingVisibilityKey, MediaCardDisplayPreferences.defaultRatingVisibility.rawValue),
      showVoteCount: d.bool(MediaCardDisplayPreferences.showVoteCountKey, MediaCardDisplayPreferences.defaultShowVoteCount),
      showIMDbRating: d.bool(MediaCardDisplayPreferences.showIMDbRatingKey, MediaCardDisplayPreferences.defaultShowIMDbRating),
      showKinopoiskRating: d.bool(MediaCardDisplayPreferences.showKinopoiskRatingKey, MediaCardDisplayPreferences.defaultShowKinopoiskRating),
      sortRatingsByVotes: d.bool(MediaCardDisplayPreferences.sortRatingsByVotesKey, MediaCardDisplayPreferences.defaultSortRatingsByVotes),
      fadedRatingIcons: d.bool(MediaCardDisplayPreferences.fadedRatingIconsKey, MediaCardDisplayPreferences.defaultFadedRatingIcons),
      capabilityPlacementRaw: d.string(MediaCardDisplayPreferences.capabilityPlacementKey, MediaCardDisplayPreferences.defaultCapabilityPlacement.rawValue),
      show4K: d.bool(MediaCardDisplayPreferences.show4KKey, MediaCardDisplayPreferences.defaultShow4K),
      showHDR: d.bool(MediaCardDisplayPreferences.showHDRKey, MediaCardDisplayPreferences.defaultShowHDR),
      showHD: d.bool(MediaCardDisplayPreferences.showHDKey, MediaCardDisplayPreferences.defaultShowHD),
      show3D: d.bool(MediaCardDisplayPreferences.show3DKey, MediaCardDisplayPreferences.defaultShow3D),
      showCC: d.bool(MediaCardDisplayPreferences.showCCKey, MediaCardDisplayPreferences.defaultShowCC),
      editorialPlacementRaw: d.string(MediaCardDisplayPreferences.editorialPlacementKey, MediaCardDisplayPreferences.defaultEditorialPlacement.rawValue),
      showOriginalTitle: d.bool(MediaCardDisplayPreferences.showOriginalTitleKey, MediaCardDisplayPreferences.defaultShowOriginalTitle),
      showYear: d.bool(MediaCardDisplayPreferences.showYearKey, MediaCardDisplayPreferences.defaultShowYear),
      showDuration: d.bool(MediaCardDisplayPreferences.showDurationKey, MediaCardDisplayPreferences.defaultShowDuration),
      showGenre: d.bool(MediaCardDisplayPreferences.showGenreKey, MediaCardDisplayPreferences.defaultShowGenre),
      showCountry: d.bool(MediaCardDisplayPreferences.showCountryKey, MediaCardDisplayPreferences.defaultShowCountry),
      showBookmarkSymbol: d.bool(MediaCardDisplayPreferences.showBookmarkSymbolKey, MediaCardDisplayPreferences.defaultShowBookmarkSymbol),
      progressVisibilityRaw: d.string(MediaCardDisplayPreferences.progressVisibilityKey, MediaCardDisplayPreferences.defaultProgressVisibility.rawValue),
      watchedStyleRaw: d.string(MediaCardDisplayPreferences.watchedStyleKey, MediaCardDisplayPreferences.defaultWatchedStyle.rawValue),
      coverLanguage: d.string(CoverArtworkPreferences.languageKey, "")
    )
  }
}

private extension UserDefaults {
  func bool(_ key: String, _ fallback: Bool) -> Bool { object(forKey: key) as? Bool ?? fallback }
  func string(_ key: String, _ fallback: String) -> String { string(forKey: key) ?? fallback }
}
