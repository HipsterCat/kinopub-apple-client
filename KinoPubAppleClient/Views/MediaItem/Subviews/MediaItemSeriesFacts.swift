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
import KinoPubMedia

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

/// The one written badge the title page leads its facts with (`TitleStatusBadge`): what is
/// new about this title right now. The first rule that holds wins; nil draws nothing.
///
/// Sasha's list (2026-11-08): «Новый сезон», «Новые серии», «Новая серия через 5 дней»,
/// «Последний сезон», «Недавно на Кинопабе», «Новинка», «Премьера», «Все серии». Each is
/// read from what kino.pub and TMDB already sent the page — no request of its own.
enum TitleStatus: Equatable {
  case newEpisode(inDays: Int)
  case premiere
  case finalSeason
  case allEpisodes
  case newSeason
  case newEpisodes
  case newRelease
  case recentlyAdded

  /// - Parameter awaitedEpisodeAirDate: the next episode of the season kino.pub is on
  ///   (`MediaItemModel.awaitedEpisodeAirDate`).
  static func resolve(_ item: MediaItem, _ metadata: TitleMetadata,
                      awaitedEpisodeAirDate: Date?, now: Date = Date(),
                      calendar: Calendar = .current) -> TitleStatus? {
    func days(since date: Date?) -> Int? {
      guard let date else { return nil }
      return calendar.dateComponents([.day], from: calendar.startOfDay(for: date),
                                     to: calendar.startOfDay(for: now)).day
    }
    let addedDaysAgo = item.createdAt > 0
      ? days(since: Date(timeIntervalSince1970: TimeInterval(item.createdAt))) : nil
    let updatedDaysAgo = item.updatedAt > 0
      ? days(since: Date(timeIntervalSince1970: TimeInterval(item.updatedAt))) : nil

    if item.isSeries {
      if let ahead = days(since: awaitedEpisodeAirDate).map({ -$0 }), (0...Rules.awaitedDays).contains(ahead) {
        return .newEpisode(inDays: ahead)
      }
      if let premiered = days(since: metadata.firstAirDate), (0...Rules.premiereDays).contains(premiered) {
        return .premiere
      }
      let seasons = item.seasons?.count ?? 0
      if SeriesFacts.isFinished(item, metadata),
         let ended = days(since: metadata.lastAirDate), (0...Rules.endedDays).contains(ended) {
        return seasons > 1 ? .finalSeason : .allEpisodes
      }
      let lastSeasonStart = metadata.seasonSummaries
        .filter { $0.seasonNumber > 0 }
        .max { $0.seasonNumber < $1.seasonNumber }?.airDate
      if seasons > 1, let started = days(since: lastSeasonStart), (0...Rules.newSeasonDays).contains(started) {
        return .newSeason
      }
      if !SeriesFacts.isFinished(item, metadata),
         let updated = updatedDaysAgo, (0...Rules.newEpisodesDays).contains(updated) {
        return .newEpisodes
      }
      return nil
    }

    if let released = days(since: metadata.releaseDate) {
      if (0...Rules.premiereDays).contains(released) { return .premiere }
      if (0...Rules.newReleaseDays).contains(released) { return .newRelease }
    }
    if let added = addedDaysAgo, (0...Rules.recentlyAddedDays).contains(added) {
      return .recentlyAdded
    }
    return nil
  }

  var text: String {
    switch self {
    case .newEpisode(let days):
      let formatter = RelativeDateTimeFormatter()
      formatter.dateTimeStyle = .named
      formatter.unitsStyle = .full
      formatter.locale = Locale(identifier: MediaLanguage.current.rawValue)
      let when = formatter.localizedString(from: DateComponents(day: days))
      return String(format: "TitleStatus_NewEpisodeWhen".localized, when)
    case .premiere: return "TitleStatus_Premiere".localized
    case .finalSeason: return "TitleStatus_FinalSeason".localized
    case .allEpisodes: return "TitleStatus_AllEpisodes".localized
    case .newSeason: return "TitleStatus_NewSeason".localized
    case .newEpisodes: return "TitleStatus_NewEpisodes".localized
    case .newRelease: return "TitleStatus_NewRelease".localized
    case .recentlyAdded: return "TitleStatus_RecentlyAdded".localized
    }
  }

  /// How fresh "new" is, in days. One place, so the badge is tuned here.
  enum Rules {
    static let awaitedDays = 30
    static let premiereDays = 14
    static let endedDays = 60
    static let newSeasonDays = 21
    static let newEpisodesDays = 7
    static let newReleaseDays = 120
    static let recentlyAddedDays = 14
  }
}
