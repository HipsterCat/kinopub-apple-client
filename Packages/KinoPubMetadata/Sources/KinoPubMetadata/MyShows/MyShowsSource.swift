import Foundation

/// Whether the viewer has MyShows switched on in Settings › Integrations.
public protocol MyShowsAccessProviding: Sendable {
  var isMyShowsEnabled: Bool { get }
}

/// MyShows.me, the Russian series tracker, through its public JSON-RPC API: its own
/// score (0…5) with votes, how many people are watching the show, and fresher IMDb
/// numbers. Series only, because MyShows has no films. No account needed.
///
/// `shows.GetByExternalId` matches by Kinopoisk id, or by the IMDb id as a bare
/// number (`903747`, not `tt0903747`). The full card comes back in one call and is
/// kept for a day (Sasha, 2026-11-09).
public final class MyShowsSource: MetadataSource, @unchecked Sendable {
  public let id: MetadataSourceID = .myShows

  public var isConfigured: Bool { access.isMyShowsEnabled }

  public static let rpcURL = URL(string: "https://api.myshows.me/v2/rpc/")!

  private let access: MyShowsAccessProviding
  private let session: URLSession
  private let cache: MetadataCache

  private static let ttl: TimeInterval = 60 * 60 * 24

  public init(access: MyShowsAccessProviding,
              session: URLSession = .shared,
              cache: MetadataCache = MetadataCache()) {
    self.access = access
    self.session = session
    self.cache = cache
  }

  public func titleMetadata(for identity: MediaIdentity) async throws -> TitleMetadata? {
    guard isConfigured else { throw MetadataError.notConfigured }
    var meta = TitleMetadata()
    meta.attribution.insert(.myShows)
    guard identity.isSeries else { return meta }

    var lookups: [(source: String, id: Int)] = []
    if let kinopoisk = identity.kinopoisk, kinopoisk > 0 { lookups.append(("kinopoisk", kinopoisk)) }
    if let imdb = identity.imdb.flatMap(Self.imdbNumber) { lookups.append(("imdb", imdb)) }

    for lookup in lookups {
      let key = "myshows/\(lookup.source)/\(lookup.id)"
      let entry = await cache.deduped(key: key, ttl: Self.ttl) { [session] in
        await Self.call(session: session, method: "shows.GetByExternalId",
                        params: ["id": lookup.id, "source": lookup.source])
      }
      guard let entry else {
        meta.debugLog.append(Self.debug(lookup, false, "No response."))
        continue
      }
      guard !entry.isNegative, let show = try? JSONDecoder().decode(MyShowsShowDTO.self, from: entry.payload) else {
        meta.debugLog.append(Self.debug(lookup, false, "MyShows does not know this show."))
        continue
      }
      meta.debugLog.append(Self.debug(lookup, true, String(data: entry.payload.prefix(16 * 1024), encoding: .utf8) ?? ""))
      Self.apply(show, to: &meta)
      return meta
    }
    return meta
  }

  // MARK: - Mapping

  static func apply(_ show: MyShowsShowDTO, to meta: inout TitleMetadata) {
    let page = URL(string: "https://myshows.me/view/\(show.id)/")
    if let rating = show.rating, rating > 0, let votes = show.voted, votes > 0 {
      meta.externalRatings = [ExternalRating(kind: .myShows, value: rating, votes: votes, url: page)]
    }
    if let rating = show.imdbRating, rating > 0, let votes = show.imdbVoted, votes > 0 {
      meta.relayedIMDbRating = rating
      meta.relayedIMDbVotes = votes
    }
    if (show.watching ?? 0) > 0 || (show.watchingTotal ?? 0) > 0 {
      meta.myShowsStats = MyShowsStats(watching: show.watching ?? 0, watchingTotal: show.watchingTotal ?? 0)
    }
    if let page { meta.externalLinks = [ExternalLink(site: .myShows, url: page)] }
    if meta.kinopoiskID == nil, let id = show.kinopoiskId, id > 0 { meta.kinopoiskID = id }
  }

  /// `tt0903747` → 903747.
  static func imdbNumber(_ raw: String) -> Int? {
    guard raw.hasPrefix("tt"), let number = Int(raw.dropFirst(2)), number > 0 else { return nil }
    return number
  }

  // MARK: - JSON-RPC

  /// The call's `result`, or a negative entry when MyShows answers "not found".
  static func call(session: URLSession, method: String, params: [String: Any]) async -> MetadataCache.Entry? {
    var request = URLRequest(url: rpcURL, timeoutInterval: 12)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("KinoPubAppleClient/1.0 (https://github.com/HipsterCat/kinopub-apple-client)",
                     forHTTPHeaderField: "User-Agent")
    let body: [String: Any] = ["jsonrpc": "2.0", "method": method, "params": params, "id": 1]
    request.httpBody = try? JSONSerialization.data(withJSONObject: body)
    guard let (data, response) = try? await session.data(for: request),
          (response as? HTTPURLResponse)?.statusCode == 200,
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
    if object["error"] != nil { return MetadataCache.Entry(payload: Data(), isNegative: true) }
    guard let result = object["result"], !(result is NSNull),
          let payload = try? JSONSerialization.data(withJSONObject: result) else {
      return MetadataCache.Entry(payload: Data(), isNegative: true)
    }
    return MetadataCache.Entry(payload: payload)
  }

  private static func debug(_ lookup: (source: String, id: Int), _ ok: Bool, _ body: String) -> SourceDebugEntry {
    SourceDebugEntry(source: .myShows, endpoint: "shows.GetByExternalId",
                     url: "\(rpcURL.absoluteString) \(lookup.source)=\(lookup.id)",
                     proxied: false, succeeded: ok, responseBody: body)
  }
}

/// `shows.GetById` / `shows.GetByExternalId` result: the fields the app reads.
struct MyShowsShowDTO: Decodable {
  let id: Int
  let rating: Double?
  let voted: Int?
  let imdbRating: Double?
  let imdbVoted: Int?
  let kinopoiskId: Int?
  let watching: Int?
  let watchingTotal: Int?
}
