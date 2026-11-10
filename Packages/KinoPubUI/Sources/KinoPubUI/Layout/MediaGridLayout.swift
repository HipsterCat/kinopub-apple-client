//
//  MediaGridLayout.swift
//  KinoPubUI
//
//  How a catalogue listing draws its titles: a poster grid, or a table/list of
//  poster + title + meta rows. Shared across Catalog, Search, person credits and
//  collections so flipping the switch on one page is visible on the next.
//

import SwiftUI
import KinoPubBackend

/// The grid / list switch of the listing pages (Catalog, Search, a person's
/// credits, a collection). List is a table of rows — not a wide 16:9 grid.
public enum MediaGridLayout: String, CaseIterable, Identifiable, Sendable {
  case posters
  case list

  public var id: String { rawValue }

  /// One choice for every listing that offers the switch: flipping it on Catalog and
  /// finding posters again on Search would read as the switch not having worked.
  public static let storageKey = "mediaGridLayout"

  /// Existing catalogue keys («Постеры» / «Список»).
  public var titleKey: String {
    switch self {
    case .posters: return "Posters"
    case .list: return "List"
    }
  }

  public var systemImage: String {
    switch self {
    case .posters: return "square.grid.3x2"
    case .list: return "list.bullet"
    }
  }

  /// Resolves a stored raw value, including the retired `wide` landscape layout
  /// (mapped to list — that switch was the alternative view, not a second grid).
  public static func resolved(from raw: String?) -> MediaGridLayout {
    switch raw {
    case list.rawValue, "wide": return .list
    default: return .posters
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

  /// A catalogue item's card for `layout`. List layout keeps the poster card; the
  /// page draws `CatalogMediaRow` instead of a grid cell.
  static func card(for item: MediaItem, in layout: MediaGridLayout?) -> MediaCard {
    MediaCard(item)
  }
}
