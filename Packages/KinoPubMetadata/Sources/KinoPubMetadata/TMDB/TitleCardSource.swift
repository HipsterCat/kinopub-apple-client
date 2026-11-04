import Foundation
import OSLog
import KinoPubLogging

/// `GET /v2/title/by/kinopub/{id}` — one card instead of the app's own TMDB calls.
///
/// The body is the page's title: billing, images, seasons, episodes. It does not
/// search TMDB. A 404 means the worker has no card yet. Not cached here: the
/// comparison on the detail page is measuring this call, and the worker already
/// keeps the answer for 60 seconds.
public final class TitleCardSource: MetadataSource, @unchecked Sendable {
  public let id: MetadataSourceID = .titleCard
  public var isConfigured: Bool { configuration.isConfigured }

  private let configuration: MetadataConfiguration
  private let client: MetadataHTTPClient

  public init(configuration: MetadataConfiguration, client: MetadataHTTPClient = MetadataHTTPClient()) {
    self.configuration = configuration
    self.client = client
  }

  public func titleMetadata(for identity: MediaIdentity) async throws -> TitleMetadata? {
    guard identity.kinopubId > 0 else { return nil }
    guard let url = makeURL(kinopubId: identity.kinopubId) else {
      return TitleMetadata()
    }
    let started = ContinuousClock().now
    do {
      let data = try await client.getData(url: url)
      let elapsed = MetadataTiming.milliseconds(since: started)
      let card = try client.decode(TitleCardDTO.self, from: data)
      var meta = Self.map(card, proxyBase: configuration.proxyBaseURL)
      let body = String(data: data.prefix(8_192), encoding: .utf8) ?? ""
      meta.debugLog = [SourceDebugEntry(
        source: .titleCard,
        endpoint: "v2/title",
        url: url.absoluteString,
        proxied: true,
        succeeded: true,
        responseBody: body,
        elapsedMilliseconds: elapsed
      )]
      return meta
    } catch MetadataError.httpStatus(404) {
      var meta = TitleMetadata()
      meta.attribution.insert(.titleCard)
      meta.debugLog = [SourceDebugEntry(
        source: .titleCard,
        endpoint: "v2/title",
        url: url.absoluteString,
        proxied: true,
        succeeded: false,
        responseBody: "404 — no card for kinopub \(identity.kinopubId)",
        elapsedMilliseconds: MetadataTiming.milliseconds(since: started)
      )]
      return meta
    } catch {
      Logger.metadata.error("Title card \(identity.kinopubId) failed: \(error.localizedDescription)")
      var meta = TitleMetadata()
      meta.debugLog = [SourceDebugEntry(
        source: .titleCard,
        endpoint: "v2/title",
        url: url.absoluteString,
        proxied: true,
        succeeded: false,
        responseBody: error.localizedDescription,
        elapsedMilliseconds: MetadataTiming.milliseconds(since: started)
      )]
      return meta
    }
  }

  private func makeURL(kinopubId: Int) -> URL? {
    guard let base = configuration.proxyBaseURL else { return nil }
    let root = base.absoluteString.hasSuffix("/")
      ? String(base.absoluteString.dropLast())
      : base.absoluteString
    return URL(string: "\(root)/v2/title/by/kinopub/\(kinopubId)")
  }

  static func map(_ card: TitleCardDTO, proxyBase: URL?) -> TitleMetadata {
    var meta = TitleMetadata()
    meta.attribution.insert(.titleCard)
    meta.language = "ru"
    meta.status = card.status
    meta.inProduction = card.status == "Returning Series"
    meta.tagline = nonEmpty(card.taglineRu)
    meta.overview = nonEmpty(card.synopsisRu)
    meta.tmdbId = tmdbNumericID(card.ids?.tmdb)
    meta.kinopoiskID = card.ids?.kinopoisk.flatMap(Int.init)
    if let rating = card.ratings?.tmdb, let value = rating.value?.value, value > 0 {
      meta.tmdbRating = value
      meta.tmdbVotes = (rating.votes ?? 0) > 0 ? rating.votes : nil
    }

    let images = card.images ?? []
    let logo = pick(images, kind: "logo", season: nil, languages: ["ru", "en", nil])
    meta.titleLogoLanguage = logo?.lang
    meta.artwork = Artwork(
      titleLogo: TMDBImageURL.proxied(logo?.url, proxyBase: proxyBase),
      poster: TMDBImageURL.proxied(
        pick(images, kind: "poster", season: nil, languages: ["ru", "en", nil])?.url,
        proxyBase: proxyBase
      ),
      backdrop: TMDBImageURL.proxied(
        pick(images, kind: "backdrop", season: nil, languages: [nil, "ru", "en"])?.url,
        proxyBase: proxyBase
      )
    )
    meta.stills = images.compactMap { image in
      guard image.kind == "still", image.personId == nil else { return nil }
      guard let url = TMDBImageURL.proxied(image.url, proxyBase: proxyBase) else { return nil }
      return StillImage(url: url)
    }

    meta.productionCompanies = (card.networks ?? []).compactMap { network in
      guard let name = nonEmpty(network.name) else { return nil }
      return ProductionCompany(
        name: name,
        logoURL: TMDBImageURL.proxied(network.logoUrl, proxyBase: proxyBase),
        originCountry: network.originCountry
      )
    }

    var cast: [CastMember] = []
    for section in ["star", "regular"] {
      for person in card.billing?[section] ?? [] {
        if let member = mapPerson(person, department: "Acting", order: cast.count, proxyBase: proxyBase) {
          cast.append(member)
        }
      }
    }
    meta.cast = cast

    var crew: [CastMember] = []
    for section in ["director", "writer"] {
      for person in card.billing?[section] ?? [] {
        let department = section == "director" ? "Directing" : "Writing"
        if let member = mapPerson(person, department: department, order: crew.count, proxyBase: proxyBase) {
          crew.append(member)
        }
      }
    }
    meta.crew = crew

    var summaries: [SeasonSummary] = []
    var schedule: [Int: [EpisodeSchedule]] = [:]
    var allEpisodes: [EpisodeSchedule] = []
    for season in card.seasons ?? [] {
      guard let number = season.number else { continue }
      let poster = season.poster
        ?? pick(images, kind: "poster", season: number, languages: ["ru", "en", nil])?.url
      summaries.append(SeasonSummary(
        seasonNumber: number,
        name: nonEmpty(season.name),
        episodeCount: season.episodeCount,
        airDate: TMDBSource.parseDate(season.airDate),
        poster: TMDBImageURL.proxied(poster, proxyBase: proxyBase)
      ))
      let episodes = (season.episodes ?? []).flatMap { episode in
        schedules(episode, season: number, proxyBase: proxyBase)
      }
      if !episodes.isEmpty {
        schedule[number] = episodes
        allEpisodes.append(contentsOf: episodes)
      }
    }
    meta.seasonSummaries = summaries
    meta.schedule = schedule
    let numbered = summaries.filter { $0.seasonNumber > 0 }
    meta.numberOfSeasons = numbered.isEmpty ? nil : numbered.count
    let counted = numbered.compactMap(\.episodeCount).reduce(0, +)
    meta.numberOfEpisodes = counted > 0 ? counted : nil
    let aired = summaries.compactMap(\.airDate)
    let ended = (card.seasons ?? []).compactMap { TMDBSource.parseDate($0.endDate) }
    meta.firstAirDate = aired.min()
    meta.lastAirDate = (aired + ended).max()

    let unique = Dictionary(
      allEpisodes.map { ("\($0.seasonNumber):\($0.episodeNumber)", $0) },
      uniquingKeysWith: { first, _ in first }
    ).values
    let dated = unique.filter { $0.airDate != nil }.sorted { lhs, rhs in
      let left = lhs.airDate ?? .distantPast
      let right = rhs.airDate ?? .distantPast
      if left != right { return left < right }
      if lhs.seasonNumber != rhs.seasonNumber { return lhs.seasonNumber < rhs.seasonNumber }
      return lhs.episodeNumber < rhs.episodeNumber
    }
    if let next = dated.first(where: \.isUpcoming) {
      meta.nextEpisode = EpisodeRef(seasonNumber: next.seasonNumber, episodeNumber: next.episodeNumber,
                                    name: next.name, airDate: next.airDate)
    }
    if let last = dated.last(where: { !$0.isUpcoming }) {
      meta.lastEpisode = EpisodeRef(seasonNumber: last.seasonNumber, episodeNumber: last.episodeNumber,
                                   name: last.name, airDate: last.airDate)
    }
    return meta
  }

  /// Russian and English titles are two rows of the same slot, so the episode grid
  /// can match either language the way the per-season TMDB fetches did.
  private static func schedules(_ episode: TitleCardEpisode, season: Int, proxyBase: URL?) -> [EpisodeSchedule] {
    guard let number = episode.number else { return [] }
    let air = TMDBSource.parseDate(episode.airDate)
    let still = TMDBImageURL.proxied(episode.still, proxyBase: proxyBase)
    let votes = (episode.tmdbVotes ?? 0) > 0 ? episode.tmdbVotes : nil
    let rating = (episode.tmdbValue?.value ?? 0) > 0 ? episode.tmdbValue?.value : nil
    func row(_ name: String?) -> EpisodeSchedule {
      EpisodeSchedule(
        episodeNumber: number,
        seasonNumber: season,
        name: nonEmpty(name),
        airDate: air,
        runtime: episode.runtimeMin,
        still: still,
        voteAverage: rating,
        voteCount: votes
      )
    }
    var rows = [row(episode.nameRu)]
    if let en = nonEmpty(episode.nameEn), en != nonEmpty(episode.nameRu) {
      rows.append(row(en))
    }
    return rows
  }

  private static func mapPerson(_ person: TitleCardPerson, department: String, order: Int,
                                proxyBase: URL?) -> CastMember? {
    let ru = nonEmpty(person.nameRu)
    let en = nonEmpty(person.nameEn)
    guard let name = ru ?? en else { return nil }
    return CastMember(
      name: name,
      localizedName: ru == nil ? nil : en,
      character: nonEmpty(person.character) ?? nonEmpty(person.job),
      photo: TMDBImageURL.proxied(person.profileUrl, proxyBase: proxyBase),
      department: department,
      tmdbPersonId: person.personId,
      episodeCount: person.episodeCount,
      order: order
    )
  }

  /// Same language first. A wider file wins inside that language; `tvoe`, then
  /// Kinopoisk, then TMDB. Season posters stay off the hero (`season != nil`).
  private static func pick(_ images: [TitleCardImage], kind: String, season: Int?,
                           languages: [String?]) -> TitleCardImage? {
    let pool = images.filter { image in
      image.kind == kind && image.personId == nil && image.episode == nil && image.season == season
    }
    let rank = ["tvoe": 0, "kinopoisk": 1, "tmdb": 2, "card": 3]
    for language in languages {
      let group = pool.filter { $0.lang == language }
      if let best = group.max(by: { lhs, rhs in
        let left = rank[lhs.source ?? ""] ?? 9
        let right = rank[rhs.source ?? ""] ?? 9
        if left != right { return left > right }
        return (lhs.width ?? 0) < (rhs.width ?? 0)
      }) {
        return best
      }
    }
    return nil
  }

  static func tmdbNumericID(_ raw: String?) -> Int? {
    guard let raw, !raw.isEmpty else { return nil }
    let tail = raw.split(separator: "/").last.map(String.init) ?? raw
    return Int(tail)
  }

  private static func nonEmpty(_ raw: String?) -> String? {
    guard let raw else { return nil }
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}

// MARK: - Wire

/// A JSON number that arrives as `9` or `8.356`. `JSONDecoder` will not coerce one into the other.
struct FlexibleDouble: Decodable {
  let value: Double

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let double = try? container.decode(Double.self) {
      value = double
      return
    }
    value = Double(try container.decode(Int.self))
  }
}

struct TitleCardDTO: Decodable, Sendable {
  var kinopubId: Int?
  var type: String?
  var title: TitleCardNames?
  var year: Int?
  var status: String?
  var taglineRu: String?
  var synopsisRu: String?
  var ids: TitleCardIDs?
  var ratings: TitleCardRatings?
  var billing: [String: [TitleCardPerson]]?
  var images: [TitleCardImage]?
  var networks: [TitleCardNetwork]?
  var seasons: [TitleCardSeason]?

  enum CodingKeys: String, CodingKey {
    case kinopubId = "kinopub_id"
    case type, title, year, status
    case taglineRu = "tagline_ru"
    case synopsisRu = "synopsis_ru"
    case ids, ratings, billing, images, networks, seasons
  }
}

struct TitleCardNames: Decodable, Sendable {
  var ru: String?
  var original: String?
}

struct TitleCardIDs: Decodable, Sendable {
  var imdb: String?
  var tmdb: String?
  var kinopoisk: String?
}

struct TitleCardRatings: Decodable, Sendable {
  var tmdb: TitleCardScore?
}

struct TitleCardScore: Decodable, Sendable {
  var value: FlexibleDouble?
  var votes: Int?
}

struct TitleCardPerson: Decodable, Sendable {
  var personId: Int?
  var nameRu: String?
  var nameEn: String?
  var character: String?
  var job: String?
  var episodeCount: Int?
  var profileUrl: String?

  enum CodingKeys: String, CodingKey {
    case personId = "person_id"
    case nameRu = "name_ru"
    case nameEn = "name_en"
    case character, job
    case episodeCount = "episode_count"
    case profileUrl = "profile_url"
  }
}

struct TitleCardImage: Decodable, Sendable {
  var kind: String?
  var lang: String?
  var url: String?
  var source: String?
  var width: Int?
  var personId: Int?
  var season: Int?
  var episode: Int?

  enum CodingKeys: String, CodingKey {
    case kind, lang, url, source, width
    case personId = "person_id"
    case season, episode
  }
}

struct TitleCardNetwork: Decodable, Sendable {
  var name: String?
  var logoUrl: String?
  var originCountry: String?

  enum CodingKeys: String, CodingKey {
    case name
    case logoUrl = "logo_url"
    case originCountry = "origin_country"
  }
}

struct TitleCardSeason: Decodable, Sendable {
  var number: Int?
  var name: String?
  var episodeCount: Int?
  var airDate: String?
  var endDate: String?
  var poster: String?
  var episodes: [TitleCardEpisode]?

  enum CodingKeys: String, CodingKey {
    case number, name, poster, episodes
    case episodeCount = "episode_count"
    case airDate = "air_date"
    case endDate = "end_date"
  }
}

struct TitleCardEpisode: Decodable, Sendable {
  var number: Int?
  var nameRu: String?
  var nameEn: String?
  var runtimeMin: Int?
  var airDate: String?
  var still: String?
  var tmdbValue: FlexibleDouble?
  var tmdbVotes: Int?

  enum CodingKeys: String, CodingKey {
    case number, still
    case nameRu = "name_ru"
    case nameEn = "name_en"
    case runtimeMin = "runtime_min"
    case airDate = "air_date"
    case tmdbValue = "tmdb_value"
    case tmdbVotes = "tmdb_votes"
  }
}
