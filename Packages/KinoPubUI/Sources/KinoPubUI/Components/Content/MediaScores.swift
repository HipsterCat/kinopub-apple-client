//
//  MediaScores.swift
//
//  UI-facing catalogue scores. Not the API DTO (`MediaItem`) and not the
//  aggregate (`Rating`) — just the external sources the chrome draws.
//

import Foundation
import KinoPubBackend

/// Which rating sources exist. The identity a weight, a logo and a tile all key off.
public enum RatingSourceID: String, Hashable, Codable, Sendable, CaseIterable {
  case imdb
  case kinopoisk
  case tmdb
  /// Us — the community thumbs, expressed on the same 0…10 scale as the rest.
  case kinopub
}

/// How much each source counts toward the aggregate.
///
/// **Everything is on and equal today.** The type exists so that the settings pane
/// this is heading for — tick the sources you trust, weigh one above another — changes
/// a stored value rather than the shape of the calculation, and so that "all sources,
/// equally" is written down as a default someone chose instead of being the absence of
/// a decision. A weight of `0` excludes the source outright.
public struct RatingWeights: Hashable, Codable, Sendable {
  public var weights: [RatingSourceID: Double]

  public init(weights: [RatingSourceID: Double] = [:]) {
    self.weights = weights
  }

  public static let `default` = RatingWeights()

  /// Unlisted sources count fully — a source added later is included until someone
  /// turns it off, which is the safer default for a number the user reads as "the".
  public func weight(for id: RatingSourceID) -> Double {
    max(0, weights[id] ?? 1)
  }

  public func isEnabled(_ id: RatingSourceID) -> Bool { weight(for: id) > 0 }
}

/// One source's contribution: its score on a 0…10 scale and how many people voted.
public struct RatingInput: Hashable, Sendable {
  public let id: RatingSourceID
  /// 0…10. Nil when the source has voters but no published score yet.
  public let score: Double?
  public let votes: Int?

  public init(id: RatingSourceID, score: Double?, votes: Int?) {
    self.id = id
    self.score = score
    self.votes = votes
  }
}

/// The external numbers the UI is allowed to see. Map from `MediaItem` (or any other
/// payload) once at the boundary; views take this, not eight loose optionals.
///
/// **Not every caller can fill it.** kino.pub's own payload carries IMDb and Kinopoisk
/// only, so a poster badge aggregates those two; TMDB's score arrives with enrichment.
/// The numbers can differ by a tenth between a card and the page it opens — the alternative
/// is plumbing enrichment through every shelf, which buys a decimal point.
/// kino.pub's thumbs are on the detail page and nowhere in the average: a vote there
/// cannot be changed, so a misclick is not a rating.
public struct MediaScores: Hashable, Codable, Sendable {

  public let imdb: Double?
  public let imdbVotes: Int?
  public let kinopoisk: Double?
  public let kinopoiskVotes: Int?
  public let tmdb: Double?
  public let tmdbVotes: Int?
  /// kino.pub publishes no score, only thumbs.
  public let kinopubLikes: Int?
  public let kinopubDislikes: Int?

  public static let empty = MediaScores()

  public init(
    imdb: Double? = nil,
    imdbVotes: Int? = nil,
    kinopoisk: Double? = nil,
    kinopoiskVotes: Int? = nil,
    tmdb: Double? = nil,
    tmdbVotes: Int? = nil,
    kinopubLikes: Int? = nil,
    kinopubDislikes: Int? = nil
  ) {
    self.imdb = imdb
    self.imdbVotes = imdbVotes
    self.kinopoisk = kinopoisk
    self.kinopoiskVotes = kinopoiskVotes
    self.tmdb = tmdb
    self.tmdbVotes = tmdbVotes
    self.kinopubLikes = kinopubLikes
    self.kinopubDislikes = kinopubDislikes
  }

  public init(_ item: MediaItem) {
    self.init(
      imdb: item.imdbRating,
      imdbVotes: item.imdbVotes,
      kinopoisk: item.kinopoiskRating,
      kinopoiskVotes: item.kinopoiskVotes
    )
  }

  /// The same scores plus what only a detail page has: TMDB's audience score from
  /// enrichment, the community thumbs from the vote endpoint.
  public func adding(tmdb: Double? = nil,
                     tmdbVotes: Int? = nil,
                     kinopubLikes: Int? = nil,
                     kinopubDislikes: Int? = nil) -> MediaScores {
    MediaScores(
      imdb: imdb,
      imdbVotes: imdbVotes,
      kinopoisk: kinopoisk,
      kinopoiskVotes: kinopoiskVotes,
      tmdb: tmdb ?? self.tmdb,
      tmdbVotes: tmdbVotes ?? self.tmdbVotes,
      kinopubLikes: kinopubLikes ?? self.kinopubLikes,
      kinopubDislikes: kinopubDislikes ?? self.kinopubDislikes
    )
  }

  /// The API sends 0 for "not rated".
  public var imdbScore: Double? { Self.rated(imdb) }
  public var kinopoiskScore: Double? { Self.rated(kinopoisk) }
  public var tmdbScore: Double? { Self.rated(tmdb) }

  /// The share that liked it, on the 0…10 scale everything else uses.
  ///
  /// When one side is 0, it is 0% or 100%. Not an input to the aggregate.
  public var kinopubScore: Double? {
    guard let votes = kinopubVotes, votes > 0, (kinopubLikes != nil || kinopubDislikes != nil) else { return nil }
    let likes = max(0, kinopubLikes ?? 0)
    return Double(likes) / Double(votes) * 10
  }

  public var kinopubVotes: Int? {
    let total = max(0, kinopubLikes ?? 0) + max(0, kinopubDislikes ?? 0)
    return total > 0 ? total : nil
  }

  public var hasDisplayableScore: Bool {
    imdbScore != nil || kinopoiskScore != nil || tmdbScore != nil || kinopubScore != nil
  }

  /// What the aggregate weighs. kino.pub is absent on purpose.
  public var inputs: [RatingInput] {
    [
      RatingInput(id: .imdb, score: imdbScore, votes: imdbVotes),
      RatingInput(id: .kinopoisk, score: kinopoiskScore, votes: kinopoiskVotes),
      RatingInput(id: .tmdb, score: tmdbScore, votes: tmdbVotes)
    ]
  }

  /// Vote counts that are actually present (> 0).
  public var totalVotes: Int {
    inputs.compactMap(\.votes).filter { $0 > 0 }.reduce(0, +)
  }

  /// Our weighted aggregate, or nil when no enabled source rated the title.
  public var aggregate: Rating? { Rating(scores: self) }

  public func aggregate(weights: RatingWeights) -> Rating? {
    Rating(scores: self, weights: weights)
  }

  /// Keep one source for the card's rating-source preference.
  public func selecting(_ source: MediaCardRatingSource) -> MediaScores {
    switch source {
    case .combined:
      return self
    case .imdb:
      return MediaScores(imdb: imdb, imdbVotes: imdbVotes)
    case .kinopoisk:
      return MediaScores(kinopoisk: kinopoisk, kinopoiskVotes: kinopoiskVotes)
    }
  }

  private static func rated(_ value: Double?) -> Double? {
    (value ?? 0) > 0 ? value : nil
  }

  /// Formats raw voter turnout count as integer thousands without decimals (e.g. 12K, 450, 1M).
  public static func formatVotesWholeThousands(_ count: Int) -> String {
    if count >= 1_000_000 {
      return "\(count / 1_000_000)M"
    } else if count >= 1_000 {
      return "\(count / 1_000)K"
    } else {
      return "\(count)"
    }
  }
}

// MARK: - MediaScoreItem & Unified Scoring Logic

/// An individual rating ready for presentation in the banner, hero, or score blocks.
public struct MediaScoreItem: Identifiable, Hashable, Sendable {
  public let source: MediaScoreLogo.Source
  /// 0…10 numeric score, or nil if only voter turnout is known.
  public let score: Double?
  /// Formatted score string, e.g. "8.8", "75%", "100%" or "—".
  public let displayScore: String
  /// Voter turnout count.
  public let votes: Int?
  /// Compact votes string, e.g. "12K", "450", "1.2M".
  public let votesCompact: String?

  public var id: String { source.rawValue }
  public var hasKnownScore: Bool { score != nil }

  /// Five voters or fewer is a handful, not an audience. TMDB and kino.pub at that
  /// size keep the number and draw it in secondary ink. A source that has voters but
  /// no score yet — Kinopoisk's "?" — is the same.
  public var drawsFaint: Bool {
    if score == nil { return true }
    switch source {
    case .tmdb, .kinopub:
      return (votes ?? 0) <= Self.faintVoteCeiling
    case .imdb, .kinopoisk:
      return false
    }
  }

  public static let faintVoteCeiling = 5

  public init(
    source: MediaScoreLogo.Source,
    score: Double?,
    displayScore: String? = nil,
    votes: Int? = nil
  ) {
    self.source = source
    self.score = score
    self.votes = (votes ?? 0) > 0 ? votes : nil
    if let displayScore {
      self.displayScore = displayScore
    } else if let score {
      self.displayScore = source.formattedScore(score)
    } else {
      self.displayScore = "—"
    }

    if let v = self.votes, v > 0 {
      if v >= 1_000_000 {
        self.votesCompact = "\(v / 1_000_000)M"
      } else if v >= 1_000 {
        self.votesCompact = "\(v / 1_000)K"
      } else {
        self.votesCompact = "\(v)"
      }
    } else {
      self.votesCompact = nil
    }
  }

  /// Returns a copy with `displayScore` empty, avoiding duplicate score digits next to the aggregate badge.
  public func withoutScore() -> MediaScoreItem {
    MediaScoreItem(
      source: source,
      score: score,
      displayScore: "",
      votes: votes
    )
  }
}

public extension MediaScores {
  /// All candidate rating items from available sources.
  var allItems: [MediaScoreItem] {
    var list: [MediaScoreItem] = []

    if let s = imdbScore, s > 0 {
      list.append(MediaScoreItem(source: .imdb, score: s, votes: imdbVotes))
    } else if let v = imdbVotes, v > 0 {
      list.append(MediaScoreItem(source: .imdb, score: nil, displayScore: "—", votes: v))
    }

    if let s = kinopoiskScore, s > 0 {
      list.append(MediaScoreItem(source: .kinopoisk, score: s, votes: kinopoiskVotes))
    } else if let v = kinopoiskVotes, v > 0 {
      list.append(MediaScoreItem(source: .kinopoisk, score: nil, displayScore: "—", votes: v))
    }

    if let s = tmdbScore, s > 0 {
      list.append(MediaScoreItem(source: .tmdb, score: s, votes: tmdbVotes))
    } else if let v = tmdbVotes, v > 0 {
      list.append(MediaScoreItem(source: .tmdb, score: nil, displayScore: "—", votes: v))
    }

    if let s = kinopubScore {
      list.append(MediaScoreItem(source: .kinopub, score: s, votes: kinopubVotes))
    } else if let v = kinopubVotes, v > 0 {
      list.append(MediaScoreItem(source: .kinopub, score: nil, displayScore: "—", votes: v))
    }

    return list
  }

  /// Sorts rating items according to our rules:
  /// 1. KinoPub is always placed last.
  /// 2. Known scores precede unknown ("—" / "?") scores.
  /// 3. Higher voter turnout comes first.
  static func sortRatings(_ a: MediaScoreItem, _ b: MediaScoreItem) -> Bool {
    // 1. KinoPub always goes last
    if a.source == .kinopub && b.source != .kinopub { return false }
    if a.source != .kinopub && b.source == .kinopub { return true }

    // 2. Known score vs unknown score
    if a.hasKnownScore != b.hasKnownScore {
      return a.hasKnownScore
    }

    // 3. Voter count descending
    let aVotes = a.votes ?? 0
    let bVotes = b.votes ?? 0
    if aVotes != bVotes {
      return aVotes > bVotes
    }

    // Fallback stable order: kinopoisk, imdb, tmdb, kinopub
    return a.source.rawValue < b.source.rawValue
  }

  /// The title page's line under the synopsis. Same order as the score cards: the
  /// bigger audience first. kino.pub stays off it. A source with voters and no score
  /// prints "?".
  ///
  /// A published score stays. Three numbers are worth more than two, and 5 000 beside
  /// 600 000 is still a rating. The only thing left off is a "?" that two published
  /// scores already outvote by about a hundred to one — a few hundred votes beside
  /// half a million, not four beside seventy-eight, and not a silent Kinopoisk
  /// pushing a real percentage off the line.
  func detailLine(deduplicateAgainstAggregate: Bool = false) -> [MediaScoreItem] {
    let order: [MediaScoreLogo.Source] = [.imdb, .kinopoisk, .tmdb]
    var items: [MediaScoreItem] = order.compactMap { source in
      guard let item = allItems.first(where: { $0.source == source }) else { return nil }
      guard item.score == nil else { return item }
      return MediaScoreItem(source: item.source, score: nil, displayScore: "?", votes: item.votes)
    }
    items.sort { ($0.votes ?? 0) > ($1.votes ?? 0) }
    let published = items.filter(\.hasKnownScore)
    let peak = published.map { $0.votes ?? 0 }.max() ?? 0
    items = items.filter { item in
      guard !item.hasKnownScore else { return true }
      let votes = item.votes ?? 0
      let larger = published.filter { ($0.votes ?? 0) > votes }.count
      if larger >= 2, votes * 150 < peak { return false }
      return true
    }
    if deduplicateAgainstAggregate && items.filter(\.hasKnownScore).count == 1 {
      items = items.map { $0.hasKnownScore ? $0.withoutScore() : $0 }
    }
    return items
  }

  /// Ordered rating items for Hero row (shows all available ranked sources).
  var heroScores: [MediaScoreItem] {
    heroScores(deduplicateAgainstAggregate: false)
  }

  /// Ordered rating items for Hero row with optional deduplication against the aggregate badge.
  func heroScores(deduplicateAgainstAggregate: Bool = false) -> [MediaScoreItem] {
    var items = allItems.sorted(by: Self.sortRatings)
    if deduplicateAgainstAggregate && items.filter(\.hasKnownScore).count == 1 {
      items = items.map { item in
        item.hasKnownScore ? item.withoutScore() : item
      }
    }
    return items
  }

  /// Rating items filtered and capped for the compact banner:
  /// - Sorted by smart ranking
  /// - Drops low turnout (< 10 votes) when larger sources exist
  /// - If one source accounts for > 90% of total votes, collapses to that 1 source
  /// - If deduplicateAgainstAggregate is true and only 1 known source rated the item, omits the duplicate digit
  /// - Capped at `limit` (default 2)
  func bannerScores(
    limit: Int = 2,
    filterNoise: Bool = true,
    filterDominant: Bool = true,
    deduplicateAgainstAggregate: Bool = false
  ) -> [MediaScoreItem] {
    var items = allItems
      .filter { $0.hasKnownScore && $0.displayScore != "—" && !$0.displayScore.isEmpty && ($0.score ?? 0) > 0 }
      .sorted(by: Self.sortRatings)

    // Filter noise: if any source has >= 10 votes, drop sources with < 10 votes
    if filterNoise {
      let hasSignificant = items.contains { ($0.votes ?? 0) >= 10 }
      if hasSignificant {
        items.removeAll { ($0.votes ?? 0) < 10 }
      }
    }

    // Dominant source: if one source accounts for > 90% of total votes, keep only it
    if filterDominant && items.count > 1 {
      let total = items.compactMap(\.votes).reduce(0, +)
      if total > 0, let top = items.first, let topVotes = top.votes {
        if Double(topVotes) / Double(total) > 0.90 {
          items = [top]
        }
      }
    }

    if deduplicateAgainstAggregate && items.filter(\.hasKnownScore).count == 1 {
      items = items.map { item in
        item.hasKnownScore ? item.withoutScore() : item
      }
    }

    return Array(items.prefix(max(1, limit)))
  }
}

extension MediaScoreLogo.Source {
  /// What a person reads. TMDB's own site and kino.pub's thumbs are a percentage;
  /// the stored score stays 0…10 so it can be averaged with IMDb and Kinopoisk.
  public func formattedScore(_ score: Double) -> String {
    switch self {
    case .tmdb, .kinopub:
      return "\(Int((score * 10).rounded()))%"
    case .imdb, .kinopoisk:
      return String(format: "%.1f", score)
    }
  }
}
