import Foundation

/// The app's MyAnimeList Client ID for public anime reads (`X-MAL-CLIENT-ID`).
/// Nil while the viewer has MAL ratings switched off, or no Client ID is configured.
public protocol MyAnimeListAccessProviding: Sendable {
  func malClientID() -> String?
}

/// Official MyAnimeList API v2 as a metadata source: mean score, rank, popularity,
/// `num_scoring_users`, and list `statistics`. Public anime details need only the
/// Client ID header — no user OAuth.
///
/// Replaces Trakt-relayed MAL votes when both answer: `TitleMetadata.merge` keeps the
/// MyAnimeList score with more votes. Answers are cached 12–24h (18h here).
///
/// Credential **name** only in source (`MALClientID` / `MAL_CLIENT_ID`); the value
/// comes from Info.plist substitution, process env, or CI secrets — never committed.
public final class MyAnimeListSource: MetadataSource, Sendable {
  public let id: MetadataSourceID = .myAnimeList

  public var isConfigured: Bool { access.malClientID() != nil }

  public static let apiBaseURL = URL(string: "https://api.myanimelist.net/v2")!
  public static let webBaseURL = URL(string: "https://myanimelist.net")!
  /// Fields requested on every detail call (Sasha, 2026-11-26).
  public static let detailFields =
    "mean,rank,popularity,num_scoring_users,statistics,alternative_titles,start_date,start_season,media_type"

  private let access: MyAnimeListAccessProviding
  private let client: MetadataHTTPClient
  private let cache: MetadataCache

  /// Midpoint of the 12–24h freshness window for rating counts.
  private static let ttl: TimeInterval = 60 * 60 * 18
  private static let searchTTL: TimeInterval = 60 * 60 * 24 * 7

  public init(access: MyAnimeListAccessProviding,
              client: MetadataHTTPClient = MetadataHTTPClient(),
              cache: MetadataCache = MetadataCache()) {
    self.access = access
    self.client = client
    self.cache = cache
  }

  public func titleMetadata(for identity: MediaIdentity) async throws -> TitleMetadata? {
    guard let clientID = access.malClientID() else { throw MetadataError.notConfigured }
    var meta = TitleMetadata()
    meta.attribution.insert(.myAnimeList)
    let headers = Self.headers(clientID: clientID)

    let animeID: Int?
    if let known = identity.mal, known > 0 {
      animeID = known
    } else if identity.isAnime || identity.mal != nil {
      animeID = await resolveID(identity: identity, headers: headers, meta: &meta)
    } else {
      meta.debugLog.append(SourceDebugEntry(
        source: .myAnimeList, endpoint: "resolve", url: "(not anime)",
        proxied: false, succeeded: false,
        responseBody: "Skipped — not marked anime and no MAL id on this title."))
      return meta
    }

    guard let animeID else { return meta }
    await fetchDetails(animeID: animeID, headers: headers, into: &meta)
    return meta
  }

  // MARK: - Resolve

  /// Prefer an already-known id; otherwise search by original title and match year.
  private func resolveID(identity: MediaIdentity, headers: [String: String],
                         meta: inout TitleMetadata) async -> Int? {
    let query = identity.originalTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    guard query.count >= 3 else {
      meta.debugLog.append(SourceDebugEntry(
        source: .myAnimeList, endpoint: "search", url: "(title too short)",
        proxied: false, succeeded: false,
        responseBody: "Skipped — original title shorter than MAL's three-character minimum."))
      return nil
    }
    var components = URLComponents(url: Self.apiBaseURL.appending(path: "anime"), resolvingAgainstBaseURL: false)
    components?.queryItems = [
      URLQueryItem(name: "q", value: String(query.prefix(64))),
      URLQueryItem(name: "limit", value: "8"),
      URLQueryItem(name: "fields", value: "id,title,alternative_titles,start_date,start_season,media_type"),
    ]
    guard let url = components?.url else { return nil }
    let key = "mal/search/\(query.lowercased())/\(identity.year)"
    let start = ContinuousClock().now
    let entry = await cache.deduped(key: key, ttl: Self.searchTTL) { [client] in
      do {
        return MetadataCache.Entry(payload: try await client.getData(url: url, headers: headers))
      } catch MetadataError.httpStatus(404) {
        return MetadataCache.Entry(payload: Data(), isNegative: true)
      } catch {
        return nil
      }
    }
    let elapsed = MetadataTiming.milliseconds(since: start)
    guard let entry, !entry.isNegative,
          let dto = try? client.decode(MALAnimeSearchDTO.self, from: entry.payload) else {
      meta.debugLog.append(SourceDebugEntry(
        source: .myAnimeList, endpoint: "search", url: url.absoluteString,
        proxied: false, succeeded: false,
        responseBody: entry == nil ? "No response — network error or MAL refused the request."
          : "MAL search returned nothing useful.",
        elapsedMilliseconds: elapsed))
      return nil
    }
    let picked = Self.pick(from: dto.data ?? [], year: identity.year, title: query)
    meta.debugLog.append(SourceDebugEntry(
      source: .myAnimeList, endpoint: "search", url: url.absoluteString,
      proxied: false, succeeded: picked != nil,
      responseBody: picked.map { "picked id=\($0)" }
        ?? (String(data: entry.payload.prefix(8 * 1024), encoding: .utf8) ?? ""),
      elapsedMilliseconds: elapsed))
    return picked
  }

  /// Prefer a start-year match, then an exact / alternative title match.
  static func pick(from rows: [MALAnimeSearchDTO.Row], year: Int, title: String) -> Int? {
    let needle = normalize(title)
    func yearOf(_ node: MALAnimeNodeDTO) -> Int? {
      if let y = node.startSeason?.year, y > 0 { return y }
      if let raw = node.startDate, raw.count >= 4, let y = Int(raw.prefix(4)), y > 0 { return y }
      return nil
    }
    let scored: [(Int, Int)] = rows.compactMap { row in
      guard let node = row.node, let id = node.id, id > 0 else { return nil }
      var score = 0
      if let y = yearOf(node), y == year { score += 100 }
      let titles = ([node.title] + (node.alternativeTitles?.allTitles ?? [])).compactMap { $0 }
      if titles.contains(where: { normalize($0) == needle }) { score += 50 }
      else if titles.contains(where: { normalize($0).contains(needle) || needle.contains(normalize($0)) }) {
        score += 10
      }
      return score > 0 ? (score, id) : (1, id) // first hit as weak fallback
    }
    return scored.max(by: { $0.0 < $1.0 })?.1
  }

  private static func normalize(_ raw: String) -> String {
    raw.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  // MARK: - Details

  private func fetchDetails(animeID: Int, headers: [String: String],
                            into meta: inout TitleMetadata) async {
    var components = URLComponents(
      url: Self.apiBaseURL.appending(path: "anime/\(animeID)"),
      resolvingAgainstBaseURL: false)
    components?.queryItems = [URLQueryItem(name: "fields", value: Self.detailFields)]
    guard let url = components?.url else { return }
    let start = ContinuousClock().now
    let entry = await cache.deduped(key: "mal/anime/\(animeID)", ttl: Self.ttl) { [client] in
      do {
        return MetadataCache.Entry(payload: try await client.getData(url: url, headers: headers))
      } catch MetadataError.httpStatus(404) {
        return MetadataCache.Entry(payload: Data(), isNegative: true)
      } catch {
        return nil
      }
    }
    let elapsed = MetadataTiming.milliseconds(since: start)
    guard let entry, !entry.isNegative,
          let dto = try? client.decode(MALAnimeDetailsDTO.self, from: entry.payload) else {
      meta.debugLog.append(SourceDebugEntry(
        source: .myAnimeList, endpoint: "anime", url: url.absoluteString,
        proxied: false, succeeded: false,
        responseBody: entry == nil ? "No response — network error or MAL refused the request."
          : "MAL does not know this anime id.",
        elapsedMilliseconds: elapsed))
      return
    }
    meta.debugLog.append(SourceDebugEntry(
      source: .myAnimeList, endpoint: "anime", url: url.absoluteString,
      proxied: false, succeeded: true,
      responseBody: String(data: entry.payload.prefix(16 * 1024), encoding: .utf8) ?? "",
      elapsedMilliseconds: elapsed))
    Self.apply(dto, to: &meta)
  }

  static func apply(_ dto: MALAnimeDetailsDTO, to meta: inout TitleMetadata) {
    let id = dto.id
    meta.malID = id
    let page = id.map { webBaseURL.appending(path: "anime/\($0)") }
    if let page {
      meta.externalLinks = [ExternalLink(site: .myAnimeList, url: page)]
    }
    if let mean = dto.mean, mean > 0 {
      let votes = dto.numScoringUsers.flatMap { $0 > 0 ? $0 : nil }
      meta.externalRatings = [
        ExternalRating(kind: .myAnimeList, value: mean, votes: votes, url: page)
      ]
    }
    let status = dto.statistics?.status
    let stats = MyAnimeListStats(
      rank: dto.rank,
      popularity: dto.popularity,
      watching: status?.watching,
      completed: status?.completed,
      onHold: status?.onHold,
      dropped: status?.dropped,
      planToWatch: status?.planToWatch,
      numListUsers: dto.statistics?.numListUsers
    )
    meta.myAnimeListStats = stats.isEmpty ? nil : stats
  }

  static func headers(clientID: String) -> [String: String] {
    ["X-MAL-CLIENT-ID": clientID, "Accept": "application/json"]
  }

  /// `https://myanimelist.net/anime/5114/…` → `5114`.
  public static func animeID(from url: URL?) -> Int? {
    guard let url else { return nil }
    let parts = url.path.split(separator: "/")
    guard let anime = parts.firstIndex(of: "anime"), anime + 1 < parts.count,
          let id = Int(parts[anime + 1]), id > 0 else { return nil }
    return id
  }

  public static func animeID(fromLink link: String?) -> Int? {
    animeID(from: link.flatMap(URL.init(string:)))
  }
}

// MARK: - DTOs (api.myanimelist.net/v2)

struct MALAnimeSearchDTO: Decodable {
  struct Row: Decodable {
    let node: MALAnimeNodeDTO?
  }
  let data: [Row]?
}

struct MALAnimeNodeDTO: Decodable {
  let id: Int?
  let title: String?
  let alternativeTitles: MALAlternativeTitlesDTO?
  let startDate: String?
  let startSeason: MALStartSeasonDTO?
  let mediaType: String?

  enum CodingKeys: String, CodingKey {
    case id, title
    case alternativeTitles = "alternative_titles"
    case startDate = "start_date"
    case startSeason = "start_season"
    case mediaType = "media_type"
  }
}

struct MALAlternativeTitlesDTO: Decodable {
  let synonyms: [String]?
  let en: String?
  let ja: String?

  var allTitles: [String] {
    (synonyms ?? []) + [en, ja].compactMap { $0 }.filter { !$0.isEmpty }
  }
}

struct MALStartSeasonDTO: Decodable {
  let year: Int?
  let season: String?
}

struct MALAnimeDetailsDTO: Decodable {
  let id: Int?
  let title: String?
  let mean: Double?
  let rank: Int?
  let popularity: Int?
  let numScoringUsers: Int?
  let statistics: MALStatisticsDTO?
  let alternativeTitles: MALAlternativeTitlesDTO?
  let startDate: String?
  let startSeason: MALStartSeasonDTO?
  let mediaType: String?

  enum CodingKeys: String, CodingKey {
    case id, title, mean, rank, popularity, statistics
    case numScoringUsers = "num_scoring_users"
    case alternativeTitles = "alternative_titles"
    case startDate = "start_date"
    case startSeason = "start_season"
    case mediaType = "media_type"
  }
}

struct MALStatisticsDTO: Decodable {
  struct Status: Decodable {
    let watching: Int?
    let completed: Int?
    let onHold: Int?
    let dropped: Int?
    let planToWatch: Int?

    enum CodingKeys: String, CodingKey {
      case watching, completed, dropped
      case onHold = "on_hold"
      case planToWatch = "plan_to_watch"
    }

    init(from decoder: Decoder) throws {
      let c = try decoder.container(keyedBy: CodingKeys.self)
      watching = Self.int(from: c, key: .watching)
      completed = Self.int(from: c, key: .completed)
      onHold = Self.int(from: c, key: .onHold)
      dropped = Self.int(from: c, key: .dropped)
      planToWatch = Self.int(from: c, key: .planToWatch)
    }

    /// MAL sometimes sends status counts as strings.
    private static func int(from c: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) -> Int? {
      if let v = try? c.decodeIfPresent(Int.self, forKey: key) { return v }
      if let s = try? c.decodeIfPresent(String.self, forKey: key) { return Int(s) }
      return nil
    }
  }

  let status: Status?
  let numListUsers: Int?

  enum CodingKeys: String, CodingKey {
    case status
    case numListUsers = "num_list_users"
  }
}
