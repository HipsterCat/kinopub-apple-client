//
//  CoverArtwork.swift
//  KinoPubUI
//
//  Appearance › Covers and images. Unset, the choice follows the app language:
//  Russian → Russian covers, every other language → English. An explicit choice
//  stays put when the interface language changes.
//
//  "In Russian" replaces kino.pub's vertical covers when the title has a Kinopoisk
//  id. `big` and `medium` (what Apple TV asks for — about 667 pt wide) become
//  https://kinopoiskapiunofficial.tech/images/posters/kp/{id}.jpg (667×1000).
//  `small` becomes kp_small (360×540), and only a request that already asked for
//  small takes that file. Wide stills are a different picture and stay kino.pub's.
//  The stored poster URL stays the kino.pub one, so switching back does not need
//  a refetch.
//
//  With the worker configured (``CoverArtwork/configureWorker(_:pixelWidth:)``, done
//  once at launch), every vertical kino.pub cover is asked of the worker's poster route
//  instead: TMDB in the cover language, then kino.pub's file, then Kinopoisk, as WebP at
//  the screen's poster width (Sasha, 2026-11-26, kino.pub's CDN was down). The direct
//  Kinopoisk and kino.pub files stay as the ladder's later rungs for a worker outage.
//

import Foundation
import Synchronization
import KinoPubMetadata

public enum CoverArtworkLanguage: String, CaseIterable, Identifiable, Sendable {
  case english
  case russian

  public var id: String { rawValue }

  public var titleKey: String {
    switch self {
    case .english: return "In English"
    case .russian: return "In Russian"
    }
  }
}

public enum CoverArtworkPreferences {
  public static let languageKey = "appearance.coverLanguage"
  public static let didChange = Notification.Name("kinopub.coverArtworkLanguage")

  /// The stored choice, or the language default when the viewer has not picked.
  public static var language: CoverArtworkLanguage {
    if let raw = UserDefaults.standard.string(forKey: languageKey),
       let value = CoverArtworkLanguage(rawValue: raw) {
      return value
    }
    return inferredDefault
  }

  /// Russian interface → Russian covers. English and any other language → English.
  public static var inferredDefault: CoverArtworkLanguage {
    let code = UserDefaults.standard.string(forKey: "selectedLanguage")
      ?? Locale.current.language.languageCode?.identifier
      ?? "en"
    return code == "ru" ? .russian : .english
  }

  public static func set(_ language: CoverArtworkLanguage) {
    guard UserDefaults.standard.string(forKey: languageKey) != language.rawValue else { return }
    UserDefaults.standard.set(language.rawValue, forKey: languageKey)
    NotificationCenter.default.post(name: didChange, object: nil)
  }
}

public enum CoverArtwork {
  private struct Worker: Sendable {
    let route: TitleImageRoute
    let pixelWidth: Int
    let widePixelWidth: Int
  }

  /// Read from cell configuration on any thread; written once at launch.
  private static let worker = Mutex<Worker?>(nil)

  /// Turns the worker's poster route on for every ``MediaCard/coverURL``. `pixelWidth` is
  /// the one width every poster asks for, so the grid, the banner, the peek and Top Shelf
  /// share one URL (and one cache entry) per title. A route with no base URL turns it off.
  /// `widePixelWidth` is the same for wide title cards (Continue Watching, History).
  public static func configureWorker(_ route: TitleImageRoute, pixelWidth: Int,
                                     widePixelWidth: Int = 0) {
    worker.withLock {
      $0 = route.isConfigured
        ? Worker(route: route, pixelWidth: pixelWidth,
                 widePixelWidth: widePixelWidth > 0 ? widePixelWidth : pixelWidth)
        : nil
    }
  }

  /// The worker's URL for a wide card that shows the title's kino.pub wide cover: cover in
  /// the cover language → textless backdrop → that kino.pub wide (Sasha, 2026-11-26).
  /// Nil for episode stills and anything that is not a kino.pub `/item/wide/` file.
  static func workerWideURL(for card: MediaCard) -> String? {
    guard let landscape = card.landscapeImageURL, landscape.contains("/item/wide/"),
          let worker = worker.withLock({ $0 }), card.itemID > 0 else { return nil }
    let route = TitleImageRoute(baseURL: worker.route.baseURL, language: coverLanguageCode)
    return route.wideCard(kinopubID: card.itemID, imdb: card.imdbID, kinopoisk: card.kinopoiskID,
                          width: worker.widePixelWidth)?.absoluteString
  }

  private static var coverLanguageCode: String {
    CoverArtworkPreferences.language == .english ? "en" : "ru"
  }

  /// The worker's poster URL for a kino.pub vertical cover, in the cover language. Nil
  /// with no worker, no title id, or art that is not a kino.pub vertical cover.
  static func workerPosterURL(for card: MediaCard) -> String? {
    guard let worker = worker.withLock({ $0 }), card.itemID > 0,
          tier(ofKinopubPoster: card.posterURL) != nil else { return nil }
    let route = TitleImageRoute(baseURL: worker.route.baseURL, language: coverLanguageCode)
    return route.poster(kinopubID: card.itemID, imdb: card.imdbID, kinopoisk: card.kinopoiskID,
                        width: worker.pixelWidth)?.absoluteString
  }

  /// The Kinopoisk one-sheet for a kino.pub vertical cover, when Russian covers
  /// are on and `kinopoiskID` is a real id. Anything else — wide art, a missing
  /// id, English covers — comes back unchanged.
  public static func resolve(url: String, kinopoiskID: Int?) -> String {
    guard CoverArtworkPreferences.language == .russian,
          let kinopoiskID, kinopoiskID > 0,
          let tier = tier(ofKinopubPoster: url) else { return url }
    return kinopoiskURL(id: kinopoiskID, tier: tier)
  }

  /// `small` is the 360×540 file. `medium` and `big` are the 667×1000 file.
  public static func kinopoiskURL(id: Int, tier: Tier) -> String {
    let folder = tier == .small ? "kp_small" : "kp"
    return "https://kinopoiskapiunofficial.tech/images/posters/\(folder)/\(id).jpg"
  }

  public enum Tier {
    case regular
    case small
  }

  static func tier(ofKinopubPoster url: String) -> Tier? {
    if url.contains("/item/small/") { return .small }
    if url.contains("/item/medium/") || url.contains("/item/big/") { return .regular }
    return nil
  }
}

public extension MediaCard {
  /// Vertical cover to decode: the worker's poster route when it is configured, else the
  /// Russian Kinopoisk file or kino.pub's own. Landscape cards keep `landscapeImageURL`.
  var coverURL: String {
    CoverArtwork.workerPosterURL(for: self) ?? directCoverURL
  }

  /// What a wide card draws first: the worker's cover › backdrop › wide chain for a
  /// title's wide cover, else `landscapeImageURL` as it is (an episode still).
  var landscapeArtworkURL: String? {
    CoverArtwork.workerWideURL(for: self) ?? landscapeImageURL
  }

  /// The cover without the worker — the ladder's rung for a worker outage.
  var directCoverURL: String {
    CoverArtwork.resolve(url: posterURL, kinopoiskID: kinopoiskID)
  }
}

public extension MediaCard {
  /// Pictures a card's artwork tries, in order: the next one only when the one before
  /// failed, with the plain plate under the wait — one picture per tile, the same
  /// ladder as tvOS (`TVUIKitMediaItemRail`, Sasha 2026-11-21).
  ///
  /// A vertical card only ever draws vertical covers: the worker's poster, the Russian
  /// cover, then kino.pub's own. The title's wide backdrop used to go up first while the Kinopoisk cover
  /// loaded, cropped into the poster tile, and stayed when it failed (2026-11-23).
  /// A wide card: unique still → kino.pub thumb on 404 (KP-23) → series backdrop.
  var artworkLadder: [URL] {
    isLandscape
      ? Self.ladder([landscapeArtworkURL ?? posterURL, landscapeImageURL, fallbackLandscapeURL, backdropURL])
      : coverLadder
  }

  /// The vertical cover's rungs whatever the card's shape: worker poster, direct
  /// Russian cover, kino.pub's file. Poster lockups (`TVUIKitPosterCell`, the banner).
  var coverLadder: [URL] {
    Self.ladder([coverURL, directCoverURL, posterURL])
  }

  private static func ladder(_ strings: [String?]) -> [URL] {
    var ladder: [URL] = []
    for string in strings {
      guard let string, !string.isEmpty, let url = URL(string: string),
            !ladder.contains(url) else { continue }
      ladder.append(url)
    }
    return ladder
  }
}
