//
//  TMDBEpisodeGroups.swift
//
//  When TMDB dumps a series into season=1, Production episode groups ARE the seasons
//  (Ice Wall, Apothecary). Remap group order → display season, 1-based index within
//  the group → episode number so kino.pub S1…Sn align and absolute eps (24→54) do not
//  leak under the wrong tab (Sasha / KP-23).
//

import Foundation

enum TMDBEpisodeGroupType {
  /// TMDB: Production.
  static let production = 6
}

enum TMDBEpisodeGroupsMapper {

  /// Prefer Production «Seasons»; else the densest Production group; else densest overall.
  static func preferredSummary(from results: [TMDBEpisodeGroupSummary]) -> TMDBEpisodeGroupSummary? {
    let production = results.filter { $0.type == TMDBEpisodeGroupType.production }
    let pool = production.isEmpty ? results : production
    guard !pool.isEmpty else { return nil }
    if let named = pool.first(where: { nameLooksLikeSeasons($0.name) }) {
      return named
    }
    return pool.max { lhs, rhs in
      (lhs.groupCount ?? 0, lhs.episodeCount ?? 0) < (rhs.groupCount ?? 0, rhs.episodeCount ?? 0)
    }
  }

  /// Flat TMDB: one regular season (or `number_of_seasons <= 1`) — groups may carry the rest.
  static func shouldApplyGroups(numberOfSeasons: Int?,
                                seasonSummaries: [SeasonSummary],
                                groupCount: Int) -> Bool {
    guard groupCount >= 2 else { return false }
    let regular = seasonSummaries.filter { $0.seasonNumber > 0 }
    if let numberOfSeasons, numberOfSeasons <= 1 { return true }
    if regular.count <= 1 { return true }
    return false
  }

  /// Remap group buckets into season summaries + per-season schedules.
  /// Skips Specials-only buckets. Season number = group.order when ≥ 1, else 1-based index.
  static func remap(
    groups: [TMDBEpisodeGroupBucket],
    stillURL: (String?) -> URL?
  ) -> (summaries: [SeasonSummary], schedule: [Int: [EpisodeSchedule]]) {
    let buckets = groups
      .filter { !isSpecialsBucket($0) }
      .filter { !($0.episodes ?? []).isEmpty }
      .sorted { ($0.order ?? Int.max) < ($1.order ?? Int.max) }

    var summaries: [SeasonSummary] = []
    var schedule: [Int: [EpisodeSchedule]] = [:]
    var used = Set<Int>()

    for (index, bucket) in buckets.enumerated() {
      var seasonNumber = bucket.order ?? (index + 1)
      if seasonNumber < 1 { seasonNumber = index + 1 }
      while used.contains(seasonNumber) { seasonNumber += 1 }
      used.insert(seasonNumber)

      let episodes = (bucket.episodes ?? []).enumerated().map { offset, ep in
        EpisodeSchedule(
          episodeNumber: offset + 1,
          seasonNumber: seasonNumber,
          name: nonEmpty(ep.name),
          overview: nonEmpty(ep.overview),
          airDate: parseDate(ep.airDate),
          runtime: ep.runtime,
          still: stillURL(ep.stillPath),
          voteAverage: (ep.voteAverage ?? 0) > 0 ? ep.voteAverage : nil,
          voteCount: (ep.voteCount ?? 0) > 0 ? ep.voteCount : nil,
          isSeasonFinale: ep.episodeType == "finale"
        )
      }
      schedule[seasonNumber] = episodes
      summaries.append(
        SeasonSummary(
          seasonNumber: seasonNumber,
          name: nonEmpty(bucket.name),
          overview: nil,
          episodeCount: episodes.count,
          airDate: episodes.compactMap(\.airDate).min(),
          poster: nil,
          voteAverage: nil
        )
      )
    }
    return (summaries, schedule)
  }

  private static func nameLooksLikeSeasons(_ name: String?) -> Bool {
    guard let name = name?.lowercased() else { return false }
    return name.contains("season") || name.contains("сезон")
  }

  private static func isSpecialsBucket(_ bucket: TMDBEpisodeGroupBucket) -> Bool {
    let name = bucket.name?.lowercased() ?? ""
    if name.contains("special") || name.contains("спец") { return true }
    if bucket.order == 0 { return true }
    return false
  }

  private static func nonEmpty(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  private static func parseDate(_ value: String?) -> Date? {
    guard let value, !value.isEmpty else { return nil }
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.date(from: value)
  }
}
