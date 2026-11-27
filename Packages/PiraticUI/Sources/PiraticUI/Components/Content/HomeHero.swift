//
//  HomeHero.swift
//  PiraticUI
//
//  The Home hero's data, on every platform: which titles it fronts, what each one's
//  picture, logo and Play are, and the words of its line and plot. tvOS draws it in
//  UIKit (`TVPageHeroCell`), iOS / iPadOS / macOS in SwiftUI (`HomeHeroCarousel`); both
//  read the same values, so a title says the same thing in each.
//

import CoreGraphics
import Foundation

/// The Home hero's names off tvOS, where nothing else is a "TV page".
public typealias HomeHero = TVPageHero
public typealias HomeHeroFeature = TVPageFeature

/// One title in the banner: its card and the title-logo slot (pending / URL / miss).
public struct TVPageFeature: Hashable {
  public let card: MediaCard
  public let logo: TitleLogoResolution
  /// The textless wide frame from the worker's image route. Tried first; a 404 there
  /// falls back to the card's own kino.pub wide still (`card.backdropImageURL`), never
  /// to the portrait poster.
  public let backdrop: URL?
  /// Play as the detail page draws it for this title (`MediaActionCatalog.play`: the
  /// label, the resume bar, Replay); nil until the title's details are in, when the
  /// hero shows plain Play.
  public let play: MediaActionAppearance?
  /// The title is in at least one bookmark folder (the glyph fills, as on the detail page).
  public let isBookmarked: Bool

  public var logoURL: URL? { logo.url }

  /// The backdrop chain, first that loads wins.
  public var backdropCandidates: [URL] {
    var seen = Set<String>()
    var ordered: [URL?] = [backdrop]
    if card.hasSpecifiedWideArtwork || !(card.backdropURL ?? "").isEmpty {
      ordered.append(URL(string: card.backdropURL ?? card.landscapeImageURL ?? ""))
    }
    return ordered
      .compactMap { $0 }
      .filter { !$0.absoluteString.isEmpty && seen.insert($0.absoluteString).inserted }
  }

  public init(card: MediaCard, logo: TitleLogoResolution = .missing, backdrop: URL? = nil,
              play: MediaActionAppearance? = nil, isBookmarked: Bool = false) {
    self.card = card
    self.logo = logo
    self.backdrop = backdrop
    self.play = play
    self.isBookmarked = isBookmarked
  }

  public init(card: MediaCard, logoURL: URL?) {
    self.card = card
    self.logo = logoURL.map { .url($0) } ?? .missing
    self.backdrop = nil
    self.play = nil
    self.isBookmarked = false
  }
}

/// What the hero carousel shows: its titles, in order, and the words on its buttons.
/// The words come from the app — this package has no localization tables.
public struct TVPageHero: Hashable {
  public struct Labels: Hashable {
    public let play: String
    public let details: String
    /// The Bookmark menu's heading, as on the detail page.
    public let bookmark: String
    public let next: String
    /// The Mac / iPad hover arrow back; tvOS has no such button.
    public let previous: String
    /// The Bookmark menu's line when there are no folders yet.
    public let noBookmarkFolders: String

    public init(play: String, details: String, bookmark: String, next: String,
                previous: String = "", noBookmarkFolders: String = "") {
      self.play = play
      self.details = details
      self.bookmark = bookmark
      self.next = next
      self.previous = previous
      self.noBookmarkFolders = noBookmarkFolders
    }
  }

  public let features: [TVPageFeature]
  public let labels: Labels

  public init(features: [TVPageFeature], labels: Labels) {
    self.features = features
    self.labels = labels
  }
}

/// The hero's words, shared by the tvOS banner, the tvOS hero and the SwiftUI hero.
public enum HomeHeroText {
  /// Returns a concise, readable synopsis snippet of at least `minLength` characters
  /// (or the full text if shorter), preventing awkward short fragments like "1903 год.".
  public static func synopsis(of text: String, minLength: Int = 45) -> String? {
    let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return nil }
    var result = ""
    text.enumerateSubstrings(in: text.startIndex..., options: .bySentences) { sentence, _, _, stop in
      guard let s = sentence?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return }
      if result.isEmpty {
        result = s
      } else {
        result += " " + s
      }
      if result.count >= minLength {
        stop = true
      }
    }
    return result.isEmpty ? text : result
  }

  /// What the Home hero says, on every platform — tvOS's UIKit hero and the SwiftUI
  /// one on iOS / iPadOS / macOS read these, so a change here changes both (Sasha,
  /// 2026-11-04).
  public enum Rules {
    /// Genres leading the meta line.
    public static let genres = 2
    /// Vote counts after each score: «IMDb 8.4 (104)».
    public static let showsVotes = true
    /// kino.pub's plot is long and its first sentences are rarely a tagline: off until
    /// there is a quick source of a short one (Sasha, 2026-10-30).
    public static let showsSynopsis = false
  }

  /// The metadata parts after the scores:
  /// Order: 1. Genre (useful, skipping generic anime/cartoons), 2. Year/span (2026, 2024–26), 3. Country, 4. Duration/Volume (2+ seasons / episodes / runtime).
  /// `genres`: how many genres lead the line — the tvOS banner names one, the iOS / macOS
  /// hero two (Sasha, 2026-10-30).
  public static func metaParts(for card: MediaCard, genres: Int = 1) -> [String] {
    // As the title page writes it (Sasha, 2026-11-16): what and when first — «Сериал
    // 2025–», «2026» — then the genres as one phrase, «Драма, криминал», the country,
    // and how long. The line drops its last parts when it does not fit.
    var parts: [String] = []
    let duration = card.bannerDurationText().flatMap { $0.isEmpty ? nil : $0 }

    // 1. Вид (сериал, когда сезонов не знаем) и год / года (2026, 2024–26)
    // A shelf payload knows no seasons or episodes: at least say it is a series, the
    // way the Apple TV app's «Телешоу · Drama» does.
    let saysSeriesKind = card.isSeries && duration == nil
    let kind = saysSeriesKind
      ? NSLocalizedString(card.seriesKindKey, comment: "A series, in the banner's line") : nil
    let years = card.bannerYearSpan.flatMap { $0.isEmpty ? nil : $0 }
    let head = [kind, years].compactMap { $0 }
    if !head.isEmpty { parts.append(head.joined(separator: " ")) }

    // 2. Жанры одной фразой (пропуская базовые/банальные: аниме, мультфильм)
    let useful = card.usefulGenres(limit: genres,
                                   omittingDocumentary: saysSeriesKind
                                     && card.seriesKindKey == "Kind_documentarySeries_One")
    if let first = useful.first {
      parts.append(([first] + useful.dropFirst().map { $0.lowercased() }).joined(separator: ", "))
    }

    // 3. Страна
    if let country = card.country, !country.isEmpty {
      parts.append(country)
    }

    // 4. Длительность: сезоны если 1+, серии если 1, duration у фильма
    if let duration {
      parts.append(duration)
    }

    return parts
  }
}

/// Loads the neighbours' pictures before they are needed (Sasha, 2026-11-10): the title
/// before the current one and the two after it, logo and backdrop, decoded into memory
/// at the size they will be drawn. A turn then paints from the cache in the same frame,
/// and the line under the logo has its language stamp (`imageWithSource` remembers it)
/// instead of waiting a second for it. Nuke coalesces a load already under way.
@MainActor
public enum HomeHeroWarmup {
  /// Behind by one, ahead by two.
  static let offsets = [1, -1, 2]

  /// - Parameter backdropSize: the size the backdrop is decoded to where it is drawn
  ///   (must match the display request; `.zero` is full resolution and should be rare);
  ///   `nil` while that size is not known yet: logos only, at ``Artwork/logoDecodeSize``.
  public static func warm(_ features: [HomeHeroFeature], around index: Int, backdropSize: CGSize?) {
    let count = features.count
    guard count > 1 else { return }
    var seen = Set<Int>()
    for offset in [0] + offsets {
      let at = ((index + offset) % count + count) % count
      guard seen.insert(at).inserted else { continue }
      let feature = features[at]
      if let logo = feature.logoURL { load(logo, size: Artwork.logoDecodeSize, mode: .fit) }
      if let backdropSize, let backdrop = feature.backdropCandidates.first {
        // Same key as the hero paint (`.fillTop`) — centre `.fill` would miss the cache.
        load(backdrop, size: backdropSize, mode: .fillTop)
      }
    }
  }

  private static func load(_ url: URL, size: CGSize, mode: Artwork.ResizeMode) {
    guard Artwork.cachedImage(for: url, size: size, mode: mode) == nil else { return }
    Task(priority: .utility) {
      _ = try? await Artwork.imageWithSource(for: url, size: size, mode: mode)
    }
  }
}
