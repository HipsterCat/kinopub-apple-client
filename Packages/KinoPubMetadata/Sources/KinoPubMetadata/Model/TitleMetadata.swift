import Foundation
import KinoPubMedia

public struct Artwork: Sendable, Hashable {
  public var titleLogo: URL?
  public var poster: URL?
  public var backdrop: URL?

  public init(titleLogo: URL? = nil, poster: URL? = nil, backdrop: URL? = nil) {
    self.titleLogo = titleLogo
    self.poster = poster
    self.backdrop = backdrop
  }
}

/// A studio (movies) or distribution network/service (TV — HBO, Netflix...).
public struct ProductionCompany: Sendable, Hashable, Identifiable {
  public var id: String { name }
  public let name: String
  public let logoURL: URL?
  public let originCountry: String?

  public init(name: String, logoURL: URL? = nil, originCountry: String? = nil) {
    self.name = name
    self.logoURL = logoURL
    self.originCountry = originCountry
  }
}

public struct CastMember: Sendable, Hashable, Identifiable {
  public var id: String { "\(tmdbPersonId.map(String.init) ?? name):\(department ?? "")" }

  public let name: String
  public var localizedName: String?
  public var character: String?
  public var photo: URL?
  public var department: String?
  public var tmdbPersonId: Int?
  public var episodeCount: Int?
  public var order: Int?

  public init(
    name: String,
    localizedName: String? = nil,
    character: String? = nil,
    photo: URL? = nil,
    department: String? = nil,
    tmdbPersonId: Int? = nil,
    episodeCount: Int? = nil,
    order: Int? = nil
  ) {
    self.name = name
    self.localizedName = localizedName
    self.character = character
    self.photo = photo
    self.department = department
    self.tmdbPersonId = tmdbPersonId
    self.episodeCount = episodeCount
    self.order = order
  }
}

public struct EpisodeSchedule: Sendable, Hashable, Identifiable {
  public var id: Int { episodeNumber }

  public let episodeNumber: Int
  public let seasonNumber: Int
  public var name: String?
  public var overview: String?
  public var airDate: Date?
  public var runtime: Int?
  public var still: URL?
  /// TMDB's audience score for this one episode, and how many people it is from.
  public var voteAverage: Double?
  public var voteCount: Int?

  public init(
    episodeNumber: Int,
    seasonNumber: Int,
    name: String? = nil,
    overview: String? = nil,
    airDate: Date? = nil,
    runtime: Int? = nil,
    still: URL? = nil,
    voteAverage: Double? = nil,
    voteCount: Int? = nil
  ) {
    self.episodeNumber = episodeNumber
    self.seasonNumber = seasonNumber
    self.name = name
    self.overview = overview
    self.airDate = airDate
    self.runtime = runtime
    self.still = still
    self.voteAverage = voteAverage
    self.voteCount = voteCount
  }

  /// True when the episode has a known air date in the future (local calendar day).
  public var isUpcoming: Bool {
    guard let airDate else { return false }
    return Calendar.current.startOfDay(for: airDate) > Calendar.current.startOfDay(for: Date())
  }
}

public struct EpisodeRef: Sendable, Hashable {
  public let seasonNumber: Int
  public let episodeNumber: Int
  public var name: String?
  public var airDate: Date?

  public init(seasonNumber: Int, episodeNumber: Int, name: String? = nil, airDate: Date? = nil) {
    self.seasonNumber = seasonNumber
    self.episodeNumber = episodeNumber
    self.name = name
    self.airDate = airDate
  }
}

/// One season of a TV title as the source lists it (summary, not the full schedule).
/// Season 0 is specials — kept out of season counts, surfaced separately.
public struct SeasonSummary: Sendable, Hashable {
  public let seasonNumber: Int
  public var name: String?
  public var overview: String?
  public var episodeCount: Int?
  public var airDate: Date?
  public var poster: URL?
  public var voteAverage: Double?

  public init(seasonNumber: Int, name: String? = nil, overview: String? = nil,
              episodeCount: Int? = nil, airDate: Date? = nil, poster: URL? = nil,
              voteAverage: Double? = nil) {
    self.seasonNumber = seasonNumber
    self.name = name
    self.overview = overview
    self.episodeCount = episodeCount
    self.airDate = airDate
    self.poster = poster
    self.voteAverage = voteAverage
  }
}

public struct Award: Sendable, Hashable {
  public let name: String
  public let nominationName: String?
  public let year: Int?
  public let won: Bool

  public init(name: String, nominationName: String? = nil, year: Int? = nil, won: Bool = false) {
    self.name = name
    self.nominationName = nominationName
    self.year = year
    self.won = won
  }
}

public struct SkipSegments: Sendable, Hashable {
  public struct Segment: Sendable, Hashable {
    public let startMs: Int
    public let endMs: Int
    public init(startMs: Int, endMs: Int) {
      self.startMs = startMs
      self.endMs = endMs
    }
  }

  public var intro: Segment?
  public var recap: Segment?
  public var outro: Segment?

  public init(intro: Segment? = nil, recap: Segment? = nil, outro: Segment? = nil) {
    self.intro = intro
    self.recap = recap
    self.outro = outro
  }
}

/// A gallery image (stills, not the single hero poster/backdrop in `Artwork`).
public struct StillImage: Sendable, Hashable, Identifiable {
  public var id: String { url.absoluteString }
  public let url: URL
  public let previewURL: URL?

  public init(url: URL, previewURL: URL? = nil) {
    self.url = url
    self.previewURL = previewURL
  }
}

public struct Fact: Sendable, Hashable, Identifiable {
  public var id: String { text }
  public let text: String
  public let isSpoiler: Bool

  public init(text: String, isSpoiler: Bool = false) {
    self.text = text
    self.isSpoiler = isSpoiler
  }
}

/// A user review: Kinopoisk's (keyed unofficial API or the keyless kpapp.link proxy) or a
/// Trakt comment (`source == .trakt`).
public struct Review: Sendable, Hashable, Identifiable {
  public var id: String { "\(author)-\(title)-\(date ?? "")" }
  public let author: String
  /// Often empty — roughly half the reviews on a title carry no headline at all.
  public let title: String
  public let body: String
  public let sentiment: String?
  /// The source's timestamp verbatim (`2022-02-18T21:51:09`). Kept because the id is
  /// built from it, and because it is the only thing that survives a format we stop
  /// recognising.
  public let date: String?
  /// The same instant, parsed. Nil when the source's format is not one we read.
  public let postedAt: Date?
  /// "Was this review useful?" — Kinopoisk's `positiveRating` / `negativeRating`.
  /// Not the review's own sentiment: a negative review can be widely agreed with.
  public let helpfulVotes: Int
  public let unhelpfulVotes: Int
  /// The **review's** id at the source, not the title's. Nothing links to a single
  /// review yet — it is here because the payload carries it and the expanded card is
  /// where a permalink would go.
  public let sourceId: Int?
  /// Where it was written. Nil is Kinopoisk (either path), which predates the field.
  public let source: MetadataSourceID?
  /// ISO 639-1 of the text, when the source says (Trakt does; Kinopoisk is Russian).
  public let language: String?

  public init(
    author: String,
    title: String,
    body: String,
    sentiment: String? = nil,
    date: String? = nil,
    postedAt: Date? = nil,
    helpfulVotes: Int = 0,
    unhelpfulVotes: Int = 0,
    sourceId: Int? = nil,
    source: MetadataSourceID? = nil,
    language: String? = nil
  ) {
    self.author = author
    self.title = title
    self.body = body
    self.sentiment = sentiment
    self.date = date
    self.postedAt = postedAt
    self.helpfulVotes = helpfulVotes
    self.unhelpfulVotes = unhelpfulVotes
    self.sourceId = sourceId
    self.source = source
    self.language = language
  }

  public var isFromTrakt: Bool { source == .trakt }
}

/// A score another catalogue publishes, relayed by Trakt's `/ratings?extended=all`:
/// Trakt's own, Rotten Tomatoes (critics and audience), Metacritic, Letterboxd and
/// MyAnimeList. Kept on each source's own scale; `score10` is the 0…10 the page sorts by.
/// Not part of the aggregate `Rating`, which stays IMDb, Kinopoisk and TMDB.
public struct ExternalRating: Sendable, Hashable, Identifiable {
  public enum Kind: String, Sendable, Hashable, CaseIterable {
    /// 0…10, with votes.
    case trakt
    /// Tomatometer, 0…100 %.
    case rottenTomatoes
    /// Popcornmeter, 0…100 %.
    case rottenTomatoesAudience
    /// Metascore, 0…100.
    case metacritic
    /// 0…5, with votes. Films only.
    case letterboxd
    /// 0…10, with votes. Anime only.
    case myAnimeList
    /// 0…10, with votes, through our worker.
    case douban
  }

  public var id: Kind { kind }
  public let kind: Kind
  public let value: Double
  public let votes: Int?
  /// Rotten Tomatoes' verdict as it states it: `fresh`, `rotten`, `certified` for critics,
  /// `upright` / `spilled` for the audience. Nil elsewhere, or when Trakt did not say.
  public let state: String?
  /// The score's page at the source.
  public let url: URL?

  public init(kind: Kind, value: Double, votes: Int? = nil, state: String? = nil, url: URL? = nil) {
    self.kind = kind
    self.value = value
    self.votes = votes
    self.state = state
    self.url = url
  }

  /// The same number on 0…10.
  public var score10: Double {
    switch kind {
    case .rottenTomatoes, .rottenTomatoesAudience, .metacritic: value / 10
    case .letterboxd: value * 2
    case .trakt, .myAnimeList, .douban: value
    }
  }

  /// Fresh / upright. Rotten Tomatoes draws a different mark for each side; without a
  /// stated verdict its own threshold (60 %) decides.
  public var isPositive: Bool {
    switch state?.lowercased() {
    case "fresh", "certified", "certified_fresh", "upright": true
    case "rotten", "spilled": false
    default: value >= 60
    }
  }
}

/// The title's page on another site, as Wikidata lists it.
public struct ExternalLink: Sendable, Hashable, Identifiable {
  public enum Site: String, Sendable, Hashable, CaseIterable {
    case wikipedia, kinopoisk, douban, letterboxd, metacritic, rottenTomatoes, trakt, tvdb
    case myAnimeList, aniDB, aniList, kitsu, wikidata

    /// As the site writes its own name.
    public var name: String {
      switch self {
      case .wikipedia: "Wikipedia"
      case .kinopoisk: "Кинопоиск"
      case .douban: "Douban"
      case .letterboxd: "Letterboxd"
      case .metacritic: "Metacritic"
      case .rottenTomatoes: "Rotten Tomatoes"
      case .trakt: "Trakt"
      case .tvdb: "TheTVDB"
      case .myAnimeList: "MyAnimeList"
      case .aniDB: "AniDB"
      case .aniList: "AniList"
      case .kitsu: "Kitsu"
      case .wikidata: "Wikidata"
      }
    }
  }

  public var id: Site { site }
  public let site: Site
  public let url: URL

  public init(site: Site, url: URL) {
    self.site = site
    self.url = url
  }
}

/// How many awards and nominations a title has, as Wikidata counts its statements.
public struct AwardCounts: Sendable, Hashable {
  public let wins: Int
  public let nominations: Int

  public init(wins: Int, nominations: Int) {
    self.wins = wins
    self.nominations = nominations
  }
}

/// Douban's side of a title, numbers only: how its votes fall over five stars, what its
/// users did with it, and where it ranks in its genres ("better than 99% of crime films").
public struct DoubanStats: Sendable, Hashable {
  public struct Rank: Sendable, Hashable {
    /// English slug: `crime`, `drama`, `sci-fi`…
    public let genre: String
    /// 0…1.
    public let betterThan: Double

    public init(genre: String, betterThan: Double) {
      self.genre = genre
      self.betterThan = betterThan
    }
  }

  /// Shares of 1★…5★, summing to 1; empty when Douban did not say.
  public let shares: [Double]
  public let watched: Int?
  public let wantToWatch: Int?
  public let watching: Int?
  public let ranks: [Rank]
  /// Ranks read "of series" rather than "of films".
  public let isSeries: Bool

  public init(shares: [Double], watched: Int?, wantToWatch: Int?, watching: Int?, ranks: [Rank],
              isSeries: Bool = false) {
    self.shares = shares
    self.watched = watched
    self.wantToWatch = wantToWatch
    self.watching = watching
    self.ranks = ranks
    self.isSeries = isSeries
  }

  public var isEmpty: Bool {
    shares.isEmpty && (watched ?? 0) == 0 && (wantToWatch ?? 0) == 0 && ranks.isEmpty
  }
}

/// How many people did what with a title, as Trakt counts its own users (`/stats`).
public struct AudienceStats: Sendable, Hashable {
  public let watchers: Int
  public let plays: Int
  public let collectors: Int
  public let comments: Int
  public let lists: Int
  public let votes: Int
  public let favorited: Int?
  public let recommended: Int?

  public init(watchers: Int, plays: Int, collectors: Int, comments: Int, lists: Int, votes: Int,
              favorited: Int? = nil, recommended: Int? = nil) {
    self.watchers = watchers
    self.plays = plays
    self.collectors = collectors
    self.comments = comments
    self.lists = lists
    self.votes = votes
    self.favorited = favorited
    self.recommended = recommended
  }
}

/// What a title's reviews praise and fault, summed up by the source (Trakt's
/// `/sentiments`, written in English). Each point is a short phrase.
public struct ReviewInsights: Sendable, Hashable {
  public let good: [String]
  public let bad: [String]
  /// How many comments the summary was drawn from.
  public let commentCount: Int
  public let analyzedAt: Date?

  public init(good: [String], bad: [String], commentCount: Int, analyzedAt: Date? = nil) {
    self.good = good
    self.bad = bad
    self.commentCount = commentCount
    self.analyzedAt = analyzedAt
  }

  public var isEmpty: Bool { good.isEmpty && bad.isEmpty }
}

/// How many reviews a title has, as the source counts them.
///
/// `total` is **not** `reviews.count`: the proxy pages its reviews and we carry the
/// first page only, so the header can say "11" while the rail holds ten cards.
public struct ReviewsSummary: Sendable, Hashable {
  public let total: Int
  public let positive: Int
  public let negative: Int
  public let neutral: Int

  public init(total: Int, positive: Int, negative: Int, neutral: Int) {
    self.total = total
    self.positive = positive
    self.negative = negative
    self.neutral = neutral
  }

  public var isEmpty: Bool { total <= 0 && positive <= 0 && negative <= 0 && neutral <= 0 }

  public func adding(_ other: ReviewsSummary) -> ReviewsSummary {
    ReviewsSummary(total: total + other.total, positive: positive + other.positive,
                   negative: negative + other.negative, neutral: neutral + other.neutral)
  }
}

public struct TrailerRef: Sendable, Hashable {
  public let site: String
  public let key: String
  /// TMDB's video type: Trailer, Teaser, Clip, Featurette, Behind the Scenes, Bloopers,
  /// Opening Credits.
  public let type: String
  public let official: Bool
  public let language: String?
  /// The uploader's title of the video, in its own language.
  public let name: String?
  public let publishedAt: Date?

  public init(site: String, key: String, type: String, official: Bool, language: String?,
              name: String? = nil, publishedAt: Date? = nil) {
    self.site = site
    self.key = key
    self.type = type
    self.official = official
    self.language = language
    self.name = name
    self.publishedAt = publishedAt
  }

  public var isYouTube: Bool { site.caseInsensitiveCompare("YouTube") == .orderedSame }

  /// The video's page — on iOS a universal link into the YouTube app, on a Mac the browser.
  public var webURL: URL? {
    guard isYouTube else { return nil }
    return URL(string: "https://www.youtube.com/watch?v=\(key)")
  }

  /// The YouTube app's own scheme, for tvOS, where there is no browser to hand a web link to.
  public var appURL: URL? {
    guard isYouTube else { return nil }
    return URL(string: "youtube://watch/\(key)")
  }

  /// YouTube's still for the video. `hqdefault` (480×360) is the one every upload has;
  /// `maxresdefault` 404s for some (measured 2026-11-04: Inception's Russian trailer
  /// RlKr_lO45Nc), which left an empty tile. It is 4:3 with the 16:9 picture letterboxed
  /// inside, so a centre-crop fill onto a 16:9 tile shows exactly the picture.
  public var thumbnailURL: URL? {
    guard isYouTube else { return nil }
    return URL(string: "https://i.ytimg.com/vi/\(key)/hqdefault.jpg")
  }

  /// The title page's videos rail: YouTube only (that is where a press goes), in the app's
  /// language, English and the title's original language — no others (Sasha, 2026-11-04).
  /// Ordered by that language preference, then trailers before teasers before the rest,
  /// official before fan uploads, newest first. Duplicated keys are dropped.
  public static func forTitlePage(_ videos: [TrailerRef],
                                  appLanguage: String,
                                  originalLanguage: String?) -> [TrailerRef] {
    let languages = [appLanguage, "en", originalLanguage].compactMap { $0?.lowercased() }
    func languageRank(_ video: TrailerRef) -> Int? {
      guard let language = video.language?.lowercased() else { return nil }
      return languages.firstIndex(of: language)
    }
    var seen = Set<String>()
    let kept = videos.filter { video in
      video.isYouTube && languageRank(video) != nil && seen.insert(video.key).inserted
    }
    return kept.sorted { lhs, rhs in
      let l = (languageRank(lhs) ?? .max, typeRank(lhs.type), lhs.official ? 0 : 1)
      let r = (languageRank(rhs) ?? .max, typeRank(rhs.type), rhs.official ? 0 : 1)
      if l != r { return l < r }
      return (lhs.publishedAt ?? .distantPast) > (rhs.publishedAt ?? .distantPast)
    }
  }

  private static func typeRank(_ type: String) -> Int {
    let order = ["trailer", "teaser", "clip", "featurette", "behind the scenes",
                 "opening credits", "bloopers"]
    return order.firstIndex(of: type.lowercased()) ?? order.count
  }
}

/// Dev-facing record of one raw HTTP call a source made while building this
/// `TitleMetadata` — what URL, whether it went through our proxy, whether it
/// succeeded, and the raw response body. Powers the debug button on the item
/// page footer; not for end-user display.
public struct SourceDebugEntry: Sendable, Hashable, Identifiable {
  public var id: String { source.rawValue + endpoint + url }
  public let source: MetadataSourceID
  public let endpoint: String
  public let url: String
  public let proxied: Bool
  public let succeeded: Bool
  public let responseBody: String
  /// Wall time of this call, including a cache hit. Nil on entries recorded before timing.
  public let elapsedMilliseconds: Int?

  public init(
    source: MetadataSourceID,
    endpoint: String,
    url: String,
    proxied: Bool,
    succeeded: Bool,
    responseBody: String,
    elapsedMilliseconds: Int? = nil
  ) {
    self.source = source
    self.endpoint = endpoint
    self.url = url
    self.proxied = proxied
    self.succeeded = succeeded
    self.responseBody = responseBody
    self.elapsedMilliseconds = elapsedMilliseconds
  }
}

/// Merged overlay the UI reads. kino.pub remains the base; this only fills gaps.
public struct TitleMetadata: Sendable {
  public var cast: [CastMember] = []
  public var crew: [CastMember] = []
  public var artwork: Artwork = Artwork()
  public var schedule: [Int: [EpisodeSchedule]] = [:]
  public var awards: [Award] = []
  public var stills: [StillImage] = []
  public var facts: [Fact] = []
  public var reviews: [Review] = []
  /// The source's own counts for `reviews`, which are a first page, not the whole set.
  public var reviewsSummary: ReviewsSummary?
  public var nextEpisode: EpisodeRef?
  public var lastEpisode: EpisodeRef?
  public var status: String?
  public var inProduction: Bool?
  /// TV: every season incl. specials (season 0), with counts and air dates.
  public var seasonSummaries: [SeasonSummary] = []
  /// TV totals as the source reports them (specials not included).
  public var numberOfSeasons: Int?
  public var numberOfEpisodes: Int?
  /// TV air span; the movie world premiere sits in `releaseDate` instead.
  public var firstAirDate: Date?
  public var lastAirDate: Date?
  /// Movie-only: the world premiere date the source knows.
  public var releaseDate: Date?
  public var ageRating: String?
  /// The source's own description of the title. kino.pub's plot outranks it
  /// (`MediaPrecedence`); it is what a title kino.pub never described falls back to.
  public var overview: String?
  /// Already in our vocabulary — the source mapped its own ids (`GenreVocabulary.tmdb`).
  public var genres: [Genre] = []
  public var keywords: [String] = []
  public var trailers: [TrailerRef] = []
  /// ISO 639-1 of the original production, when the source says.
  public var originalLanguage: String?
  public var tagline: String?
  public var homepage: URL?
  /// Movie-only; both nil for series (TMDB doesn't report box office for TV).
  public var budget: Int?
  public var revenue: Int?
  /// US domestic box office in dollars, as OMDb reports it. Films only.
  public var boxOfficeUSD: Int?
  /// OMDb's one line about awards: "Won 4 Oscars. 157 wins & 220 nominations total".
  /// English, as OMDb writes it.
  public var awardsSummary: String?
  public var productionCompanies: [ProductionCompany] = []
  public var tmdbId: Int?
  /// Kinopoisk film id the title card carried, when the page still needs the proxy
  /// and the kino.pub item did not have one.
  public var kinopoiskID: Int?
  /// TMDB's own audience score (0…10) and its vote count. A third rating source
  /// beside kino.pub's IMDb and Kinopoisk numbers — **not** folded into the aggregate
  /// `Rating`, which stays the two sources it has always weighed.
  public var tmdbRating: Double?
  public var tmdbVotes: Int?
  /// Trakt, Rotten Tomatoes, Metacritic, Letterboxd, MyAnimeList — one per kind.
  public var externalRatings: [ExternalRating] = []
  /// The title's page on Trakt, when Trakt knows it.
  public var traktURL: URL?
  /// How Trakt's votes fall, score 1…10 → votes.
  public var traktDistribution: [Int: Int] = [:]
  public var audienceStats: AudienceStats?
  public var reviewInsights: ReviewInsights?
  public var doubanStats: DoubanStats?
  /// Wikidata: the item, the title's pages elsewhere, worldwide box office, award counts.
  public var wikidataID: String?
  public var externalLinks: [ExternalLink] = []
  public var boxOfficeWorldwideUSD: Int?
  public var awardCounts: AwardCounts?
  /// IMDb's score and vote count as Trakt last read them. Fresher than kino.pub's own
  /// copy when it has more votes (Sasha, 2026-11-09).
  public var relayedIMDbRating: Double?
  public var relayedIMDbVotes: Int?
  /// A scene after (or during) the credits, as Trakt's users mark it.
  public var hasAfterCreditsScene: Bool?
  public var hasDuringCreditsScene: Bool?
  public var attribution: Set<MetadataSourceID> = []
  /// The language this source's text was asked in — TMDB's `MetadataConfiguration.language`.
  /// Nil where the source did not say; on a merged overlay, the first source's.
  public var language: String?
  /// Language of the logo this overlay chose (`ru`, `en`), when the file itself said.
  /// The hero's second line reads it the way it reads the worker image route's stamp.
  public var titleLogoLanguage: String?
  /// What a source states about the title **in our model** — Kinopoisk's details.
  /// Concatenated by `merge`, never gap-filled: each stays its own source's statement, so
  /// nothing it said is lost to whichever source answered first.
  public var fragments: [MediaFragment] = []
  /// Each source's own answer, before the gap-filling merge, keyed by source. Filled by
  /// `MetadataService`, so the media model can read TMDB's facts as TMDB's.
  ///
  /// TODO(decision): the gap-filled fields above are what the detail page reads today
  /// (cast, artwork, awards…). Once those surfaces read the media model, the overlay can
  /// stop gap-filling and become `parts` alone.
  public var parts: [MetadataSourceID: TitleMetadata] = [:]
  /// Every raw HTTP call any source made for this title, across the whole merge —
  /// concatenated, not "fill gap" like the other fields. Dev/debug only.
  public var debugLog: [SourceDebugEntry] = []

  public init() {}

  public var titleLogoURL: URL? { artwork.titleLogo }
  public var backdropURL: URL? { artwork.backdrop }

  public mutating func merge(_ other: TitleMetadata) {
    if cast.isEmpty { cast = other.cast }
    else { cast = Self.mergeCast(base: cast, overlay: other.cast) }
    if crew.isEmpty { crew = other.crew }
    if artwork.titleLogo == nil { artwork.titleLogo = other.artwork.titleLogo }
    if artwork.poster == nil { artwork.poster = other.artwork.poster }
    if artwork.backdrop == nil { artwork.backdrop = other.artwork.backdrop }
    for (season, episodes) in other.schedule {
      if schedule[season] == nil { schedule[season] = episodes }
    }
    if awards.isEmpty { awards = other.awards }
    if stills.isEmpty { stills = other.stills }
    if facts.isEmpty { facts = other.facts }
    mergeReviews(other)
    if nextEpisode == nil { nextEpisode = other.nextEpisode }
    if lastEpisode == nil { lastEpisode = other.lastEpisode }
    if status == nil { status = other.status }
    if inProduction == nil { inProduction = other.inProduction }
    if seasonSummaries.isEmpty { seasonSummaries = other.seasonSummaries }
    if numberOfSeasons == nil { numberOfSeasons = other.numberOfSeasons }
    if numberOfEpisodes == nil { numberOfEpisodes = other.numberOfEpisodes }
    if firstAirDate == nil { firstAirDate = other.firstAirDate }
    if lastAirDate == nil { lastAirDate = other.lastAirDate }
    if releaseDate == nil { releaseDate = other.releaseDate }
    if ageRating == nil { ageRating = other.ageRating }
    if overview == nil { overview = other.overview }
    if genres.isEmpty { genres = other.genres }
    if keywords.isEmpty { keywords = other.keywords }
    if trailers.isEmpty { trailers = other.trailers }
    if originalLanguage == nil { originalLanguage = other.originalLanguage }
    if tagline == nil { tagline = other.tagline }
    if homepage == nil { homepage = other.homepage }
    if budget == nil { budget = other.budget }
    if revenue == nil { revenue = other.revenue }
    if boxOfficeUSD == nil { boxOfficeUSD = other.boxOfficeUSD }
    if awardsSummary == nil { awardsSummary = other.awardsSummary }
    if productionCompanies.isEmpty { productionCompanies = other.productionCompanies }
    if tmdbId == nil { tmdbId = other.tmdbId }
    if kinopoiskID == nil { kinopoiskID = other.kinopoiskID }
    if tmdbRating == nil { tmdbRating = other.tmdbRating }
    if tmdbVotes == nil { tmdbVotes = other.tmdbVotes }
    for rating in other.externalRatings where !externalRatings.contains(where: { $0.kind == rating.kind }) {
      externalRatings.append(rating)
    }
    if traktURL == nil { traktURL = other.traktURL }
    if traktDistribution.isEmpty { traktDistribution = other.traktDistribution }
    if audienceStats == nil { audienceStats = other.audienceStats }
    if reviewInsights == nil { reviewInsights = other.reviewInsights }
    if doubanStats == nil { doubanStats = other.doubanStats }
    if wikidataID == nil { wikidataID = other.wikidataID }
    for link in other.externalLinks where !externalLinks.contains(where: { $0.site == link.site }) {
      externalLinks.append(link)
    }
    if boxOfficeWorldwideUSD == nil { boxOfficeWorldwideUSD = other.boxOfficeWorldwideUSD }
    if awardCounts == nil { awardCounts = other.awardCounts }
    // Trakt and OMDb both relay IMDb; the copy with more votes is the fresher one.
    if let votes = other.relayedIMDbVotes, other.relayedIMDbRating != nil, votes > (relayedIMDbVotes ?? 0) {
      relayedIMDbRating = other.relayedIMDbRating
      relayedIMDbVotes = votes
    }
    if hasAfterCreditsScene == nil { hasAfterCreditsScene = other.hasAfterCreditsScene }
    if hasDuringCreditsScene == nil { hasDuringCreditsScene = other.hasDuringCreditsScene }
    attribution.formUnion(other.attribution)
    if language == nil { language = other.language }
    if titleLogoLanguage == nil { titleLogoLanguage = other.titleLogoLanguage }
    fragments.append(contentsOf: other.fragments)
    parts.merge(other.parts) { mine, _ in mine }
    debugLog.append(contentsOf: other.debugLog)
  }

  /// Kinopoisk's reviews gap-fill each other (keyed API and proxy carry the same ones);
  /// Trakt's are other people's words, so they follow Kinopoisk's instead of being
  /// dropped, and the counts take them in.
  private mutating func mergeReviews(_ other: TitleMetadata) {
    let incomingTrakt = other.reviews.filter(\.isFromTrakt)
    let incomingOther = other.reviews.filter { !$0.isFromTrakt }
    let hadTrakt = reviews.contains(where: \.isFromTrakt)
    let traktSummary = Self.summary(of: reviews.filter(\.isFromTrakt))
    if !reviews.contains(where: { !$0.isFromTrakt }), !incomingOther.isEmpty {
      reviews.insert(contentsOf: incomingOther, at: 0)
      // The summary so far was Trakt's alone; Kinopoisk's own counts replace it, and
      // the Trakt reviews already held are added back below.
      if let summary = other.reviewsSummary {
        reviewsSummary = hadTrakt ? summary.adding(traktSummary) : summary
      }
    } else if reviewsSummary == nil, !hadTrakt {
      reviewsSummary = other.reviewsSummary
    }
    if !hadTrakt, !incomingTrakt.isEmpty {
      reviews.append(contentsOf: incomingTrakt)
      if let summary = reviewsSummary {
        reviewsSummary = summary.adding(Self.summary(of: incomingTrakt))
      }
    }
  }

  private static func summary(of reviews: [Review]) -> ReviewsSummary {
    let tones = reviews.map { $0.sentiment?.uppercased() }
    let positive = tones.filter { $0 == "POSITIVE" }.count
    let negative = tones.filter { $0 == "NEGATIVE" }.count
    return ReviewsSummary(total: reviews.count, positive: positive, negative: negative,
                          neutral: reviews.count - positive - negative)
  }

  /// Prefer existing name order; fill photo/character from overlay by normalized name.
  public static func mergeCast(base: [CastMember], overlay: [CastMember]) -> [CastMember] {
    let byName = Dictionary(overlay.map { (Self.normalize($0.name), $0) },
                            uniquingKeysWith: { first, _ in first })
    return base.map { member in
      guard let hit = byName[Self.normalize(member.name)] else { return member }
      var merged = member
      if merged.character == nil || merged.character?.isEmpty == true {
        merged.character = hit.character
      }
      if merged.photo == nil { merged.photo = hit.photo }
      if merged.tmdbPersonId == nil { merged.tmdbPersonId = hit.tmdbPersonId }
      if merged.episodeCount == nil { merged.episodeCount = hit.episodeCount }
      return merged
    }
  }

  /// Enrich kino.pub name list with TMDB cast/crew data, keeping kino.pub order.
  public static func enrich(
    names: [String],
    roleDepartment: String?,
    from metadata: TitleMetadata
  ) -> [CastMember] {
    let pool = metadata.cast + metadata.crew
    let byName = Dictionary(pool.map { (Self.normalize($0.name), $0) },
                            uniquingKeysWith: { first, _ in first })
    return names.map { name in
      if let hit = byName[Self.normalize(name)] {
        var member = hit
        member = CastMember(
          name: name,
          localizedName: hit.localizedName,
          character: hit.character,
          photo: hit.photo,
          department: roleDepartment ?? hit.department,
          tmdbPersonId: hit.tmdbPersonId,
          episodeCount: hit.episodeCount,
          order: hit.order
        )
        return member
      }
      return CastMember(name: name, department: roleDepartment)
    }
  }

  public static func normalize(_ name: String) -> String {
    name.folding(options: .diacriticInsensitive, locale: .current)
      .lowercased()
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
