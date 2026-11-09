import Foundation

/// Whether the viewer has Douban's scores switched on in Settings › Integrations.
public protocol DoubanAccessProviding: Sendable {
  var isDoubanEnabled: Bool { get }
}

/// Douban's score, star breakdown, audience counts and genre ranks, by IMDb id, through
/// our worker's `GET /v1/douban/by/imdb/{tt}`. The worker signs the calls to Douban's
/// app API (Frodo) with secrets the app never holds, keeps the answers for a day, and
/// returns numbers and English only (Sasha, 2026-11-09).
public final class DoubanSource: MetadataSource, @unchecked Sendable {
  public let id: MetadataSourceID = .douban

  public var isConfigured: Bool { configuration.isConfigured && access.isDoubanEnabled }

  private let configuration: MetadataConfiguration
  private let access: DoubanAccessProviding
  private let client: MetadataHTTPClient
  private let cache: MetadataCache

  private static let ttl: TimeInterval = 60 * 60 * 24

  public init(configuration: MetadataConfiguration,
              access: DoubanAccessProviding,
              client: MetadataHTTPClient = MetadataHTTPClient(),
              cache: MetadataCache = MetadataCache()) {
    self.configuration = configuration
    self.access = access
    self.client = client
    self.cache = cache
  }

  public func titleMetadata(for identity: MediaIdentity) async throws -> TitleMetadata? {
    guard isConfigured, let base = configuration.proxyBaseURL else { throw MetadataError.notConfigured }
    var meta = TitleMetadata()
    meta.attribution.insert(.douban)
    guard let imdb = identity.imdb, imdb.hasPrefix("tt") else {
      meta.debugLog = [SourceDebugEntry(source: .douban, endpoint: "douban", url: "(no imdb id on this title)",
                                        proxied: true, succeeded: false,
                                        responseBody: "Skipped — no IMDb id from kino.pub.")]
      return meta
    }
    let url = base.appending(path: "v1/douban/by/imdb/\(imdb)")
    let start = ContinuousClock().now
    let entry = await cache.deduped(key: "douban/imdb/\(imdb)", ttl: Self.ttl) { [client] in
      do {
        return MetadataCache.Entry(payload: try await client.getData(url: url))
      } catch MetadataError.httpStatus(404) {
        return MetadataCache.Entry(payload: Data(), isNegative: true)
      } catch {
        return nil
      }
    }
    let elapsed = MetadataTiming.milliseconds(since: start)
    guard let entry, !entry.isNegative, let dto = try? client.decode(DoubanTitleDTO.self, from: entry.payload) else {
      meta.debugLog = [SourceDebugEntry(
        source: .douban, endpoint: "douban", url: url.absoluteString, proxied: true, succeeded: false,
        responseBody: entry == nil ? "No response — network error, or the worker has no Douban secrets."
          : "Douban does not know this title.",
        elapsedMilliseconds: elapsed)]
      return meta
    }
    meta.debugLog = [SourceDebugEntry(
      source: .douban, endpoint: "douban", url: url.absoluteString, proxied: true, succeeded: true,
      responseBody: String(data: entry.payload, encoding: .utf8) ?? "", elapsedMilliseconds: elapsed)]
    Self.apply(dto, to: &meta)
    return meta
  }

  static func apply(_ dto: DoubanTitleDTO, to meta: inout TitleMetadata) {
    let page = dto.url.flatMap(URL.init(string:))
    if let rating = dto.rating, rating.value > 0, rating.votes > 0 {
      meta.externalRatings = [ExternalRating(kind: .douban, value: rating.value, votes: rating.votes, url: page)]
    }
    let shares = dto.distribution ?? []
    let stats = DoubanStats(
      shares: shares.count == 5 ? shares : [],
      watched: dto.watched, wantToWatch: dto.wantToWatch, watching: dto.watching,
      ranks: (dto.ranks ?? []).map { DoubanStats.Rank(genre: $0.genre, betterThan: $0.betterThan) },
      isSeries: dto.type == "tv")
    meta.doubanStats = stats.isEmpty ? nil : stats
  }
}

/// The worker's answer (`workers/tmdb-proxy/src/douban.js`, `project`).
struct DoubanTitleDTO: Decodable {
  struct Rating: Decodable {
    let value: Double
    let votes: Int
  }
  struct Rank: Decodable {
    let genre: String
    let betterThan: Double
  }
  let id: String?
  let type: String?
  let url: String?
  let rating: Rating?
  let distribution: [Double]?
  let watched: Int?
  let wantToWatch: Int?
  let watching: Int?
  let ranks: [Rank]?
}
