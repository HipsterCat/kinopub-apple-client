//
//  MediaItemSeriesFacts.swift
//  KinoPubAppleClient
//
//  Where a series is in its run and how much of it there is — said once, for the SwiftUI
//  info columns and for the table under the tvOS detail page, so the two cannot disagree about
//  whether a show has ended.
//

import Foundation
import KinoPubBackend
import KinoPubMetadata

enum SeriesFacts {

  /// TMDB's word for the run when it has one, kino.pub's `finished` flag when it does not.
  static func isFinished(_ item: MediaItem, _ metadata: TitleMetadata) -> Bool {
    switch metadata.status?.lowercased() {
    case "ended", "canceled": return true
    case "returning series", "in production", "pilot", "planned": return false
    default: return item.finished
    }
  }

  /// The localization key of the status line. Nil for anything that is not a series — by its
  /// payload (it has seasons) or by its type, which a listing card has before the details land.
  static func statusKey(_ item: MediaItem, _ metadata: TitleMetadata) -> String? {
    guard item.isSeries || item.isEpisodicType else { return nil }
    switch metadata.status?.lowercased() {
    case "ended": return "MediaItem_StatusEnded"
    case "canceled": return "MediaItem_StatusCanceled"
    case "returning series", "in production", "pilot", "planned":
      return "MediaItem_StatusInProduction"
    default: return item.seriesStatusKey
    }
  }

  /// The years it aired, as a line: "с 2026" while it is still airing, "с 2019 по 2026" once it has
  /// ended, the one year when it began and ended in it. Falls back to kino.pub's year when TMDB
  /// has no air dates. Nil when neither knows.
  static func years(_ item: MediaItem, _ metadata: TitleMetadata) -> String? {
    let calendar = Calendar.current
    let start = metadata.firstAirDate.map { calendar.component(.year, from: $0) }
      ?? (item.year > 0 ? item.year : nil)
    guard let start else { return nil }
    guard isFinished(item, metadata) else {
      return String(format: "MediaItem_SinceDate".localized, "\(start)")
    }
    let end = metadata.lastAirDate.map { calendar.component(.year, from: $0) } ?? start
    return end == start
      ? "\(start)"
      : String(format: "MediaItem_YearsRange".localized, "\(start)", "\(end)")
  }

  /// "18 сезонов, 386 серий" — TMDB's totals (specials excluded); what kino.pub carries when TMDB
  /// has none. Nil when nobody has counted.
  static func volume(_ item: MediaItem, _ metadata: TitleMetadata) -> String? {
    if let seasons = metadata.numberOfSeasons, seasons > 0 {
      var text = "\(seasons) \(unit(seasons, .season))"
      if let episodes = metadata.numberOfEpisodes, episodes > 0 {
        text += ", \(episodes) \(unit(episodes, .episode))"
      }
      return text
    }
    guard let counts = item.volumeCounts, counts.seasons > 0 else { return nil }
    var text = "\(counts.seasons) \(unit(counts.seasons, .season))"
    if counts.episodes > 0 { text += ", \(counts.episodes) \(unit(counts.episodes, .episode))" }
    return text
  }

  enum Unit { case season, episode, special }

  /// Grammatically correct unit for the running locale.
  static func unit(_ count: Int, _ kind: Unit) -> String {
    let form = localizedPluralForm(count)
    let key: String
    switch (kind, form) {
    case (.season, 0): key = "MediaItem_UnitSeasonOne"
    case (.season, 1): key = "MediaItem_UnitSeasonFew"
    case (.season, 2): key = "MediaItem_UnitSeasonMany"
    case (.episode, 0): key = "MediaItem_UnitEpisodeOne"
    case (.episode, 1): key = "MediaItem_UnitEpisodeFew"
    case (.episode, 2): key = "MediaItem_UnitEpisodeMany"
    case (.special, 0): key = "MediaItem_UnitSpecialOne"
    case (.special, 1): key = "MediaItem_UnitSpecialFew"
    case (.special, 2): key = "MediaItem_UnitSpecialMany"
    default: key = "MediaItem_UnitSeasonMany"
    }
    return key.localized
  }
}
