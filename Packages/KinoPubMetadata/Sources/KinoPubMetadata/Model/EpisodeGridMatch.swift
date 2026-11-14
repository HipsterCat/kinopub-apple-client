//
//  EpisodeGridMatch.swift
//

import Foundation

/// Which official episode a kino.pub episode is, when the season tables disagree.
///
/// kino.pub renumbers blocks, merges two or three seasons under one year, and
/// sometimes has an episode the official grid lacks (or lacks one it has). Matching
/// on the episode index alone then badges the wrong premiere and opens holes in the
/// wrong place. A match needs a title, a runtime, and a season that more than one
/// source can support. IMDb wins a tie: its episode list is often the one kino.pub
/// follows when TMDB and TVDB do not (Sasha, 2026-10-31).
public enum EpisodeGridMatch {

  public enum Source: Int, Sendable, Comparable, Hashable {
    case tvdb = 1
    case tmdb = 2
    case imdb = 3

    public static func < (lhs: Source, rhs: Source) -> Bool { lhs.rawValue < rhs.rawValue }
  }

  /// One kino.pub episode, already pulled off the season block.
  public struct KinoEpisode: Sendable, Hashable {
    public var blockID: Int
    public var blockNumber: Int
    /// The first number in the block's title. A year (`2012`) is not a season index.
    public var titledNumber: Int?
    public var number: Int
    public var title: String
    public var runtimeMinutes: Int?

    public init(blockID: Int, blockNumber: Int, titledNumber: Int?, number: Int,
                title: String, runtimeMinutes: Int?) {
      self.blockID = blockID
      self.blockNumber = blockNumber
      self.titledNumber = titledNumber
      self.number = number
      self.title = title
      self.runtimeMinutes = runtimeMinutes
    }
  }

  /// One episode from an official grid. Several sources for the same slot collapse
  /// into one value, keeping every title.
  public struct OfficialEpisode: Sendable, Hashable {
    public var source: Source
    public var season: Int
    public var number: Int
    public var titles: [String]
    public var runtimeMinutes: Int?
    public var airDate: Date?
    public var still: URL?
    public var isSeasonFinale: Bool

    public init(source: Source, season: Int, number: Int, titles: [String],
                runtimeMinutes: Int? = nil, airDate: Date? = nil, still: URL? = nil,
                isSeasonFinale: Bool = false) {
      self.source = source
      self.season = season
      self.number = number
      self.titles = titles
      self.runtimeMinutes = runtimeMinutes
      self.airDate = airDate
      self.still = still
      self.isSeasonFinale = isSeasonFinale
    }

    public init(source: Source, season: Int, number: Int, title: String,
                runtimeMinutes: Int? = nil, airDate: Date? = nil, still: URL? = nil,
                isSeasonFinale: Bool = false) {
      self.init(source: source, season: season, number: number, titles: [title],
                runtimeMinutes: runtimeMinutes, airDate: airDate, still: still,
                isSeasonFinale: isSeasonFinale)
    }
  }

  public struct Hit: Sendable, Hashable {
    public var kino: KinoEpisode
    public var official: OfficialEpisode

    public init(kino: KinoEpisode, official: OfficialEpisode) {
      self.kino = kino
      self.official = official
    }
  }

  public enum Row: Sendable, Hashable {
    /// A kino.pub episode, with the official episode it lined up with.
    case matched(Hit)
    /// An official episode this block's season is missing.
    case hole(OfficialEpisode)
    /// A kino.pub episode no official row claimed.
    case extra(KinoEpisode)
  }

  public struct Result: Sendable, Hashable {
    public var hits: [Hit]
    public var unmatchedKino: [KinoEpisode]
    public var official: [OfficialEpisode]
    /// Season hint used for each block, after dropping years and duplicated numbers.
    public var seasonHint: [Int: Int]

    public init(hits: [Hit], unmatchedKino: [KinoEpisode], official: [OfficialEpisode],
                seasonHint: [Int: Int]) {
      self.hits = hits
      self.unmatchedKino = unmatchedKino
      self.official = official
      self.seasonHint = seasonHint
    }

    public func hit(blockID: Int, number: Int) -> Hit? {
      hits.first { $0.kino.blockID == blockID && $0.kino.number == number }
    }

    /// The number the season chip and the play button share.
    /// Years in the title are not display seasons (a merged run such as 17262 keeps
    /// the kino.pub block index via the caller). One official season across the block's
    /// matches replaces a duplicated or renumbered title — unless that official number
    /// itself looks like a year.
    public func displaySeason(blockID: Int, titledNumber: Int?) -> Int? {
      let titled = titledNumber.flatMap { EpisodeGridMatch.isYear($0) ? nil : $0 }
      let seasons = Set(
        hits.filter { $0.kino.blockID == blockID }
          .map(\.official.season)
          .filter { !EpisodeGridMatch.isYear($0) }
      )
      if seasons.count == 1 { return seasons.first }
      return titled
    }

    /// Rail order for one kino.pub block: matched episodes, the holes that belong
    /// with them, and the extras kino.pub has on top.
    public func rows(for blockID: Int) -> [Row] {
      let blockHits = hits.filter { $0.kino.blockID == blockID }
      let extras = unmatchedKino.filter { $0.blockID == blockID }
        .sorted { $0.number < $1.number }
      let seasons = Set(blockHits.map(\.official.season))
      guard !seasons.isEmpty else {
        return extras.map { .extra($0) }
      }

      if seasons.count == 1, let season = seasons.first {
        return singleSeasonRows(season: season, hits: blockHits, extras: extras)
      }
      return mergedRows(seasons: seasons, hits: blockHits, extras: extras)
    }

    /// The first missing episode's air date, in rail order. Nil when this block has
    /// no hole with a date.
    public func firstHoleAirDate(blockID: Int) -> Date? {
      for row in rows(for: blockID) {
        if case .hole(let episode) = row, let airDate = episode.airDate { return airDate }
      }
      return nil
    }

    private func singleSeasonRows(season: Int, hits: [Hit], extras: [KinoEpisode]) -> [Row] {
      let inSeason = official.filter { $0.season == season }.sorted { $0.number < $1.number }
      var used = Set<Int>()
      var rows: [Row] = []
      for episode in inSeason {
        if let hit = hits.first(where: { $0.official.number == episode.number }) {
          rows.append(.matched(hit))
          used.insert(hit.kino.number)
        } else if !Self.alreadyMatched(episode, hits: self.hits) {
          rows.append(.hole(episode))
        }
      }
      for extra in extras where !used.contains(extra.number) {
        rows.append(.extra(extra))
      }
      // A 1:1 season reads in episode order, extras included where their number sits.
      return rows.sorted { lhs, rhs in
        Self.orderKey(lhs) < Self.orderKey(rhs)
      }
    }

    private func mergedRows(seasons: Set<Int>, hits: [Hit], extras: [KinoEpisode]) -> [Row] {
      var rows: [Row] = []
      for season in seasons.sorted() {
        let seasonHits = hits.filter { $0.official.season == season }
        guard let lo = seasonHits.map(\.official.number).min(),
              let hi = seasonHits.map(\.official.number).max() else { continue }
        let span = official
          .filter { $0.season == season && $0.number >= lo && $0.number <= hi }
          .sorted { $0.number < $1.number }
        for episode in span {
          if let hit = seasonHits.first(where: { $0.official.number == episode.number }) {
            rows.append(.matched(hit))
          } else if !Self.alreadyMatched(episode, hits: self.hits) {
            rows.append(.hole(episode))
          }
        }
      }
      rows.append(contentsOf: extras.map { .extra($0) })
      return rows
    }

    private static func alreadyMatched(_ episode: OfficialEpisode, hits: [Hit]) -> Bool {
      hits.contains { hit in
        hit.official.season == episode.season && hit.official.number == episode.number
      }
    }

    private static func orderKey(_ row: Row) -> Int {
      switch row {
      case .matched(let hit): return hit.official.number
      case .hole(let episode): return episode.number
      case .extra(let kino): return kino.number
      }
    }
  }

  /// A calendar year written as a season title, not a season index.
  public static func isYear(_ number: Int) -> Bool {
    (1900...2100).contains(number)
  }

  public static func align(kino: [KinoEpisode], official raw: [OfficialEpisode]) -> Result {
    let official = collapse(raw)
    let hints = seasonHints(kino: kino, official: official)
    // Normalise every title once. Scoring every pair used to fold and split both
    // strings again: a long show hung the title page for seconds (2026-11-04).
    var vocabulary: [Substring: Int] = [:]
    func prepare(_ raw: String) -> PreparedTitle? { PreparedTitle(raw, vocabulary: &vocabulary) }
    let kinoTitles = kino.map { prepare($0.title) }
    let officialTitles = official.map { $0.titles.compactMap(prepare) }

    var candidates: [(score: Int, kino: Int, official: Int)] = []
    for (kinoIndex, episode) in kino.enumerated() {
      let title = kinoTitles[kinoIndex]
      let hint = hints[episode.blockID]
      for (officialIndex, candidate) in official.enumerated() {
        let titleValue = title.map { titleScore($0, officialTitles[officialIndex]) } ?? 0
        guard let score = score(episode, candidate, title: titleValue, hint: hint) else { continue }
        candidates.append((score, kinoIndex, officialIndex))
      }
    }
    candidates.sort { lhs, rhs in
      if lhs.score != rhs.score { return lhs.score > rhs.score }
      if lhs.official != rhs.official { return lhs.official < rhs.official }
      return lhs.kino < rhs.kino
    }
    var usedKino = Set<Int>()
    var usedOfficial = Set<Int>()
    var matchedKino = Set<Int>()
    var hits: [Hit] = []
    for candidate in candidates {
      // A kino.pub episode whose best slot is already taken stays an extra: it is not
      // slid onto its next-best number. It used to drop out of the rail altogether.
      guard usedKino.insert(candidate.kino).inserted else { continue }
      guard usedOfficial.insert(candidate.official).inserted else { continue }
      matchedKino.insert(candidate.kino)
      hits.append(Hit(kino: kino[candidate.kino], official: official[candidate.official]))
    }
    let unmatched = kino.enumerated().compactMap { index, episode in
      matchedKino.contains(index) ? nil : episode
    }
    return Result(hits: hits, unmatchedKino: unmatched, official: official, seasonHint: hints)
  }

  /// A title already normalised, with its words as ids into one vocabulary.
  struct PreparedTitle {
    var text: String
    var length: Int
    var words: Set<Int>

    /// Nil for a title under two characters once normalised: it identifies nothing.
    init?(_ raw: String, vocabulary: inout [Substring: Int]) {
      let text = EpisodeGridMatch.normalize(raw)
      guard text.count >= 2 else { return nil }
      var words = Set<Int>()
      for word in text.split(separator: " ") {
        if let id = vocabulary[word] {
          words.insert(id)
        } else {
          let id = vocabulary.count
          vocabulary[word] = id
          words.insert(id)
        }
      }
      self.text = text
      self.length = text.count
      self.words = words
    }
  }

  // MARK: - Scoring

  /// Same season and number, and a runtime that does not contradict, are one slot
  /// told twice (Russian and English, or TMDB and IMDb). A runtime that disagrees
  /// by more than a few minutes stays two candidates.
  static func collapse(_ episodes: [OfficialEpisode]) -> [OfficialEpisode] {
    var groups: [OfficialEpisode] = []
    var bySlot: [Int: [Int]] = [:]
    let ordered = episodes.sorted { $0.source > $1.source }
    for episode in ordered {
      let slot = episode.season &* 100_000 &+ episode.number
      if let index = bySlot[slot]?.first(where: { sameSlot(groups[$0], episode) }) {
        var existing = groups[index]
        for title in episode.titles where !existing.titles.contains(title) {
          existing.titles.append(title)
        }
        if existing.runtimeMinutes == nil { existing.runtimeMinutes = episode.runtimeMinutes }
        if existing.airDate == nil { existing.airDate = episode.airDate }
        if existing.still == nil { existing.still = episode.still }
        if episode.isSeasonFinale { existing.isSeasonFinale = true }
        if episode.source > existing.source { existing.source = episode.source }
        groups[index] = existing
      } else {
        bySlot[slot, default: []].append(groups.count)
        groups.append(episode)
      }
    }
    return groups
  }

  private static func sameSlot(_ lhs: OfficialEpisode, _ rhs: OfficialEpisode) -> Bool {
    guard lhs.season == rhs.season, lhs.number == rhs.number else { return false }
    switch (lhs.runtimeMinutes, rhs.runtimeMinutes) {
    case let (left?, right?) where abs(left - right) > 5:
      return false
    default:
      return true
    }
  }

  /// A duplicated title number is not a season (Drag Race UK chips `2` twice).
  /// A year is not one either. Otherwise the unique number, or the block's own
  /// number when that season exists and nobody else claimed it. When a titled
  /// number is missing from the official set, also try the other way: an official
  /// season that uniquely fits this block's episode numbers can live "inside" a
  /// renumbered or year-titled kino block.
  static func seasonHints(kino: [KinoEpisode], official: [OfficialEpisode]) -> [Int: Int] {
    let officialSeasons = Set(official.map(\.season))
    var titled: [Int: Int] = [:]
    var blocks: [Int: KinoEpisode] = [:]
    var blockEpisodes: [Int: [KinoEpisode]] = [:]
    for episode in kino {
      blocks[episode.blockID] = episode
      blockEpisodes[episode.blockID, default: []].append(episode)
      guard let number = episode.titledNumber, !isYear(number) else { continue }
      titled[episode.blockID] = number
    }
    // Count blocks, not episodes.
    var blockCount: [Int: Int] = [:]
    for number in titled.values {
      blockCount[number, default: 0] += 1
    }
    var hints: [Int: Int] = [:]
    var claimed = Set<Int>()
    for (blockID, number) in titled where blockCount[number] == 1 && officialSeasons.contains(number) {
      hints[blockID] = number
      claimed.insert(number)
    }
    for (blockID, episode) in blocks where hints[blockID] == nil {
      guard episode.titledNumber.map(isYear) != true else { continue }
      guard titled[blockID] == nil else { continue }
      let number = episode.blockNumber
      guard officialSeasons.contains(number), !claimed.contains(number) else { continue }
      hints[blockID] = number
      claimed.insert(number)
    }
    // Reverse: titled/year blocks with no forward hint — pick an unclaimed official
    // season whose episode-number span uniquely covers this block's numbers.
    for (blockID, episodes) in blockEpisodes where hints[blockID] == nil {
      let numbers = Set(episodes.map(\.number))
      guard !numbers.isEmpty else { continue }
      var candidates: [Int] = []
      for season in officialSeasons.subtracting(claimed) {
        let officialNumbers = Set(official.filter { $0.season == season }.map(\.number))
        guard !officialNumbers.isDisjoint(with: numbers) else { continue }
        // The block's episode numbers sit inside this official season (or the season
        // sits inside the block — merged years). Either direction is a hint.
        if numbers.isSubset(of: officialNumbers) || officialNumbers.isSubset(of: numbers) {
          candidates.append(season)
        }
      }
      guard candidates.count == 1, let season = candidates.first else { continue }
      hints[blockID] = season
      claimed.insert(season)
    }
    return hints
  }

  /// Nil when the pair is only an index. A future air date never enters the score.
  static func score(_ kino: KinoEpisode, _ official: OfficialEpisode, hint: Int?) -> Int? {
    score(kino, official, title: titleScore(kino.title, official.titles), hint: hint)
  }

  static func score(_ kino: KinoEpisode, _ official: OfficialEpisode, title: Int, hint: Int?) -> Int? {
    let runtime = runtimeScore(kino.runtimeMinutes, official.runtimeMinutes)
    let hinted = hint == official.season
    let sameNumber = hinted && kino.number == official.number
    let identified = title >= 85
      || (title >= 50 && runtime >= 40)
      || (sameNumber && (runtime >= 25 || kino.runtimeMinutes == nil || official.runtimeMinutes == nil))
    guard identified else { return nil }
    var total = title * 10 + runtime
    if hinted { total += 30 }
    if sameNumber { total += 15 }
    total += official.source.rawValue
    return total
  }

  static func titleScore(_ kino: String, _ titles: [String]) -> Int {
    var vocabulary: [Substring: Int] = [:]
    func prepare(_ raw: String) -> PreparedTitle? { PreparedTitle(raw, vocabulary: &vocabulary) }
    guard let left = prepare(kino) else { return 0 }
    return titleScore(left, titles.compactMap(prepare))
  }

  /// Exact match 100, one inside the other (8+ characters each) 85, else the share
  /// of words the two have in common.
  static func titleScore(_ left: PreparedTitle, _ titles: [PreparedTitle]) -> Int {
    var best = 0
    for right in titles {
      if left.text == right.text {
        return 100
      }
      if left.length >= 8, right.length >= 8,
         left.text.contains(right.text) || right.text.contains(left.text) {
        best = max(best, 85)
      }
      // Counted in place: `intersection` allocates a set per pair.
      let (small, large) = left.words.count <= right.words.count
        ? (left.words, right.words) : (right.words, left.words)
      var shared = 0
      for word in small where large.contains(word) { shared += 1 }
      guard shared > 0 else { continue }
      let union = left.words.count + right.words.count - shared
      best = max(best, shared * 100 / union)
    }
    return best
  }

  static func runtimeScore(_ kino: Int?, _ official: Int?) -> Int {
    guard let kino, let official else { return 0 }
    let delta = abs(kino - official)
    // ±1 minute rounding never rejects a hit; treat it as exact.
    if delta <= 1 { return 40 }
    if delta <= 2 { return 40 }
    if delta <= 5 { return 25 }
    return 0
  }

  static func normalize(_ raw: String) -> String {
    let folded = raw.folding(options: [.diacriticInsensitive, .caseInsensitive],
                             locale: Locale(identifier: "en"))
    let scalars = folded.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? $0 : " " }
    return String(String.UnicodeScalarView(scalars))
      .split(whereSeparator: \.isWhitespace)
      .joined(separator: " ")
  }
}
