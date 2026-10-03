import Foundation

/// One thing to watch, or one container of them, as **we** describe it — whichever
/// sources said what. A source never builds one of these directly: it builds a
/// `MediaFragment`, and `MediaAggregator` merges fragments into an entity, recording in
/// `provenance` where each field came from.
///
/// The field set follows what Apple's own catalogue carries for the same objects (title,
/// short and long description, genres with a primary one, release date, content rating,
/// artwork, season/episode numbering), plus what we hold beyond it (scores from every
/// source, countries). A field Apple has no slot for is still kept: it simply never
/// reaches an Apple surface.
///
/// **Two readings of one entity.** The stored fields are the *default* answer — each from
/// the source `MediaPrecedence` ranks first. `claims` is everything every source said,
/// kept whole: ask it (`claims(for:_:)`, `value(from:_:)`) when a surface wants a
/// particular source's fact, or every source's, rather than the default.
public struct MediaEntity: Hashable, Sendable, Codable {
  public var kind: MediaKind
  public var extraKind: ExtraKind?
  public var ids: [ExternalID]
  public var title: String?
  public var originalTitle: String?
  /// A version of the same work — "48 fps", "Director's Cut". kino.pub ships these as the
  /// videos of a multi-version film; they are editions of one movie, never episodes.
  public var edition: String?
  /// `.season`: its own number. `.episode`: the season it belongs to. Always the real
  /// season number, never a platform's re-numbered block.
  public var seasonNumber: Int?
  /// `.episode` only.
  public var episodeNumber: Int?
  /// `.show`: how many seasons it has that the source knows of. One, and it is season 1 →
  /// an episode's season goes without saying (`EpisodeText`).
  public var seasonCount: Int?
  public var synopsis: Synopsis
  /// Ordered by significance. **The first is the primary genre** — the one field Apple
  /// shows where there is room for one word ("Comedy" on a card for a show filed under
  /// Comedy and Sport). There is no second, separately stored "primary" to disagree with.
  public var genres: [Genre]
  /// Movie: premiere. Show: first air date. Season and episode: their own air date.
  public var release: ReleaseDate?
  /// Show and season: when the run ended.
  public var ended: ReleaseDate?
  /// Seconds.
  public var runtime: TimeInterval?
  /// The age rating ("16+", "PG-13") — **not** a score.
  public var contentRating: ContentRating?
  /// Scores, every source side by side, never averaged. Never inherited either: a
  /// show's 8.8 printed on one of its episodes would be a number nobody gave it.
  public var scores: [Score]
  public var artwork: ArtworkSet
  public var countries: [String]
  /// A concert's setlist, in order. Empty for everything else.
  public var setlist: [SetlistEntry]
  /// What a platform says about its copy or its catalogue rather than about the work —
  /// kino.pub's "Эксклюзив". Not genres, never the one word shown; kept for badges,
  /// filters and sections. Every source's are kept.
  public var labels: [MediaLabel]
  /// Which source each field came from. Filled by `MediaAggregator`; empty on a fragment.
  public var provenance: [MediaField: MediaSource]
  /// Every fragment this entity was merged from, as each source stated it. Filled by
  /// `MediaAggregator`; empty on a fragment.
  public var claims: [MediaFragment]

  public init(kind: MediaKind,
              extraKind: ExtraKind? = nil,
              ids: [ExternalID] = [],
              title: String? = nil,
              originalTitle: String? = nil,
              edition: String? = nil,
              seasonNumber: Int? = nil,
              episodeNumber: Int? = nil,
              seasonCount: Int? = nil,
              synopsis: Synopsis = Synopsis(),
              genres: [Genre] = [],
              release: ReleaseDate? = nil,
              ended: ReleaseDate? = nil,
              runtime: TimeInterval? = nil,
              contentRating: ContentRating? = nil,
              scores: [Score] = [],
              artwork: ArtworkSet = ArtworkSet(),
              countries: [String] = [],
              setlist: [SetlistEntry] = [],
              labels: [MediaLabel] = [],
              provenance: [MediaField: MediaSource] = [:],
              claims: [MediaFragment] = []) {
    self.kind = kind
    self.extraKind = extraKind
    self.ids = ids
    self.title = title.nonBlank
    self.originalTitle = originalTitle.nonBlank
    self.edition = edition.nonBlank
    self.seasonNumber = seasonNumber
    self.episodeNumber = episodeNumber
    self.seasonCount = seasonCount.flatMap { $0 > 0 ? $0 : nil }
    self.synopsis = synopsis
    self.genres = genres
    self.release = release
    self.ended = ended
    self.runtime = runtime.flatMap { $0 > 0 ? $0 : nil }
    self.contentRating = contentRating
    self.scores = scores
    self.artwork = artwork
    self.countries = countries
    self.setlist = setlist
    self.labels = labels
    self.provenance = provenance
    self.claims = claims
  }

  public var primaryGenre: Genre? { genres.first }

  public func id(_ namespace: ExternalID.Namespace) -> String? {
    ids.first { $0.namespace == namespace }?.value
  }

  // MARK: - Every source's facts

  /// What every source said about one field, best-ranked first — the default answer is
  /// the first. `read` takes the fact off one source's statement; nil means that source
  /// said nothing about it.
  ///
  ///     show.claims(for: .tagline) { $0.synopsis.tagline }
  ///     // [Claim(.kinopoisk, "ru", "Страх — это кандалы…"), Claim(.tmdb, "en", "Fear can hold you prisoner…")]
  public func claims<Value>(for field: MediaField,
                            precedence: MediaPrecedence = .standard,
                            _ read: (MediaEntity) -> Value?) -> [Claim<Value>] {
    claims.enumerated()
      .sorted { lhs, rhs in
        let left = precedence.rank(lhs.element.source, for: field)
        let right = precedence.rank(rhs.element.source, for: field)
        return left != right ? left < right : lhs.offset < rhs.offset
      }
      .compactMap { pair -> Claim<Value>? in
        let fragment = pair.element
        guard let value = read(fragment.entity) else { return nil }
        return Claim(source: fragment.source, language: fragment.language, value: value)
      }
  }

  /// One source's own answer, whatever won the default — Kinopoisk's short description,
  /// TMDB's English plot.
  public func value<Value>(from source: MediaSource, _ read: (MediaEntity) -> Value?) -> Value? {
    for fragment in claims where fragment.source == source {
      if let value = read(fragment.entity) { return value }
    }
    return nil
  }

  /// The sources that said anything at all about this entity.
  public var sources: [MediaSource] {
    var seen: [MediaSource] = []
    for fragment in claims where !seen.contains(fragment.source) { seen.append(fragment.source) }
    return seen
  }
}

/// One song of a concert's setlist. A song nobody could name keeps its place in the order
/// with no title — kino.pub writes those as «N/A».
public struct SetlistEntry: Hashable, Codable, Sendable {
  public var title: String?
  public var artists: String?
  /// The song's own audio, when the source gives one.
  public var audio: URL?

  public init(title: String?, artists: String? = nil, audio: URL? = nil) {
    let title = title.nonBlank
    self.title = title == "N/A" ? nil : title
    self.artists = artists.nonBlank
    self.audio = audio
  }
}

/// One source's statement of one fact.
public struct Claim<Value> {
  public let source: MediaSource
  public let language: String?
  public let value: Value

  public init(source: MediaSource, language: String? = nil, value: Value) {
    self.source = source
    self.language = language
    self.value = value
  }
}

extension Claim: Equatable where Value: Equatable {}
extension Claim: Hashable where Value: Hashable {}
extension Claim: Sendable where Value: Sendable {}

// MARK: - Values

/// A platform's statement about a title that is not a genre: "Эксклюзив" on kino.pub.
/// `sourceKey` is how that platform itself asks for it (kino.pub's `genre=128`), so a
/// section or a filter built on the label can query the source it came from.
public struct MediaLabel: Hashable, Sendable, Codable {
  public let id: String
  public let name: LocalizedName
  public let source: MediaSource
  public let sourceKey: String?

  public init(id: String, name: LocalizedName, source: MediaSource, sourceKey: String? = nil) {
    self.id = id
    self.name = name
    self.source = source
    self.sourceKey = sourceKey
  }
}

public struct ExternalID: Hashable, Sendable, Codable {
  public enum Namespace: String, Hashable, Sendable, Codable, CaseIterable {
    case kinopub, imdb, tmdb, kinopoisk, tvdb, apple
  }

  public let namespace: Namespace
  public let value: String

  public init(_ namespace: Namespace, _ value: String) {
    self.namespace = namespace
    self.value = value
  }
}

/// Apple's catalogue carries a short and a long description; the record adds a tagline.
public struct Synopsis: Hashable, Sendable, Codable {
  public var short: String?
  public var full: String?
  public var tagline: String?

  public init(short: String? = nil, full: String? = nil, tagline: String? = nil) {
    self.short = short.nonBlank
    self.full = full.nonBlank
    self.tagline = tagline.nonBlank
  }

  /// The description to show where there is room for one.
  public var best: String? { full.nonBlank ?? short.nonBlank }

  public var isEmpty: Bool { best == nil && tagline.nonBlank == nil }
}

/// A date with the precision the source actually had. kino.pub knows a year; TMDB knows
/// a day. Inventing a first of January would be a fact nobody gave us.
public enum ReleaseDate: Hashable, Sendable, Codable {
  case year(Int)
  case day(year: Int, month: Int, day: Int)

  public init?(year: Int) {
    guard year > 0 else { return nil }
    self = .year(year)
  }

  /// Reads the calendar day in UTC: the sources parse `yyyy-MM-dd` at UTC midnight
  /// (`TMDBSource.parseDate`), so any other time zone would move some dates a day back.
  public init(date: Date) {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
    let parts = calendar.dateComponents([.year, .month, .day], from: date)
    self = .day(year: parts.year ?? 0, month: parts.month ?? 1, day: parts.day ?? 1)
  }

  public var year: Int {
    switch self {
    case .year(let year), .day(let year, _, _): return year
    }
  }

  public var hasDay: Bool {
    if case .day = self { return true }
    return false
  }

  /// "2023" or "2023-05-05" — ISO 8601 at whatever precision we have.
  public var iso8601: String {
    switch self {
    case .year(let year):
      return Self.padded(year, 4)
    case .day(let year, let month, let day):
      return "\(Self.padded(year, 4))-\(Self.padded(month, 2))-\(Self.padded(day, 2))"
    }
  }

  private static func padded(_ number: Int, _ width: Int) -> String {
    let digits = String(number)
    return String(repeating: "0", count: max(0, width - digits.count)) + digits
  }
}

/// Whose audience gave a score. Not the same question as who *reported* it: kino.pub
/// reports IMDb's number, and that number is still IMDb's.
public enum ScoreProvider: String, Hashable, Sendable, Codable, CaseIterable {
  case imdb, kinopoisk, tmdb, kinopub, rottenTomatoes, metacritic, trakt
}

public struct Score: Hashable, Sendable, Codable {
  public let provider: ScoreProvider
  public let value: Double
  public let scale: Double
  public let votes: Int?

  /// Nil for a missing or zero score: zero means "nobody voted" in every source we read,
  /// not a title the audience scored 0.
  public init?(_ provider: ScoreProvider, value: Double?, scale: Double = 10, votes: Int? = nil) {
    guard let value, value > 0, scale > 0 else { return nil }
    self.provider = provider
    self.value = value
    self.scale = scale
    self.votes = votes.flatMap { $0 > 0 ? $0 : nil }
  }
}

/// The age rating, as the source prints it. `region` is the rating system's country
/// when the source says which one it used ("RU" → 16+, "US" → PG-13).
public struct ContentRating: Hashable, Sendable, Codable {
  public let value: String
  public let region: String?

  public init?(_ value: String?, region: String? = nil) {
    guard let value = value.nonBlank else { return nil }
    self.value = value
    self.region = region.nonBlank
  }
}

public struct ArtworkSet: Hashable, Sendable, Codable {
  /// Portrait, with lettering.
  public var poster: URL?
  /// A frame of this very thing — an episode's still, a trailer's thumbnail.
  public var still: URL?
  /// Landscape, without lettering.
  public var backdrop: URL?
  public var logo: URL?

  public init(poster: URL? = nil, still: URL? = nil, backdrop: URL? = nil, logo: URL? = nil) {
    self.poster = poster
    self.still = still
    self.backdrop = backdrop
    self.logo = logo
  }

  /// Sources hand us strings, and blank ones: kino.pub ships `""` for a missing poster.
  public static func url(_ string: String?) -> URL? {
    string.nonBlank.flatMap(URL.init(string:))
  }
}

extension Optional where Wrapped == String {
  var nonBlank: String? {
    guard let self else { return nil }
    let trimmed = self.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}
