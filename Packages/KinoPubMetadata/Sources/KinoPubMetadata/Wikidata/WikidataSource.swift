import Foundation

/// Whether the viewer has Wikidata switched on in Settings › Integrations.
public protocol WikidataAccessProviding: Sendable {
  var isWikidataEnabled: Bool { get }
}

/// Wikidata as a metadata source: the title's ids on every other site (Kinopoisk,
/// TMDB, Douban, Letterboxd, Metacritic, Rotten Tomatoes, Trakt, TVDB, MyAnimeList,
/// AniDB, AniList, Kitsu), its Wikipedia articles, box office and budget in dollars,
/// and how many awards and nominations it has. Public CC0 data, no key.
///
/// Found by IMDb id, as Plozz does it (`haswbstatement:P345=tt…`): one search, then one
/// `wbgetentities` for the claims and the ru/en sitelinks. Kept for a week. Wikidata asks
/// for a User-Agent that names the client and how to reach it (Sasha, 2026-11-09).
public final class WikidataSource: MetadataSource, @unchecked Sendable {
  public let id: MetadataSourceID = .wikidata

  public var isConfigured: Bool { access.isWikidataEnabled }

  public static let apiURL = URL(string: "https://www.wikidata.org/w/api.php")!
  static let headers = [
    "User-Agent": "KinoPubAppleClient/1.0 (https://github.com/HipsterCat/kinopub-apple-client)",
    "Accept": "application/json",
  ]

  private let access: WikidataAccessProviding
  private let language: String
  private let client: MetadataHTTPClient
  private let cache: MetadataCache

  private static let ttl: TimeInterval = 60 * 60 * 24 * 7

  public init(access: WikidataAccessProviding,
              language: String = Locale.current.language.languageCode?.identifier ?? "ru",
              client: MetadataHTTPClient = MetadataHTTPClient(),
              cache: MetadataCache = MetadataCache()) {
    self.access = access
    self.language = language
    self.client = client
    self.cache = cache
  }

  public func titleMetadata(for identity: MediaIdentity) async throws -> TitleMetadata? {
    guard isConfigured else { throw MetadataError.notConfigured }
    var meta = TitleMetadata()
    meta.attribution.insert(.wikidata)
    guard let imdb = identity.imdb, imdb.hasPrefix("tt") else {
      meta.debugLog = [Self.debug("search", "(no imdb id on this title)", false, "Skipped — no IMDb id from kino.pub.")]
      return meta
    }

    let searchURL = Self.url([
      "action": "query", "format": "json", "list": "search", "srlimit": "1",
      "srsearch": "haswbstatement:P345=\(imdb)",
    ])
    let search = await fetch(searchURL, key: "wikidata/search/\(imdb)")
    guard let searchData = search,
          let found = try? client.decode(WikidataSearchDTO.self, from: searchData),
          let qid = found.query?.search.first?.title, qid.hasPrefix("Q") else {
      meta.debugLog = [Self.debug("search", searchURL.absoluteString, false,
                                  search == nil ? "No response." : "Wikidata does not know this IMDb id.")]
      return meta
    }

    let entityURL = Self.url([
      "action": "wbgetentities", "format": "json", "props": "claims|sitelinks",
      "sitefilter": "ruwiki|enwiki", "ids": qid,
    ])
    guard let entityData = await fetch(entityURL, key: "wikidata/entity/\(qid)"),
          let response = try? client.decode(WikidataEntitiesDTO.self, from: entityData),
          let entity = response.entities[qid] else {
      meta.debugLog = [Self.debug("search", searchURL.absoluteString, true, qid),
                       Self.debug("entity", entityURL.absoluteString, false, "No entity.")]
      return meta
    }
    meta.debugLog = [Self.debug("search", searchURL.absoluteString, true, qid),
                     Self.debug("entity", entityURL.absoluteString, true,
                                String(data: entityData.prefix(64 * 1024), encoding: .utf8) ?? "")]
    Self.apply(entity, qid: qid, isSeries: identity.isSeries, language: language, to: &meta)
    return meta
  }

  // MARK: - Mapping

  static func apply(_ entity: WikidataEntityDTO, qid: String, isSeries: Bool, language: String,
                    to meta: inout TitleMetadata) {
    meta.wikidataID = qid
    let claims = entity.claims ?? [:]
    func string(_ property: String) -> String? {
      claims[property]?.lazy.compactMap { $0.mainsnak.datavalue?.value.string }.first
    }

    meta.kinopoiskID = string("P2603").flatMap(Int.init)
    meta.tmdbId = string(isSeries ? "P4983" : "P4947").flatMap(Int.init)

    // Box office: the statement scoped to the world (P3005 = Q13780930) and the one for
    // the US (Q30); a lone unscoped figure counts as worldwide. Dollars only.
    var worldwide: Int?
    var domestic: Int?
    for statement in claims["P2142"] ?? [] {
      guard let amount = statement.mainsnak.datavalue?.value.dollars else { continue }
      let scope = statement.qualifiers?["P3005"]?.first?.datavalue?.value.entityID
      switch scope {
      case "Q30": domestic = domestic ?? amount
      case "Q13780930", nil: worldwide = worldwide ?? amount
      default: break
      }
    }
    meta.boxOfficeWorldwideUSD = worldwide
    meta.boxOfficeUSD = domestic
    meta.budget = claims["P2130"]?.lazy.compactMap { $0.mainsnak.datavalue?.value.dollars }.first

    let awards = claims["P166"]?.count ?? 0
    let nominations = claims["P1411"]?.count ?? 0
    meta.awardCounts = awards + nominations > 0 ? AwardCounts(wins: awards, nominations: nominations) : nil

    var links: [ExternalLink] = []
    func add(_ site: ExternalLink.Site, _ url: String?) {
      if let url, let parsed = URL(string: url) { links.append(ExternalLink(site: site, url: parsed)) }
    }
    // The app's language first, then English.
    let wikis = language == "ru" ? ["ruwiki", "enwiki"] : ["enwiki", "ruwiki"]
    if let wiki = wikis.first(where: { entity.sitelinks?[$0] != nil }), let title = entity.sitelinks?[wiki]?.title {
      let host = wiki == "ruwiki" ? "ru" : "en"
      let path = title.replacingOccurrences(of: " ", with: "_")
        .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? title
      add(.wikipedia, "https://\(host).wikipedia.org/wiki/\(path)")
    }
    add(.kinopoisk, meta.kinopoiskID.map { "https://www.kinopoisk.ru/\(isSeries ? "series" : "film")/\($0)/" })
    add(.douban, string("P4529").map { "https://movie.douban.com/subject/\($0)/" })
    add(.letterboxd, string("P6127").map { "https://letterboxd.com/film/\($0)/" })
    add(.metacritic, string("P1712").map { "https://www.metacritic.com/\($0)" })
    add(.rottenTomatoes, string("P1258").map { "https://www.rottentomatoes.com/\($0)" })
    add(.trakt, string("P8013").map { "https://trakt.tv/\($0)" })
    add(.tvdb, string("P4835").map { "https://thetvdb.com/?tab=series&id=\($0)" })
    add(.myAnimeList, string("P4086").map { "https://myanimelist.net/anime/\($0)" })
    add(.aniDB, string("P5646").map { "https://anidb.net/anime/\($0)" })
    add(.aniList, string("P8729").map { "https://anilist.co/anime/\($0)" })
    add(.kitsu, string("P11495").map { "https://kitsu.app/anime/\($0)" })
    add(.wikidata, "https://www.wikidata.org/wiki/\(qid)")
    meta.externalLinks = links
  }

  // MARK: - HTTP

  static func url(_ query: [String: String]) -> URL {
    var components = URLComponents(url: apiURL, resolvingAgainstBaseURL: false)!
    components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
    return components.url!
  }

  private func fetch(_ url: URL, key: String) async -> Data? {
    let entry = await cache.deduped(key: key, ttl: Self.ttl) { [client] in
      guard let data = try? await client.getData(url: url, headers: Self.headers) else { return nil }
      return MetadataCache.Entry(payload: data)
    }
    return entry?.payload
  }

  private static func debug(_ endpoint: String, _ url: String, _ ok: Bool, _ body: String) -> SourceDebugEntry {
    SourceDebugEntry(source: .wikidata, endpoint: endpoint, url: url, proxied: false, succeeded: ok, responseBody: body)
  }
}

// MARK: - DTOs (MediaWiki action API)

struct WikidataSearchDTO: Decodable {
  struct Query: Decodable {
    struct Hit: Decodable { let title: String }
    let search: [Hit]
  }
  let query: Query?
}

struct WikidataEntitiesDTO: Decodable {
  let entities: [String: WikidataEntityDTO]
}

struct WikidataEntityDTO: Decodable {
  struct Sitelink: Decodable { let title: String }
  struct Snak: Decodable {
    struct DataValue: Decodable { let value: WikidataValue }
    let datavalue: DataValue?
  }
  struct Statement: Decodable {
    let mainsnak: Snak
    let qualifiers: [String: [Snak]]?
  }
  let claims: [String: [Statement]]?
  let sitelinks: [String: Sitelink]?
}

/// A datavalue's `value`: a plain string (external ids, file names), an entity
/// reference, or a quantity. Anything else decodes as `.other`.
enum WikidataValue: Decodable {
  case string(String)
  case entity(String)
  case quantity(amount: Double, unit: String)
  case other

  private struct Object: Decodable {
    let id: String?
    let amount: String?
    let unit: String?
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let text = try? container.decode(String.self) { self = .string(text); return }
    if let object = try? container.decode(Object.self) {
      if let id = object.id { self = .entity(id); return }
      if let amount = object.amount.flatMap({ Double($0.replacingOccurrences(of: "+", with: "")) }) {
        self = .quantity(amount: amount, unit: object.unit ?? ""); return
      }
    }
    self = .other
  }

  var string: String? { if case .string(let text) = self { text } else { nil } }
  var entityID: String? { if case .entity(let id) = self { id } else { nil } }
  /// A quantity in US dollars (Q4917), whole.
  var dollars: Int? {
    guard case .quantity(let amount, let unit) = self, unit.hasSuffix("/Q4917"), amount > 0 else { return nil }
    return Int(amount)
  }
}
