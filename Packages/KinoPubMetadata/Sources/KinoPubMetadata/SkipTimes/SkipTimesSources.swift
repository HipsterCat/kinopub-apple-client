import Foundation

/// Whether the viewer keeps a skip-times source on in Settings › Integrations.
public protocol SkipTimesAccessProviding: Sendable {
  func isEnabled(_ source: MetadataSourceID) -> Bool
}

/// SkipDB (skipdb.tv), the open skip-times database: intro, recap, outro and preview of
/// an episode or a film by IMDb id. Reading needs no key. With the stream's runtime in
/// seconds it picks the submission for this cut and shifts the times to it.
///
/// `GET https://api.skipdb.tv/api/segments?imdb_id=tt…&season=&episode=&duration=<s>`
/// answers `{segments: {intro, recap, outro, preview}}`, each null or
/// `{start_ms, end_ms, confidence, …}` (skipdb.tv/docs, 2026-11-09). Data under ODbL 1.0:
/// shown with attribution on the source's Settings page (Sasha, 2026-11-09).
public final class SkipDBSource: MetadataSource, @unchecked Sendable {
  public let id: MetadataSourceID = .skipDB
  public var isConfigured: Bool { access.isEnabled(.skipDB) }

  public static let baseURL = URL(string: "https://api.skipdb.tv/api/segments")!

  private let access: SkipTimesAccessProviding
  private let session: URLSession
  private let cache: MetadataCache

  public init(access: SkipTimesAccessProviding, session: URLSession = .shared,
              cache: MetadataCache = MetadataCache()) {
    self.access = access
    self.session = session
    self.cache = cache
  }

  public func segments(for identity: MediaIdentity, season: Int?, episode: Int?,
                       durationMs: Int?) async throws -> SkipSegments? {
    guard isConfigured else { throw MetadataError.notConfigured }
    guard let url = Self.url(identity: identity, season: season, episode: episode, durationMs: durationMs)
    else { return nil }
    let entry = await cache.deduped(key: "skipdb/\(url.query ?? "")", ttl: SkipTimes.ttl) { [session] in
      await SkipTimes.get(url, session: session)
    }
    guard let entry, !entry.isNegative,
          let dto = try? SkipTimes.decoder.decode(SkipDBResponseDTO.self, from: entry.payload) else { return nil }
    let result = Self.segments(from: dto)
    return result.isEmpty ? nil : result
  }

  static func url(identity: MediaIdentity, season: Int?, episode: Int?, durationMs: Int?) -> URL? {
    guard let imdb = identity.imdb, imdb.hasPrefix("tt") else { return nil }
    var items = [URLQueryItem(name: "imdb_id", value: imdb)]
    if let season, let episode {
      items.append(URLQueryItem(name: "season", value: String(season)))
      items.append(URLQueryItem(name: "episode", value: String(episode)))
    }
    // Whole seconds: SkipDB asks for them (better CDN hits than milliseconds).
    if let durationMs, durationMs > 0 {
      items.append(URLQueryItem(name: "duration", value: String(durationMs / 1000)))
    }
    var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
    components?.queryItems = items
    return components?.url
  }

  static func segments(from dto: SkipDBResponseDTO) -> SkipSegments {
    func segment(_ raw: SkipDBResponseDTO.Segment?) -> SkipSegments.Segment? {
      guard let raw, let start = raw.startMs else { return nil }
      return SkipSegments.Segment(startMs: start, endMs: raw.endMs, source: .skipDB)
    }
    var result = SkipSegments()
    result[.intro] = segment(dto.segments?.intro)
    result[.recap] = segment(dto.segments?.recap)
    result[.credits] = segment(dto.segments?.outro)
    result[.preview] = segment(dto.segments?.preview)
    return result
  }
}

/// TheIntroDB (theintrodb.org): intro, recap, credits and preview, read without a key
/// (5 000 calls a day per address). Its data is not open, so it only fills what SkipDB
/// has not got.
///
/// `GET https://api.theintrodb.org/v4/media?imdb_id=tt…&season=&episode=&duration_ms=`
/// answers arrays per kind of `{start_ms, end_ms}`; a null start is the beginning, a null
/// end the end of the stream (the `theintrodb` npm SDK 4.0.0, 2026-11-09).
public final class TheIntroDBSource: MetadataSource, @unchecked Sendable {
  public let id: MetadataSourceID = .introdb
  public var isConfigured: Bool { access.isEnabled(.introdb) }

  public static let baseURL = URL(string: "https://api.theintrodb.org/v4/media")!

  private let access: SkipTimesAccessProviding
  private let session: URLSession
  private let cache: MetadataCache

  public init(access: SkipTimesAccessProviding, session: URLSession = .shared,
              cache: MetadataCache = MetadataCache()) {
    self.access = access
    self.session = session
    self.cache = cache
  }

  public func segments(for identity: MediaIdentity, season: Int?, episode: Int?,
                       durationMs: Int?) async throws -> SkipSegments? {
    guard isConfigured else { throw MetadataError.notConfigured }
    guard let url = Self.url(identity: identity, season: season, episode: episode, durationMs: durationMs)
    else { return nil }
    let entry = await cache.deduped(key: "theintrodb/\(url.query ?? "")", ttl: SkipTimes.ttl) { [session] in
      await SkipTimes.get(url, session: session)
    }
    guard let entry, !entry.isNegative,
          let dto = try? SkipTimes.decoder.decode(TheIntroDBMediaDTO.self, from: entry.payload) else { return nil }
    let result = Self.segments(from: dto)
    return result.isEmpty ? nil : result
  }

  static func url(identity: MediaIdentity, season: Int?, episode: Int?, durationMs: Int?) -> URL? {
    guard let imdb = identity.imdb, imdb.hasPrefix("tt") else { return nil }
    var items = [URLQueryItem(name: "imdb_id", value: imdb)]
    if let season, let episode {
      items.append(URLQueryItem(name: "season", value: String(season)))
      items.append(URLQueryItem(name: "episode", value: String(episode)))
      // Only single episodes take a runtime (the SDK's own check).
      if let durationMs, durationMs > 0 {
        items.append(URLQueryItem(name: "duration_ms", value: String(durationMs)))
      }
    }
    var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
    components?.queryItems = items
    return components?.url
  }

  static func segments(from dto: TheIntroDBMediaDTO) -> SkipSegments {
    func segment(_ list: [TheIntroDBMediaDTO.Segment]?) -> SkipSegments.Segment? {
      // The best supported one first when the source says how sure it is.
      let best = list?.max { ($0.confidence ?? 0, $0.submissionCount ?? 0) < ($1.confidence ?? 0, $1.submissionCount ?? 0) }
      guard let best, best.startMs != nil || best.endMs != nil else { return nil }
      return SkipSegments.Segment(startMs: best.startMs ?? 0, endMs: best.endMs, source: .introdb)
    }
    var result = SkipSegments()
    result[.intro] = segment(dto.intro)
    result[.recap] = segment(dto.recap)
    result[.credits] = segment(dto.credits)
    result[.preview] = segment(dto.preview)
    return result
  }
}

enum SkipTimes {
  /// Times change rarely once approved; a day keeps one episode to one call a day.
  static let ttl: TimeInterval = 60 * 60 * 24

  static var decoder: JSONDecoder {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return decoder
  }

  /// The body on 200; a negative entry on 404 (nothing known), nil on anything else so a
  /// failed call is asked again next time.
  static func get(_ url: URL, session: URLSession) async -> MetadataCache.Entry? {
    var request = URLRequest(url: url, timeoutInterval: 8)
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue("KinoPubAppleClient/1.0 (https://github.com/HipsterCat/kinopub-apple-client)",
                     forHTTPHeaderField: "User-Agent")
    guard let (data, response) = try? await session.data(for: request),
          let status = (response as? HTTPURLResponse)?.statusCode else { return nil }
    switch status {
    case 200: return MetadataCache.Entry(payload: data)
    case 404: return MetadataCache.Entry(payload: Data(), isNegative: true)
    default: return nil
    }
  }
}

// MARK: - DTOs

struct SkipDBResponseDTO: Decodable {
  struct Segment: Decodable {
    let startMs: Int?
    let endMs: Int?
    let confidence: Double?
  }
  struct Segments: Decodable {
    let intro: Segment?
    let recap: Segment?
    let outro: Segment?
    let preview: Segment?
  }
  let segments: Segments?
}

struct TheIntroDBMediaDTO: Decodable {
  struct Segment: Decodable {
    let startMs: Int?
    let endMs: Int?
    let confidence: Double?
    let submissionCount: Int?
  }
  let intro: [Segment]?
  let recap: [Segment]?
  let credits: [Segment]?
  let preview: [Segment]?
}
