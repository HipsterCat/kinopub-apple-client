import Foundation

/// The viewer's Plex sign-in: the account token and the app's own client id. Nil token
/// while nobody is signed in.
public protocol PlexAccessProviding: Sendable {
  func plexToken() -> String?
  var plexClientIdentifier: String { get }
}

/// Plex's cloud catalogue (Discover) as a metadata source, with the viewer's Plex account:
/// Common Sense Media's age, one-liner and topic ratings, the US content rating, and the
/// IMDb / Rotten Tomatoes figures Plex relays. No Plex server is involved.
///
/// Every call needs an account token (anonymous calls answer 401, measured 2026-11-09).
/// Three calls on a miss, all kept for a day: `matches` by IMDb guid on
/// metadata.provider.plex.tv gives the Plex id (24 hex characters); the item on
/// discover.provider.plex.tv (Plozz: metadata.provider's item reads moved there); and
/// Common Sense's full entry, which stayed on metadata.provider. The endpoints are the
/// ones Rivulet and Plozz use; Plex does not document them (Sasha, 2026-11-09).
public final class PlexSource: MetadataSource, @unchecked Sendable {
  public let id: MetadataSourceID = .plex

  public var isConfigured: Bool { access.plexToken() != nil }

  public static let metadataHost = URL(string: "https://metadata.provider.plex.tv")!
  public static let discoverHost = URL(string: "https://discover.provider.plex.tv")!

  private let access: PlexAccessProviding
  private let session: URLSession
  private let cache: MetadataCache

  private static let ttl: TimeInterval = 60 * 60 * 24

  public init(access: PlexAccessProviding,
              session: URLSession = .shared,
              cache: MetadataCache = MetadataCache()) {
    self.access = access
    self.session = session
    self.cache = cache
  }

  public func titleMetadata(for identity: MediaIdentity) async throws -> TitleMetadata? {
    guard let token = access.plexToken() else { throw MetadataError.notConfigured }
    var meta = TitleMetadata()
    meta.attribution.insert(.plex)
    guard let imdb = identity.imdb, imdb.hasPrefix("tt") else {
      meta.debugLog = [SourceDebugEntry(source: .plex, endpoint: "matches", url: "(no imdb id on this title)",
                                        proxied: false, succeeded: false,
                                        responseBody: "Skipped — no IMDb id from kino.pub.")]
      return meta
    }
    let type = identity.isSeries ? "2" : "1"
    var matches = URLComponents(url: Self.metadataHost.appending(path: "library/metadata/matches"),
                                resolvingAgainstBaseURL: false)!
    matches.queryItems = [URLQueryItem(name: "type", value: type),
                          URLQueryItem(name: "guid", value: "imdb://\(imdb)")]
    guard let match = await get(matches.url!, key: "plex/match/\(type)/\(imdb)", token: token,
                                endpoint: "matches", into: &meta),
          let item = try? JSONDecoder().decode(PlexContainerDTO.self, from: match).mediaContainer?.metadata?.first,
          let ratingKey = item.ratingKey, !ratingKey.isEmpty else {
      return meta
    }

    var detail = URLComponents(url: Self.discoverHost.appending(path: "library/metadata/\(ratingKey)"),
                               resolvingAgainstBaseURL: false)!
    detail.queryItems = [URLQueryItem(name: "includeGuids", value: "1"),
                         URLQueryItem(name: "includeReviews", value: "1")]
    let full = await get(detail.url!, key: "plex/item/\(ratingKey)", token: token, endpoint: "metadata", into: &meta)
      .flatMap { try? JSONDecoder().decode(PlexContainerDTO.self, from: $0).mediaContainer?.metadata?.first }
    Self.apply(full ?? item, to: &meta)

    let csmURL = Self.metadataHost.appending(path: "library/metadata/\(ratingKey)/commonsensemedia")
    if let data = await get(csmURL, key: "plex/csm/\(ratingKey)", token: token, endpoint: "commonsensemedia",
                            into: &meta),
       let container = try? JSONDecoder().decode(PlexContainerDTO.self, from: data).mediaContainer,
       let csm = container.commonSenseMedia?.first ?? container.metadata?.first?.commonSenseMedia?.first {
      if let full = Self.commonSense(csm) { meta.commonSense = full.richer(than: meta.commonSense) }
    }
    return meta
  }

  // MARK: - Mapping

  static func apply(_ item: PlexMetadataDTO, to meta: inout TitleMetadata) {
    meta.plexID = item.ratingKey
    if let rating = text(item.contentRating) { meta.ageRating = rating }
    var external: [ExternalRating] = []
    for rating in item.ratings ?? [] {
      guard let value = rating.value, value > 0 else { continue }
      let image = rating.image ?? ""
      if image.hasPrefix("imdb://"), let votes = item.imdbRatingCount, votes > 0 {
        meta.relayedIMDbRating = value
        meta.relayedIMDbVotes = votes
      } else if image.hasPrefix("rottentomatoes://") {
        // Plex keeps Rotten Tomatoes on 0…10; the app's Tomatometer is a percentage.
        let kind: ExternalRating.Kind = rating.type == "audience" ? .rottenTomatoesAudience : .rottenTomatoes
        if !external.contains(where: { $0.kind == kind }) {
          external.append(ExternalRating(kind: kind, value: (value * 10).rounded()))
        }
      }
    }
    meta.externalRatings = external
    if let csm = item.commonSenseMedia?.first, let summary = commonSense(csm) {
      meta.commonSense = summary
    }
    if let page = item.publicPagesURL.flatMap(URL.init(string:)) {
      meta.externalLinks = [ExternalLink(site: .plex, url: page)]
    }
  }

  static func commonSense(_ dto: PlexCommonSenseDTO) -> CommonSenseMedia? {
    let official = dto.ageRatings?.first { $0.type == "official" } ?? dto.ageRatings?.first
    let topics = (dto.topics ?? []).compactMap { topic -> CommonSenseMedia.Topic? in
      guard let label = text(topic.label) else { return nil }
      return CommonSenseMedia.Topic(label: label, rating: topic.rating ?? 0,
                                    isPositive: topic.positive ?? false, text: text(topic.tag))
    }
    let result = CommonSenseMedia(
      age: official?.age,
      stars: official?.rating,
      parentsAge: dto.ageRatings?.first { $0.type == "adult" }?.age,
      kidsAge: dto.ageRatings?.first { $0.type == "child" }?.age,
      oneLiner: text(dto.oneLiner),
      parentsNeedToKnow: text(dto.parentsNeedToKnow),
      anyGood: text(dto.anyGood),
      topics: topics,
      talkingPoints: (dto.talkingPoints ?? []).compactMap { text($0.tag) })
    return result.isEmpty ? nil : result
  }

  static func text(_ raw: String?) -> String? {
    guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
    return raw
  }

  // MARK: - HTTP

  /// The body of a 200, cached a day; nil on anything else, with the reason in the log.
  /// A 404 is kept as a miss; a refused token or a network error is not kept.
  private func get(_ url: URL, key: String, token: String, endpoint: String,
                   into meta: inout TitleMetadata) async -> Data? {
    let start = ContinuousClock().now
    let status = StatusBox()
    let entry = await cache.deduped(key: key, ttl: Self.ttl) { [session, access] in
      var request = URLRequest(url: url, timeoutInterval: 12)
      request.setValue("application/json", forHTTPHeaderField: "Accept")
      request.setValue("KinoPub", forHTTPHeaderField: "X-Plex-Product")
      request.setValue(access.plexClientIdentifier, forHTTPHeaderField: "X-Plex-Client-Identifier")
      request.setValue(token, forHTTPHeaderField: "X-Plex-Token")
      guard let (data, response) = try? await session.data(for: request) else { return nil }
      let code = (response as? HTTPURLResponse)?.statusCode ?? 0
      status.code = code
      if code == 200 { return MetadataCache.Entry(payload: data) }
      if code == 404 { return MetadataCache.Entry(payload: Data(), isNegative: true) }
      return nil
    }
    let elapsed = MetadataTiming.milliseconds(since: start)
    let ok = entry.map { !$0.isNegative } ?? false
    let body: String
    if let entry, !entry.isNegative {
      body = String(data: entry.payload.prefix(32 * 1024), encoding: .utf8) ?? ""
    } else if entry != nil {
      body = "Plex does not know this title (404)."
    } else if let code = status.code {
      body = code == 401 || code == 403
        ? "HTTP \(code) — the Plex sign-in was refused (sign in again), or this needs Plex Pass."
        : "HTTP \(code)."
    } else {
      body = "No response — network error."
    }
    meta.debugLog.append(SourceDebugEntry(source: .plex, endpoint: endpoint, url: url.absoluteString,
                                          proxied: false, succeeded: ok, responseBody: body,
                                          elapsedMilliseconds: elapsed))
    return ok ? entry?.payload : nil
  }

  private final class StatusBox: @unchecked Sendable {
    var code: Int?
  }
}

// MARK: - DTO (Plex Discover / metadata provider, JSON with Accept: application/json)

struct PlexContainerDTO: Decodable {
  struct Container: Decodable {
    let metadata: [PlexMetadataDTO]?
    let commonSenseMedia: [PlexCommonSenseDTO]?

    enum CodingKeys: String, CodingKey {
      case metadata = "Metadata"
      case commonSenseMedia = "CommonSenseMedia"
    }
  }

  let mediaContainer: Container?

  enum CodingKeys: String, CodingKey {
    case mediaContainer = "MediaContainer"
  }
}

struct PlexMetadataDTO: Decodable {
  struct Rating: Decodable {
    let image: String?
    let type: String?
    let value: Double?

    enum CodingKeys: String, CodingKey { case image, type, value }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      image = try? container.decode(String.self, forKey: .image)
      type = try? container.decode(String.self, forKey: .type)
      // A number on some titles, a string on others (Plozz).
      if let number = try? container.decode(Double.self, forKey: .value) {
        value = number
      } else {
        value = (try? container.decode(String.self, forKey: .value)).flatMap(Double.init)
      }
    }
  }

  let ratingKey: String?
  let contentRating: String?
  let imdbRatingCount: Int?
  let publicPagesURL: String?
  let ratings: [Rating]?
  let commonSenseMedia: [PlexCommonSenseDTO]?

  enum CodingKeys: String, CodingKey {
    case ratingKey, contentRating, imdbRatingCount, publicPagesURL
    case ratings = "Rating"
    case commonSenseMedia = "CommonSenseMedia"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    ratingKey = try? container.decode(String.self, forKey: .ratingKey)
    contentRating = try? container.decode(String.self, forKey: .contentRating)
    imdbRatingCount = try? container.decode(Int.self, forKey: .imdbRatingCount)
    publicPagesURL = try? container.decode(String.self, forKey: .publicPagesURL)
    ratings = try? container.decode([Rating].self, forKey: .ratings)
    commonSenseMedia = try? container.decode([PlexCommonSenseDTO].self, forKey: .commonSenseMedia)
  }
}

struct PlexCommonSenseDTO: Decodable {
  struct AgeRating: Decodable {
    let age: Int?
    let rating: Double?
    let type: String?

    enum CodingKeys: String, CodingKey { case age, rating, type }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      age = (try? container.decode(Int.self, forKey: .age))
        ?? (try? container.decode(String.self, forKey: .age)).flatMap { Int($0.filter(\.isNumber)) }
      rating = try? container.decode(Double.self, forKey: .rating)
      type = try? container.decode(String.self, forKey: .type)
    }
  }

  struct Topic: Decodable {
    let label: String?
    let positive: Bool?
    let rating: Double?
    let tag: String?
  }

  struct Tag: Decodable {
    let tag: String?
  }

  let oneLiner: String?
  let parentsNeedToKnow: String?
  let anyGood: String?
  let ageRatings: [AgeRating]?
  let topics: [Topic]?
  let talkingPoints: [Tag]?

  enum CodingKeys: String, CodingKey {
    case oneLiner, parentsNeedToKnow, anyGood
    case ageRatings = "AgeRating"
    case topics = "ParentalAdvisoryTopic"
    case talkingPoints = "TalkingPoint"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    oneLiner = try? container.decode(String.self, forKey: .oneLiner)
    parentsNeedToKnow = try? container.decode(String.self, forKey: .parentsNeedToKnow)
    anyGood = try? container.decode(String.self, forKey: .anyGood)
    ageRatings = try? container.decode([AgeRating].self, forKey: .ageRatings)
    topics = try? container.decode([Topic].self, forKey: .topics)
    talkingPoints = try? container.decode([Tag].self, forKey: .talkingPoints)
  }
}
