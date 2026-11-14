import Foundation
import KinoPubMedia

/// The viewer's own TMDB key, read fresh on every request (Settings can change it while
/// the app runs). Nil means "go through the worker proxy".
public protocol TMDBDirectAccessProviding: Sendable {
  func directAPIKey() -> String?
}

/// TMDB implementation of `MetadataSource`. Talks to the Cloudflare Worker proxy, which
/// holds KinoPub's key — or, while the viewer has their own key switched on, to
/// api.themoviedb.org directly with it. The worker mirrors TMDB's `/3/…` paths, so only
/// the host and the credential change.
public final class TMDBSource: MetadataSource, @unchecked Sendable {
  public let id: MetadataSourceID = .tmdb

  public var isConfigured: Bool { configuration.isConfigured || directKey != nil }

  public static let directBaseURL = URL(string: "https://api.themoviedb.org")!

  private let configuration: MetadataConfiguration
  private let directAccess: TMDBDirectAccessProviding?
  private let client: MetadataHTTPClient
  private let cache: MetadataCache

  private static let idTTL: TimeInterval = 60 * 60 * 24 * 365 * 50 // ~forever
  private static let detailsTTL: TimeInterval = 60 * 60 * 24 * 30
  private static let seasonTTL: TimeInterval = 60 * 60 * 12

  public init(
    configuration: MetadataConfiguration,
    client: MetadataHTTPClient = MetadataHTTPClient(),
    cache: MetadataCache = MetadataCache(),
    directAccess: TMDBDirectAccessProviding? = nil
  ) {
    self.configuration = configuration
    self.directAccess = directAccess
    self.client = client
    self.cache = cache
  }

  // MARK: - MetadataSource

  public func titleMetadata(for identity: MediaIdentity) async throws -> TitleMetadata? {
    guard isConfigured else { throw MetadataError.notConfigured }
    let (resolved, findDebug) = await resolveID(for: identity)
    guard let resolved else {
      var empty = TitleMetadata()
      empty.debugLog = [findDebug]
      return empty
    }
    let (details, detailsDebug) = await fetchDetails(id: resolved.tmdbId, type: resolved.type)
    guard let details else {
      var empty = TitleMetadata()
      empty.debugLog = [findDebug, detailsDebug]
      return empty
    }
    var meta = mapDetails(details, type: resolved.type, tmdbId: resolved.tmdbId)
    meta.debugLog = [findDebug, detailsDebug]
    // The details carry the videos in the app's language and English. A title made in a
    // third language gets its own videos in one more call — Korean teasers are often the
    // only ones a Korean series has.
    if let original = details.originalLanguage?.lowercased(), !original.isEmpty,
       !videoLanguages.contains(original) {
      let (extra, videosDebug) = await fetchVideos(id: resolved.tmdbId, type: resolved.type,
                                                   language: original)
      meta.trailers += extra.compactMap(Self.trailer(from:))
      meta.debugLog.append(videosDebug)
    }
    return meta
  }

  public func artwork(for identity: MediaIdentity) async throws -> Artwork? {
    try await titleMetadata(for: identity)?.artwork
  }

  public func cast(for identity: MediaIdentity) async throws -> [CastMember] {
    try await titleMetadata(for: identity)?.cast ?? []
  }

  public func nextEpisode(for identity: MediaIdentity) async throws -> EpisodeRef? {
    try await titleMetadata(for: identity)?.nextEpisode
  }

  public func schedule(for identity: MediaIdentity, season: Int) async throws -> [EpisodeSchedule] {
    try await schedule(for: identity, season: season, language: nil)
  }

  /// `language` nil uses the configured one (`ru-RU`). An explicit tag is a second
  /// grid — English titles, cached apart from the first — so a kino.pub episode
  /// named in either language can still match.
  public func schedule(for identity: MediaIdentity, season: Int,
                       language: String?) async throws -> [EpisodeSchedule] {
    guard isConfigured else { throw MetadataError.notConfigured }
    let (resolved, _) = await resolveID(for: identity)
    guard let resolved, resolved.type == .tv else {
      return []
    }
    return try await fetchSeason(tmdbId: resolved.tmdbId, season: season, language: language)
  }

  public func personMetadata(id: Int) async throws -> PersonMetadata? {
    guard isConfigured else { throw MetadataError.notConfigured }
    let details = try await fetchPerson(id: id)
    return mapPerson(details)
  }

  // MARK: - Resolve

  private struct Resolved: Sendable {
    let tmdbId: Int
    let type: TMDBMediaType
  }

  private func resolveID(for identity: MediaIdentity) async -> (Resolved?, SourceDebugEntry) {
    guard let imdb = identity.imdb, !imdb.isEmpty else {
      return (nil, SourceDebugEntry(source: .tmdb, endpoint: "find", url: "(no imdb id on this title)",
                                    proxied: isConfigured, succeeded: false, responseBody: "Skipped — no IMDb id from kino.pub."))
    }
    let key = "tmdb/find/\(imdb)"
    let findPath = "/3/find/\(imdb)"

    let entry = await cache.deduped(key: key, ttl: Self.idTTL) { [self] in
      do {
        let url = try makeURL(path: findPath, query: [
          URLQueryItem(name: "external_source", value: "imdb_id"),
          URLQueryItem(name: "language", value: configuration.language),
        ])
        let data = try await fetch(url)
        let response = try client.decode(TMDBFindResponse.self, from: data)
        guard let match = response.match(preferSeries: identity.isSeries) else {
          return MetadataCache.Entry(payload: Data(), isNegative: true)
        }
        let payload = TMDBResolvedID(tmdbId: match.id, type: match.type.rawValue)
        let encoded = try await cache.encode(payload)
        return MetadataCache.Entry(payload: encoded, isNegative: false)
      } catch MetadataError.httpStatus(404) {
        return MetadataCache.Entry(payload: Data(), isNegative: true)
      } catch {
        // Transient — don't cache.
        return nil
      }
    }

    let debugURL = (try? makeURL(path: findPath, query: [])).map(\.absoluteString) ?? findPath
    guard let entry else {
      return (nil, SourceDebugEntry(source: .tmdb, endpoint: "find", url: debugURL, proxied: isConfigured,
                                    succeeded: false, responseBody: "No response — not configured or network error."))
    }
    guard !entry.isNegative else {
      return (nil, SourceDebugEntry(source: .tmdb, endpoint: "find", url: debugURL, proxied: isConfigured,
                                    succeeded: false, responseBody: "No match for this IMDb id."))
    }
    // Only the resolved id is cached (the find response can list many candidates,
    // most irrelevant) — that's also the most useful single fact for debugging:
    // did we even match the right title.
    guard let resolved = try? await cache.decode(TMDBResolvedID.self, from: entry.payload),
          let type = TMDBMediaType(rawValue: resolved.type) else {
      return (nil, SourceDebugEntry(source: .tmdb, endpoint: "find", url: debugURL, proxied: isConfigured,
                                    succeeded: false, responseBody: "Resolved id cache entry failed to decode."))
    }
    let debugBody = "Resolved via /find to tmdbId=\(resolved.tmdbId), type=\(resolved.type) " +
      "(only the resolved id is cached, not the full /find response)."
    let debug = SourceDebugEntry(source: .tmdb, endpoint: "find", url: debugURL, proxied: isConfigured,
                                 succeeded: true, responseBody: debugBody)
    return (Resolved(tmdbId: resolved.tmdbId, type: type), debug)
  }

  // MARK: - Details

  private func fetchDetails(id: Int, type: TMDBMediaType) async -> (TMDBTitleDetails?, SourceDebugEntry) {
    // `videos-` in the key: entries from before the videos were asked in more than one
    // language would otherwise serve the Russian ones alone for a month.
    let key = "tmdb/details/videos-\(videoLanguages.joined(separator: "-"))/\(type.rawValue)/\(id)"
    let path = "/3/\(type.rawValue)/\(id)"
    let entry = await cache.deduped(key: key, ttl: Self.detailsTTL) { [self] in
      do {
        let append: String
        switch type {
        case .movie:
          append = "credits,images,videos,release_dates,keywords,external_ids"
        case .tv:
          append = "aggregate_credits,images,videos,content_ratings,keywords,external_ids"
        }
        let url = try makeURL(path: path, query: [
          URLQueryItem(name: "language", value: configuration.language),
          URLQueryItem(name: "append_to_response", value: append),
          URLQueryItem(name: "include_image_language", value: "ru,en,null"),
          // Without it TMDB lists only the videos in `language`.
          URLQueryItem(name: "include_video_language", value: videoLanguages.joined(separator: ",")),
        ])
        let data = try await fetch(url)
        // Validate before caching.
        _ = try client.decode(TMDBTitleDetails.self, from: data)
        return MetadataCache.Entry(payload: data)
      } catch {
        return nil
      }
    }
    let debugURL = (try? makeURL(path: path, query: [])).map(\.absoluteString) ?? path
    guard let entry else {
      return (nil, SourceDebugEntry(source: .tmdb, endpoint: "details", url: debugURL, proxied: isConfigured,
                                    succeeded: false, responseBody: "No response — not configured or network error."))
    }
    let debugBody = String(data: entry.payload, encoding: .utf8) ?? "<\(entry.payload.count) non-UTF8 bytes>"
    let debug = SourceDebugEntry(source: .tmdb, endpoint: "details", url: debugURL, proxied: isConfigured,
                                 succeeded: !entry.isNegative, responseBody: debugBody)
    guard !entry.isNegative else { return (nil, debug) }
    return (try? client.decode(TMDBTitleDetails.self, from: entry.payload), debug)
  }

  /// The app's language and English: what every title's videos are asked in.
  private var videoLanguages: [String] {
    let app = configuration.language.split(separator: "-").first.map { String($0).lowercased() } ?? "ru"
    return app == "en" ? ["en"] : [app, "en"]
  }

  /// One language's videos of a title (`/videos`), for the original language the details
  /// were not asked in.
  private func fetchVideos(id: Int, type: TMDBMediaType, language: String) async -> ([TMDBVideo], SourceDebugEntry) {
    let key = "tmdb/videos/\(type.rawValue)/\(id)/\(language)"
    let path = "/3/\(type.rawValue)/\(id)/videos"
    let query = [URLQueryItem(name: "language", value: language),
                 URLQueryItem(name: "include_video_language", value: language)]
    let entry = await cache.deduped(key: key, ttl: Self.detailsTTL) { [self] in
      do {
        let data = try await fetch(try makeURL(path: path, query: query))
        _ = try client.decode(TMDBVideos.self, from: data)
        return MetadataCache.Entry(payload: data)
      } catch {
        return nil
      }
    }
    let debugURL = (try? makeURL(path: path, query: query)).map(\.absoluteString) ?? path
    guard let entry, !entry.isNegative,
          let videos = try? client.decode(TMDBVideos.self, from: entry.payload) else {
      return ([], SourceDebugEntry(source: .tmdb, endpoint: "videos", url: debugURL, proxied: isConfigured,
                                   succeeded: false, responseBody: "No response — not configured or network error."))
    }
    let body = String(data: entry.payload, encoding: .utf8) ?? ""
    return (videos.results ?? [], SourceDebugEntry(source: .tmdb, endpoint: "videos", url: debugURL,
                                                   proxied: isConfigured, succeeded: true, responseBody: body))
  }

  private static func trailer(from video: TMDBVideo) -> TrailerRef? {
    guard let key = video.key, let site = video.site, let type = video.type else { return nil }
    return TrailerRef(site: site, key: key, type: type, official: video.official ?? false,
                      language: video.iso6391, name: video.name,
                      publishedAt: video.publishedAt.flatMap(Self.parseTimestamp))
  }

  private static func parseTimestamp(_ raw: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: raw) { return date }
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: raw)
  }

  /// Every poster TMDB has for one season, the app's language first, then English, then
  /// textless, the most-voted first within each (`/3/tv/{id}/season/{n}/images`). For
  /// looking through, not for choosing what the rail shows.
  public func seasonPosters(for identity: MediaIdentity, season: Int) async -> [URL] {
    guard isConfigured else { return [] }
    let (resolved, _) = await resolveID(for: identity)
    guard let resolved, resolved.type == .tv else { return [] }
    let tmdbId = resolved.tmdbId
    let language = String(configuration.language.prefix(2))
    let key = "tmdb/season-images/\(tmdbId)/\(season)"
    let entry = await cache.deduped(key: key, ttl: Self.seasonTTL) { [self] in
      do {
        let url = try makeURL(path: "/3/tv/\(tmdbId)/season/\(season)/images", query: [
          URLQueryItem(name: "include_image_language", value: "\(language),en,null"),
        ])
        let data = try await fetch(url)
        _ = try client.decode(TMDBImages.self, from: data)
        return MetadataCache.Entry(payload: data)
      } catch {
        return nil
      }
    }
    guard let entry, let images = try? client.decode(TMDBImages.self, from: entry.payload) else { return [] }
    let order: [String?] = [language, "en", nil]
    func rank(_ entry: TMDBImageEntry) -> Int {
      order.firstIndex { $0 == (entry.iso6391?.isEmpty == false ? entry.iso6391 : nil) } ?? order.count
    }
    return images.posters
      .filter { !($0.filePath ?? "").isEmpty }
      .sorted { lhs, rhs in
        let (l, r) = (rank(lhs), rank(rhs))
        return l != r ? l < r : (lhs.voteAverage ?? 0) > (rhs.voteAverage ?? 0)
      }
      .compactMap { imageURL(path: $0.filePath, size: .posterW780) }
  }

  private func fetchSeason(tmdbId: Int, season: Int, language: String?) async throws -> [EpisodeSchedule] {
    let lang = language ?? configuration.language
    // The unscoped key is the configured language, so a cache filled before the
    // second language existed still answers the primary fetch.
    let key = language == nil
      ? "tmdb/season/\(tmdbId)/\(season)"
      : "tmdb/season/\(tmdbId)/\(season)/\(lang)"
    let entry = await cache.deduped(key: key, ttl: Self.seasonTTL) { [self] in
      do {
        let url = try makeURL(path: "/3/tv/\(tmdbId)/season/\(season)", query: [
          URLQueryItem(name: "language", value: lang),
        ])
        let data = try await fetch(url)
        _ = try client.decode(TMDBSeasonDetails.self, from: data)
        return MetadataCache.Entry(payload: data)
      } catch {
        return nil
      }
    }
    guard let entry else { return [] }
    let details = try client.decode(TMDBSeasonDetails.self, from: entry.payload)
    let seasonNumber = details.seasonNumber ?? season
    return (details.episodes ?? []).compactMap { ep in
      guard let number = ep.episodeNumber else { return nil }
      return EpisodeSchedule(
        episodeNumber: number,
        seasonNumber: seasonNumber,
        name: ep.name,
        overview: ep.overview,
        airDate: Self.parseDate(ep.airDate),
        runtime: ep.runtime,
        still: imageURL(path: ep.stillPath, size: .stillW300),
        voteAverage: ep.voteAverage,
        voteCount: ep.voteCount,
        isSeasonFinale: ep.episodeType == "finale"
      )
    }
  }

  private func fetchPerson(id: Int) async throws -> TMDBPersonDetails {
    let key = "tmdb/person/\(id)"
    let entry = await cache.deduped(key: key, ttl: Self.detailsTTL) { [self] in
      do {
        let url = try makeURL(path: "/3/person/\(id)", query: [
          URLQueryItem(name: "language", value: configuration.language),
        ])
        let data = try await fetch(url)
        _ = try client.decode(TMDBPersonDetails.self, from: data)
        return MetadataCache.Entry(payload: data)
      } catch MetadataError.httpStatus(404) {
        return MetadataCache.Entry(payload: Data(), isNegative: true)
      } catch {
        return nil
      }
    }
    guard let entry, !entry.isNegative else { throw MetadataError.notFound }
    return try client.decode(TMDBPersonDetails.self, from: entry.payload)
  }

  // MARK: - Mapping

  private func mapPerson(_ details: TMDBPersonDetails) -> PersonMetadata {
    PersonMetadata(
      biography: details.biography.flatMap { $0.isEmpty ? nil : $0 },
      birthday: Self.parseDate(details.birthday),
      placeOfBirth: details.placeOfBirth.flatMap { $0.isEmpty ? nil : $0 },
      photo: imageURL(path: details.profilePath, size: .profileW342),
      knownForDepartment: details.knownForDepartment,
      attribution: [.tmdb]
    )
  }

  private func mapDetails(_ details: TMDBTitleDetails, type: TMDBMediaType, tmdbId: Int) -> TitleMetadata {
    var meta = TitleMetadata()
    meta.attribution.insert(.tmdb)
    // TMDB answers in the language it was asked; a missing translation comes back empty,
    // not in English, so whatever text there is is in this language.
    meta.language = configuration.language
    meta.tmdbId = tmdbId
    meta.status = details.status
    meta.inProduction = details.inProduction
    meta.seriesType = details.type
    meta.keywords = details.keywords?.all.compactMap(\.name) ?? []
    meta.tagline = details.tagline?.isEmpty == false ? details.tagline : nil
    meta.overview = details.overview?.isEmpty == false ? details.overview : nil
    var genres: [Genre] = []
    for named in details.genres ?? [] {
      guard let id = named.id else { continue }
      for genre in GenreVocabulary.tmdb(id: id, name: named.name) where !genres.contains(genre) {
        genres.append(genre)
      }
    }
    meta.genres = genres
    meta.homepage = details.homepage.flatMap { $0.isEmpty ? nil : URL(string: $0) }
    meta.budget = (details.budget ?? 0) > 0 ? details.budget : nil
    meta.revenue = (details.revenue ?? 0) > 0 ? details.revenue : nil
    // Zero means "nobody voted" here as it does everywhere else in this app, not a
    // title the audience scored 0.0.
    meta.tmdbRating = (details.voteAverage ?? 0) > 0 ? details.voteAverage : nil
    meta.tmdbVotes = (details.voteCount ?? 0) > 0 ? details.voteCount : nil

    // TV shows report their distribution service (HBO, Netflix...) as `networks`,
    // not `production_companies` — that's who made it, not who's streaming it,
    // and "which service is this on" is the more useful signal here.
    let companies = (type == .tv ? details.networks : details.productionCompanies) ?? []
    meta.productionCompanies = companies.compactMap { company in
      guard let name = company.name, !name.isEmpty else { return nil }
      return ProductionCompany(
        name: name,
        logoURL: imageURL(path: company.logoPath, size: .logoW500),
        originCountry: company.originCountry
      )
    }

    let credits = type == .tv ? (details.aggregateCredits ?? details.credits) : details.credits
    meta.cast = (credits?.cast ?? []).compactMap(mapCast)
    meta.crew = (credits?.crew ?? []).compactMap(mapCrew)

    if let images = details.images {
      meta.artwork = Artwork(
        titleLogo: imageURL(
          path: images.bestLogoPath(preferring: configuration.imageLanguages),
          size: .logoW500
        ),
        poster: imageURL(path: images.bestPosterPath(), size: .posterW780),
        backdrop: imageURL(path: images.bestBackdropPath(), size: .backdropOriginal)
      )
    }

    meta.trailers = (details.videos?.results ?? []).compactMap(Self.trailer(from:))
    meta.originalLanguage = details.originalLanguage

    meta.ageRating = Self.pickAgeRating(
      releaseDates: details.releaseDates,
      contentRatings: details.contentRatings
    )

    if let next = details.nextEpisodeToAir,
       let season = next.seasonNumber,
       let episode = next.episodeNumber {
      meta.nextEpisode = EpisodeRef(
        seasonNumber: season,
        episodeNumber: episode,
        name: next.name,
        airDate: Self.parseDate(next.airDate)
      )
    }
    if let last = details.lastEpisodeToAir,
       let season = last.seasonNumber,
       let episode = last.episodeNumber {
      meta.lastEpisode = EpisodeRef(
        seasonNumber: season,
        episodeNumber: episode,
        name: last.name,
        airDate: Self.parseDate(last.airDate)
      )
    }

    meta.seasonSummaries = (details.seasons ?? []).compactMap { ref in
      guard let number = ref.seasonNumber else { return nil }
      return SeasonSummary(
        seasonNumber: number,
        name: ref.name,
        overview: ref.overview?.isEmpty == false ? ref.overview : nil,
        episodeCount: ref.episodeCount,
        airDate: Self.parseDate(ref.airDate),
        poster: imageURL(path: ref.posterPath, size: .posterW780),
        voteAverage: ref.voteAverage
      )
    }
    meta.numberOfSeasons = details.numberOfSeasons
    meta.numberOfEpisodes = details.numberOfEpisodes
    meta.firstAirDate = Self.parseDate(details.firstAirDate)
    meta.lastAirDate = Self.parseDate(details.lastAirDate)
    meta.releaseDate = Self.parseDate(details.releaseDate)

    return meta
  }

  private func mapCast(_ credit: TMDBCredit) -> CastMember? {
    guard let name = credit.name, !name.isEmpty else { return nil }
    let episodeCount = credit.episodeCount
      ?? credit.roles?.compactMap(\.episodeCount).max()
    return CastMember(
      name: name,
      character: credit.primaryCharacter,
      photo: imageURL(path: credit.profilePath, size: .profileW185),
      department: credit.knownDepartmentOrActing,
      tmdbPersonId: credit.id,
      episodeCount: episodeCount,
      order: credit.order
    )
  }

  private func mapCrew(_ credit: TMDBCredit) -> CastMember? {
    guard let name = credit.name, !name.isEmpty else { return nil }
    return CastMember(
      name: name,
      character: credit.job,
      photo: imageURL(path: credit.profilePath, size: .profileW185),
      department: credit.department ?? credit.job,
      tmdbPersonId: credit.id
    )
  }

  private func imageURL(path: String?, size: TMDBImageSize) -> URL? {
    TMDBImageURL.url(path: path, size: size,
                     proxyBase: directKey == nil ? configuration.proxyBaseURL : nil)
  }

  private static func pickAgeRating(
    releaseDates: TMDBReleaseDates?,
    contentRatings: TMDBContentRatings?
  ) -> String? {
    let preferred = ["RU", "US", "GB"]
    if let ratings = contentRatings?.results {
      for country in preferred {
        if let hit = ratings.first(where: { $0.iso31661 == country }),
           let rating = hit.rating, !rating.isEmpty {
          return rating
        }
      }
      if let any = ratings.first(where: { !($0.rating ?? "").isEmpty })?.rating {
        return any
      }
    }
    if let countries = releaseDates?.results {
      for country in preferred {
        if let dates = countries.first(where: { $0.iso31661 == country })?.releaseDates {
          if let cert = dates.first(where: { !($0.certification ?? "").isEmpty })?.certification {
            return cert
          }
        }
      }
    }
    return nil
  }

  // MARK: - URL

  private var directKey: String? {
    guard let key = directAccess?.directAPIKey(), !key.isEmpty else { return nil }
    return key
  }

  /// A v4 read access token is a JWT and goes in the header; a v3 key is a query item.
  private static func isBearerToken(_ key: String) -> Bool { key.hasPrefix("eyJ") }

  private func fetch(_ url: URL) async throws -> Data {
    if let key = directKey, Self.isBearerToken(key) {
      return try await client.getData(url: url, headers: ["Authorization": "Bearer \(key)"])
    }
    return try await client.getData(url: url)
  }

  private func makeURL(path: String, query: [URLQueryItem]) throws -> URL {
    var query = query
    let direct = directKey
    if let direct, !Self.isBearerToken(direct) {
      query.append(URLQueryItem(name: "api_key", value: direct))
    }
    guard let base = direct != nil ? Self.directBaseURL : configuration.proxyBaseURL else {
      throw MetadataError.notConfigured
    }
    let baseString = base.absoluteString.hasSuffix("/")
      ? String(base.absoluteString.dropLast())
      : base.absoluteString
    guard var comps = URLComponents(string: baseString + path) else {
      throw MetadataError.badURL
    }
    comps.queryItems = query.isEmpty ? nil : query
    guard let url = comps.url else { throw MetadataError.badURL }
    return url
  }

  private static let dateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.calendar = Calendar(identifier: .gregorian)
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone(secondsFromGMT: 0)
    f.dateFormat = "yyyy-MM-dd"
    return f
  }()

  static func parseDate(_ raw: String?) -> Date? {
    guard let raw, !raw.isEmpty else { return nil }
    return dateFormatter.date(from: String(raw.prefix(10)))
  }
}

private extension TMDBCredit {
  var knownDepartmentOrActing: String? {
    department ?? "Acting"
  }
}
