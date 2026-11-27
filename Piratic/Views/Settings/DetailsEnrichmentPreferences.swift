//
//  DetailsEnrichmentPreferences.swift
//  Piratic
//
//  Settings › Details: master metadata fetch, per-item switches, spoilers.
//  Sources rows deep-link to Integrations; they are not a second integrations catalog.
//

import Foundation

enum DetailsEnrichmentPreferences {
  static let metadataFetchingKey = "settings.details.metadataFetching"
  static let paneKey = "settings.details.enrichmentPane"

  static let hideDescriptionsKey = "settings.details.spoilers.hideDescriptions"
  static let hideTitlesKey = "settings.details.spoilers.hideTitles"
  static let blurPreviewsKey = "settings.details.spoilers.blurPreviews"

  /// On by default — enrichment is the normal path.
  static var metadataFetchingEnabled: Bool {
    UserDefaults.standard.object(forKey: metadataFetchingKey) as? Bool ?? true
  }

  static var hideDescriptions: Bool {
    UserDefaults.standard.object(forKey: hideDescriptionsKey) as? Bool ?? false
  }

  static var hideTitles: Bool {
    UserDefaults.standard.object(forKey: hideTitlesKey) as? Bool ?? false
  }

  static var blurPreviews: Bool {
    UserDefaults.standard.object(forKey: blurPreviewsKey) as? Bool ?? false
  }

  static func isItemEnabled(_ item: DetailsEnrichmentItem) -> Bool {
    UserDefaults.standard.object(forKey: item.enabledKey) as? Bool ?? true
  }

  enum Pane: String, CaseIterable, Identifiable {
    case items
    case sources

    var id: String { rawValue }

    var titleKey: String {
      switch self {
      case .items: return "Items"
      case .sources: return "Sources"
      }
    }
  }
}

/// One enrichment surface on the title page (image kind or info block).
enum DetailsEnrichmentItem: String, CaseIterable, Identifiable, Hashable {
  // Images
  case posters
  case thumbnails
  case covers
  case backdrops
  case logos
  // Info
  case skipTimings
  case ratings
  case reviews
  case castAndTeam
  case characters
  case airDate
  case episodes
  case seasons
  case specials
  case photos
  case videos
  case studios
  case lists
  case awards
  case counters
  case releaseDate
  case trivia
  case boxOffice

  var id: String { rawValue }

  var enabledKey: String { "settings.details.item.\(rawValue).enabled" }

  enum Group {
    case images
    case info
  }

  var group: Group {
    switch self {
    case .posters, .thumbnails, .covers, .backdrops, .logos: return .images
    default: return .info
    }
  }

  var titleKey: String {
    switch self {
    case .posters: return "Posters"
    case .thumbnails: return "Thumbnails"
    case .covers: return "Covers"
    case .backdrops: return "Backdrops"
    case .logos: return "Logos"
    case .skipTimings: return "Skip timings"
    case .ratings: return "Ratings"
    case .reviews: return "Reviews"
    case .castAndTeam: return "Cast & Team"
    case .characters: return "Characters"
    case .airDate: return "Air Date"
    case .episodes: return "Episodes"
    case .seasons: return "Seasons"
    case .specials: return "Specials"
    case .photos: return "Photos"
    case .videos: return "Videos"
    case .studios: return "Studios"
    case .lists: return "Lists"
    case .awards: return "Awards"
    case .counters: return "Counters"
    case .releaseDate: return "Release date"
    case .trivia: return "Trivia"
    case .boxOffice: return "Box office"
    }
  }

  var systemImage: String {
    switch self {
    case .posters: return "rectangle.portrait.fill"
    case .thumbnails: return "rectangle.fill"
    case .covers: return "book.closed.fill"
    case .backdrops: return "photo.fill"
    case .logos: return "textformat"
    case .skipTimings: return "forward.fill"
    case .ratings: return "star.fill"
    case .reviews: return "text.bubble.fill"
    case .castAndTeam: return "person.3.fill"
    case .characters: return "theatermasks.fill"
    case .airDate: return "calendar"
    case .episodes: return "play.rectangle.fill"
    case .seasons: return "square.stack.3d.up.fill"
    case .specials: return "sparkles.tv.fill"
    case .photos: return "photo.on.rectangle.angled"
    case .videos: return "film.fill"
    case .studios: return "building.2.fill"
    case .lists: return "list.bullet.rectangle.fill"
    case .awards: return "trophy.fill"
    case .counters: return "number"
    case .releaseDate: return "calendar.badge.clock"
    case .trivia: return "lightbulb.fill"
    case .boxOffice: return "banknote.fill"
    }
  }

  /// Optional Integration to hint / open for deeper setup.
  var relatedIntegration: Integration? {
    switch self {
    case .posters, .thumbnails, .covers, .backdrops, .logos, .photos, .videos,
         .episodes, .seasons, .specials, .airDate, .releaseDate, .studios, .lists:
      return .tmdb
    case .ratings, .reviews, .castAndTeam, .characters, .trivia, .boxOffice, .awards, .counters:
      return .kinopoisk
    case .skipTimings:
      return .skipDB
    }
  }

  var footerKey: String {
    switch self {
    case .videos:
      return "Trailers, teasers, behind the scenes, featurettes."
    case .lists:
      return "Collections and categories from metadata sources."
    case .skipTimings:
      return "Intro, recap and credits markers used by Skip."
    default:
      return "Fetched for the title page when metadata is on."
    }
  }

  static var imageItems: [DetailsEnrichmentItem] {
    [.posters, .thumbnails, .covers, .backdrops, .logos]
  }

  /// Title-page order: playable rails, then Ratings → … → Skip (player).
  static var infoItems: [DetailsEnrichmentItem] {
    [
      .episodes, .seasons, .specials,
      .ratings, .reviews, .castAndTeam, .characters,
      .photos, .trivia, .lists, .videos,
      .studios, .awards, .boxOffice, .counters,
      .airDate, .releaseDate, .skipTimings,
    ]
  }
}

/// Integrations listed under Details › Sources — detail-oriented hints into Integrations.
enum DetailsEnrichmentSource {
  static var rows: [Integration] {
    Integration.available.filter { integration in
      switch integration {
      case .kinopoisk, .tmdb, .omdb, .trakt, .douban, .myShows, .wikidata,
           .skipDB, .theIntroDB, .myAnimeList:
        return true
      case .plex, .simkl, .anilist, .shikimori:
        return false
      }
    }
  }
}
