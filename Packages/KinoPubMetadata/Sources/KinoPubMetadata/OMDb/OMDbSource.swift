import Foundation

/// The viewer's own OMDb key, read on every request: nil while none is connected or it
/// is switched off in Settings › Integrations.
public protocol OMDbKeyProviding: Sendable {
  func omdbAPIKey() -> String?
}

/// OMDb (omdbapi.com) as a metadata source, with the viewer's own key: the IMDb score and
/// votes, the Tomatometer and the Metascore, and two things nobody else here gives — the
/// US box office and the awards line ("Won 4 Oscars. 157 wins & 220 nominations total").
///
/// One call per title, by IMDb id. The free key allows 1 000 calls a day, so an answer
/// is kept for three days. Trakt relays the same Rotten Tomatoes and Metacritic figures
/// and outranks OMDb where both answer: `MetadataService` merges Trakt first, the merge
/// keeps the first score of each kind, and IMDb takes whichever source counted more votes
/// (Sasha, 2026-11-09).
public final class OMDbSource: MetadataSource, @unchecked Sendable {
  public let id: MetadataSourceID = .omdb

  public var isConfigured: Bool { keys.omdbAPIKey() != nil }

  public static let baseURL = URL(string: "https://www.omdbapi.com/")!

  private let keys: OMDbKeyProviding
  private let client: MetadataHTTPClient
  private let cache: MetadataCache

  private static let ttl: TimeInterval = 60 * 60 * 24 * 3

  public init(keys: OMDbKeyProviding,
              client: MetadataHTTPClient = MetadataHTTPClient(),
              cache: MetadataCache = MetadataCache()) {
    self.keys = keys
    self.client = client
    self.cache = cache
  }

  /// The one request: title by IMDb id. Also what Settings uses to check a key.
  public static func requestURL(imdb: String, key: String) -> URL? {
    var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
    components?.queryItems = [URLQueryItem(name: "i", value: imdb), URLQueryItem(name: "apikey", value: key)]
    return components?.url
  }

  public func titleMetadata(for identity: MediaIdentity) async throws -> TitleMetadata? {
    guard let key = keys.omdbAPIKey() else { throw MetadataError.notConfigured }
    var meta = TitleMetadata()
    meta.attribution.insert(.omdb)
    guard let imdb = identity.imdb, !imdb.isEmpty, let url = Self.requestURL(imdb: imdb, key: key) else {
      meta.debugLog = [SourceDebugEntry(source: .omdb, endpoint: "title", url: "(no imdb id on this title)",
                                        proxied: false, succeeded: false,
                                        responseBody: "Skipped — no IMDb id from kino.pub.")]
      return meta
    }
    // The key stays out of the log.
    let shownURL = url.absoluteString.replacingOccurrences(of: key, with: "•••")
    let start = ContinuousClock().now
    let entry = await cache.deduped(key: "omdb/title/\(imdb)", ttl: Self.ttl) { [client] in
      do {
        let data = try await client.getData(url: url, headers: [:])
        // "Movie not found!" comes back as 200 with Response "False": a miss worth keeping.
        let dto = try? client.decode(OMDbTitleDTO.self, from: data)
        return MetadataCache.Entry(payload: data, isNegative: dto?.response == "False")
      } catch {
        return nil
      }
    }
    let elapsed = MetadataTiming.milliseconds(since: start)
    guard let entry, !entry.isNegative,
          let dto = try? client.decode(OMDbTitleDTO.self, from: entry.payload) else {
      meta.debugLog = [SourceDebugEntry(
        source: .omdb, endpoint: "title", url: shownURL, proxied: false, succeeded: false,
        responseBody: entry.map { String(data: $0.payload, encoding: .utf8) ?? "" }
          ?? "No response — network error, a rejected key or today's limit used up.",
        elapsedMilliseconds: elapsed)]
      return meta
    }
    meta.debugLog = [SourceDebugEntry(
      source: .omdb, endpoint: "title", url: shownURL, proxied: false, succeeded: true,
      responseBody: String(data: entry.payload, encoding: .utf8) ?? "", elapsedMilliseconds: elapsed)]
    Self.apply(dto, imdb: imdb, to: &meta)
    return meta
  }

  // MARK: - Mapping

  static func apply(_ dto: OMDbTitleDTO, imdb: String, to meta: inout TitleMetadata) {
    meta.externalRatings = ratings(from: dto, imdb: imdb)
    if let rating = number(dto.imdbRating), rating > 0, let votes = count(dto.imdbVotes), votes > 0 {
      meta.relayedIMDbRating = rating
      meta.relayedIMDbVotes = votes
    }
    meta.boxOfficeUSD = count(dto.boxOffice).flatMap { $0 > 0 ? $0 : nil }
    meta.awardsSummary = text(dto.awards)
  }

  static func ratings(from dto: OMDbTitleDTO, imdb: String) -> [ExternalRating] {
    var list: [ExternalRating] = []
    let tomatoes = dto.ratings?.first { $0.source == "Rotten Tomatoes" }?.value
    if let value = tomatoes.flatMap(number), value > 0 {
      list.append(ExternalRating(kind: .rottenTomatoes, value: value))
    }
    let metascore = number(dto.metascore)
      ?? dto.ratings?.first { $0.source == "Metacritic" }?.value.flatMap(number)
    if let value = metascore, value > 0 {
      list.append(ExternalRating(kind: .metacritic, value: value,
                                 url: URL(string: "https://www.imdb.com/title/\(imdb)/criticreviews")))
    }
    return list
  }

  /// The leading number of "75%", "57/100", "8.5/10", "57"; nil for "N/A".
  static func number(_ raw: String?) -> Double? {
    guard let raw else { return nil }
    let lead = raw.prefix { $0.isNumber || $0 == "." }
    return lead.isEmpty ? nil : Double(lead)
  }

  /// "1,234,567" and "$292,576,195" as whole numbers; nil for "N/A".
  static func count(_ raw: String?) -> Int? {
    guard let raw else { return nil }
    let digits = raw.filter(\.isNumber)
    return digits.isEmpty ? nil : Int(digits)
  }

  static func text(_ raw: String?) -> String? {
    guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty, raw != "N/A" else {
      return nil
    }
    return raw
  }
}

// MARK: - DTO (omdbapi.com, `?i=` by IMDb id)

struct OMDbTitleDTO: Decodable {
  struct Rating: Decodable {
    let source: String
    let value: String?

    enum CodingKeys: String, CodingKey {
      case source = "Source"
      case value = "Value"
    }
  }

  let response: String?
  let ratings: [Rating]?
  let metascore: String?
  let imdbRating: String?
  let imdbVotes: String?
  let boxOffice: String?
  let awards: String?

  enum CodingKeys: String, CodingKey {
    case response = "Response"
    case ratings = "Ratings"
    case metascore = "Metascore"
    case imdbRating
    case imdbVotes
    case boxOffice = "BoxOffice"
    case awards = "Awards"
  }
}
