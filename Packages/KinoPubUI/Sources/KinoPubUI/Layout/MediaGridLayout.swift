//
//  MediaGridLayout.swift
//  KinoPubUI
//
//  How a catalogue grid draws its titles: 2:3 posters, or the 16:9 wide card Home's
//  Continue Watching already uses — the same `MediaCardView`, the same
//  `ShelfMetrics.landscape` columns. Not a second card.
//

import SwiftUI
import KinoPubBackend

/// The grid / wide cells switch of the listing pages (Catalog, Search, a person's
/// credits, a collection), as the SF Symbols app and AniShelf have it in the toolbar.
public enum MediaGridLayout: String, CaseIterable, Identifiable, Sendable {
  case posters
  case wide

  public var id: String { rawValue }

  /// One choice for every listing that offers the switch: flipping it on Catalog and
  /// finding posters again on Search would read as the switch not having worked.
  public static let storageKey = "mediaGridLayout"

  /// Existing catalogue keys («Постеры» / «Горизонтальные»).
  public var titleKey: String {
    switch self {
    case .posters: return "Posters"
    case .wide: return "Landscape"
    }
  }

  public var systemImage: String {
    switch self {
    case .posters: return "square.grid.3x2"
    case .wide: return "rectangle.grid.2x2"
    }
  }
}

public extension EnvironmentValues {
  /// Set by a page that offers the switch. Nil — every other grid — draws the cards as
  /// they come.
  @Entry var mediaGridLayout: MediaGridLayout? = nil
}

public extension MediaCard {

  /// The same card with its 16:9 artwork replaced; nil makes it a poster card again.
  /// Words, facts and viewer state are untouched.
  func withLandscapeImage(_ url: String?) -> MediaCard {
    MediaCard(id: id, posterURL: posterURL, title: title, subtitle: subtitle,
              watchedAt: watchedAt, scores: scores, progress: progress,
              badge: badge, backdropURL: backdropURL,
              hasSpecifiedWideArtwork: hasSpecifiedWideArtwork,
              overview: overview, landscapeImageURL: url,
              overlayLabel: overlayLabel, offeredName: offeredName, hoverStillURL: hoverStillURL,
              itemID: itemID, video: video, season: season,
              seasonCount: seasonCount, mediaID: mediaID, isWatched: isWatched,
              isSeries: isSeries, isInHistory: isInHistory, viewerState: viewerState,
              is4K: is4K, isHDR: isHDR, isHD: isHD, is3D: is3D,
              hasClosedCaptions: hasClosedCaptions, year: year, yearEnd: yearEnd,
              unwatchedEpisodes: unwatchedEpisodes,
              durationSeconds: durationSeconds, genres: genres, country: country,
              primaryAction: primaryAction, opensCollection: opensCollection,
              captionStats: captionStats, imdbID: imdbID, kinopoiskID: kinopoiskID)
  }

  /// A catalogue item's card for `layout`: wide takes the title's own 16:9 cover
  /// (`titleWideArtwork`, the rule Continue Watching follows), then its backdrop, then
  /// the poster cropped — every tile in a wide grid stays 16:9.
  static func card(for item: MediaItem, in layout: MediaGridLayout?) -> MediaCard {
    let card = MediaCard(item)
    guard layout == .wide else { return card }
    let wide = titleWideArtwork(posters: item.posters)
      ?? card.backdropURL.flatMap { $0.isEmpty ? nil : $0 }
      ?? card.posterURL
    return card.withLandscapeImage(wide)
  }
}
