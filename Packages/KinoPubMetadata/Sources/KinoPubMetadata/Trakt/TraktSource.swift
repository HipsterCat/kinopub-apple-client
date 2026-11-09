import Foundation

/// The app's Trakt Client ID, read on every request: nil while the viewer has Trakt's
/// ratings and reviews switched off in Settings › Integrations.
public protocol TraktAccessProviding: Sendable {
  func traktClientID() -> String?
}

/// Trakt as a metadata source: its own score, the scores it relays from Rotten Tomatoes,
/// Metacritic, Letterboxd and MyAnimeList (`/ratings?extended=all`), and its users'
/// comments as reviews. Public data: the Client ID alone, no sign-in.
///
/// Trakt takes an IMDb id wherever it takes its own, so there is no lookup step. Three
/// calls per title — summary (for the page link), ratings, comments — each cached; the
/// unauthenticated limit is 500 calls per 5 minutes per Client ID and address.
///
/// Trakt's API terms ask for "uses Trakt but is not endorsed or certified by Trakt"
/// beside the data: Settings › Integrations › Trakt carries it.
public final class TraktSource: MetadataSource, @unchecked Sendable {
  public let id: MetadataSourceID = .trakt

  public var isConfigured: Bool { access.traktClientID() != nil }

  public static let baseURL = URL(string: "https://api.trakt.tv")!
  public static let webBaseURL = URL(string: "https://trakt.tv")!

  private let access: TraktAccessProviding
  private let client: MetadataHTTPClient
  private let cache: MetadataCache
  /// The app's language first among the comments.
  private let language: String

  private static let summaryTTL: TimeInterval = 60 * 60 * 24 * 30
  private static let ratingsTTL: TimeInterval = 60 * 60 * 24
  private static let commentsTTL: TimeInterval = 60 * 60 * 24
  /// What a title page shows; the rest stays on Trakt.
  static let reviewLimit = 20

  public init(access: TraktAccessProviding,
              language: String = Locale.current.language.languageCode?.identifier ?? "ru",
              client: MetadataHTTPClient = MetadataHTTPClient(),
              cache: MetadataCache = MetadataCache()) {
    self.access = access
    self.language = language
    self.client = client
    self.cache = cache
  }

  // MARK: - MetadataSource

  public func titleMetadata(for identity: MediaIdentity) async throws -> TitleMetadata? {
    guard let clientID = access.traktClientID() else { throw MetadataError.notConfigured }
    var meta = TitleMetadata()
    meta.attribution.insert(.trakt)
    guard let imdb = identity.imdb, !imdb.isEmpty else {
      meta.debugLog = [SourceDebugEntry(source: .trakt, endpoint: "summary", url: "(no imdb id on this title)",
                                        proxied: false, succeeded: false,
                                        responseBody: "Skipped — no IMDb id from kino.pub.")]
      return meta
    }
    let kind = identity.isSeries ? "shows" : "movies"
    let headers = Self.headers(clientID: clientID)

    async let summaryCall = fetch(path: "/\(kind)/\(imdb)", query: [],
                                  key: "trakt/summary/\(kind)/\(imdb)", ttl: Self.summaryTTL,
                                  headers: headers, endpoint: "summary")
    async let ratingsCall = fetch(path: "/\(kind)/\(imdb)/ratings",
                                  query: [URLQueryItem(name: "extended", value: "all")],
                                  key: "trakt/ratings/\(kind)/\(imdb)", ttl: Self.ratingsTTL,
                                  headers: headers, endpoint: "ratings")
    async let commentsCall = fetch(path: "/\(kind)/\(imdb)/comments/likes",
                                   query: [URLQueryItem(name: "limit", value: "50")],
                                   key: "trakt/comments/likes/\(kind)/\(imdb)", ttl: Self.commentsTTL,
                                   headers: headers, endpoint: "comments")
    let (summary, ratings, comments) = await (summaryCall, ratingsCall, commentsCall)
    meta.debugLog = [summary.debug, ratings.debug, comments.debug]

    if let data = summary.data, let dto = try? client.decode(TraktSummaryDTO.self, from: data),
       let slug = dto.ids?.slug, !slug.isEmpty {
      meta.traktURL = Self.webBaseURL.appending(path: "\(kind)/\(slug)")
    }
    if let data = ratings.data, let dto = try? client.decode(TraktRatingsDTO.self, from: data) {
      meta.externalRatings = Self.ratings(from: dto, traktURL: meta.traktURL)
    }
    if let data = comments.data, let dto = try? client.decode([TraktCommentDTO].self, from: data) {
      meta.reviews = Self.reviews(from: dto, preferredLanguage: language)
    }
    return meta
  }

  // MARK: - Mapping

  static func ratings(from dto: TraktRatingsDTO, traktURL: URL?) -> [ExternalRating] {
    var list: [ExternalRating] = []
    func url(_ link: String?) -> URL? { link.flatMap(URL.init(string:)) }
    // A score with nobody behind it is not a score: Trakt returns `rating: 0, votes: 0`
    // for a title nobody rated, and `null` for an outside source it has no figure from.
    if let trakt = dto.trakt ?? dto.ownFallback, (trakt.votes ?? 0) > 0, let value = trakt.rating, value > 0 {
      list.append(ExternalRating(kind: .trakt, value: value, votes: trakt.votes, url: traktURL))
    }
    if let rt = dto.rottenTomatoes {
      if let value = rt.rating, value > 0 {
        list.append(ExternalRating(kind: .rottenTomatoes, value: value, state: rt.state, url: url(rt.link)))
      }
      if let value = rt.userRating, value > 0 {
        list.append(ExternalRating(kind: .rottenTomatoesAudience, value: value, state: rt.userState,
                                   url: url(rt.link)))
      }
    }
    if let meta = dto.metascore, let value = meta.rating, value > 0 {
      list.append(ExternalRating(kind: .metacritic, value: value, url: url(meta.link)))
    }
    if let lb = dto.letterboxd, let value = lb.rating, value > 0 {
      list.append(ExternalRating(kind: .letterboxd, value: value, votes: lb.votes, url: url(lb.link)))
    }
    if let mal = dto.mal, let value = mal.rating, value > 0 {
      list.append(ExternalRating(kind: .myAnimeList, value: value, votes: mal.votes, url: url(mal.link)))
    }
    return list
  }

  /// Trakt's comments, most liked first, as reviews. Spoilers are left out — the whole
  /// comment flagged, or one with a `[spoiler]` tag inside — and so are one-liners
  /// that are not reviews of anything. The app's language comes first.
  static func reviews(from comments: [TraktCommentDTO], preferredLanguage: String) -> [Review] {
    let kept = comments.filter { comment in
      let text = comment.comment.trimmingCharacters(in: .whitespacesAndNewlines)
      return !(comment.spoiler ?? false)
        && !text.localizedCaseInsensitiveContains("[spoiler]")
        && text.count >= 40
    }
    let preferred = preferredLanguage.lowercased()
    let ordered = kept.enumerated().sorted { lhs, rhs in
      let l = lhs.element.language?.lowercased() == preferred ? 0 : 1
      let r = rhs.element.language?.lowercased() == preferred ? 0 : 1
      return l != r ? l < r : lhs.offset < rhs.offset
    }.map(\.element)
    return ordered.prefix(reviewLimit).map(review(from:))
  }

  static func review(from comment: TraktCommentDTO) -> Review {
    let author = comment.user?.name.flatMap { $0.isEmpty ? nil : $0 } ?? comment.user?.username ?? "Trakt"
    return Review(
      author: author,
      title: "",
      body: comment.comment.trimmingCharacters(in: .whitespacesAndNewlines),
      sentiment: sentiment(forUserRating: comment.userRating),
      date: comment.createdAt,
      postedAt: comment.createdAt.flatMap(parseDate),
      helpfulVotes: comment.likes ?? 0,
      sourceId: comment.id,
      source: .trakt,
      language: comment.language
    )
  }

  /// The author's own score of the title (1…10) is the review's tone, in Kinopoisk's
  /// words so the cards colour it the same way. No score, no tone.
  static func sentiment(forUserRating rating: Int?) -> String? {
    guard let rating, rating > 0 else { return nil }
    switch rating {
    case 7...: return "POSITIVE"
    case ...4: return "NEGATIVE"
    default: return "NEUTRAL"
    }
  }

  private static func parseDate(_ raw: String) -> Date? {
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = fractional.date(from: raw) { return date }
    return ISO8601DateFormatter().date(from: raw)
  }

  // MARK: - HTTP

  static func headers(clientID: String) -> [String: String] {
    ["trakt-api-version": "2", "trakt-api-key": clientID, "Content-Type": "application/json"]
  }

  private struct Fetched {
    let data: Data?
    let debug: SourceDebugEntry
  }

  /// One cached GET. A 404 is cached as a miss (Trakt does not know the title); a
  /// network error or a 5xx is not cached.
  private func fetch(path: String, query: [URLQueryItem], key: String, ttl: TimeInterval,
                     headers: [String: String], endpoint: String) async -> Fetched {
    var components = URLComponents(url: Self.baseURL.appending(path: path), resolvingAgainstBaseURL: false)
    components?.queryItems = query.isEmpty ? nil : query
    guard let url = components?.url else {
      return Fetched(data: nil, debug: SourceDebugEntry(source: .trakt, endpoint: endpoint, url: path,
                                                        proxied: false, succeeded: false, responseBody: "Bad URL."))
    }
    let start = ContinuousClock().now
    let entry = await cache.deduped(key: key, ttl: ttl) { [client] in
      do {
        let data = try await client.getData(url: url, headers: headers)
        return MetadataCache.Entry(payload: data)
      } catch MetadataError.httpStatus(404) {
        return MetadataCache.Entry(payload: Data(), isNegative: true)
      } catch {
        return nil
      }
    }
    let elapsed = MetadataTiming.milliseconds(since: start)
    guard let entry else {
      return Fetched(data: nil, debug: SourceDebugEntry(
        source: .trakt, endpoint: endpoint, url: url.absoluteString, proxied: false, succeeded: false,
        responseBody: "No response — network error or Trakt refused the request.", elapsedMilliseconds: elapsed))
    }
    guard !entry.isNegative else {
      return Fetched(data: nil, debug: SourceDebugEntry(
        source: .trakt, endpoint: endpoint, url: url.absoluteString, proxied: false, succeeded: false,
        responseBody: "Trakt does not know this title (404).", elapsedMilliseconds: elapsed))
    }
    let body = String(data: entry.payload.prefix(64 * 1024), encoding: .utf8) ?? "(\(entry.payload.count) bytes)"
    return Fetched(data: entry.payload, debug: SourceDebugEntry(
      source: .trakt, endpoint: endpoint, url: url.absoluteString, proxied: false, succeeded: true,
      responseBody: body, elapsedMilliseconds: elapsed))
  }
}

// MARK: - DTOs (trakt/trakt-api contracts: ratingsResponseSchema, commentResponseSchema)

struct TraktSummaryDTO: Decodable {
  struct IDs: Decodable {
    let trakt: Int?
    let slug: String?
  }
  let ids: IDs?
}

struct TraktRatingsDTO: Decodable {
  struct Own: Decodable {
    let rating: Double?
    let votes: Int?
  }
  struct External: Decodable {
    let rating: Double?
    let votes: Int?
    let link: String?
  }
  struct RottenTomatoes: Decodable {
    let rating: Double?
    let state: String?
    let userRating: Double?
    let userState: String?
    let link: String?

    enum CodingKeys: String, CodingKey {
      case rating, state, link
      case userRating = "user_rating"
      case userState = "user_state"
    }
  }

  /// `extended=all` nests Trakt's own score under `trakt`; the plain response has it at
  /// the top level.
  let rating: Double?
  let votes: Int?
  let trakt: Own?
  let metascore: External?
  let rottenTomatoes: RottenTomatoes?
  let letterboxd: External?
  let mal: External?

  var ownFallback: Own? { rating == nil && votes == nil ? nil : Own(rating: rating, votes: votes) }

  enum CodingKeys: String, CodingKey {
    case rating, votes, trakt, metascore, letterboxd, mal
    case rottenTomatoes = "rotten_tomatoes"
  }
}

struct TraktCommentDTO: Decodable {
  struct User: Decodable {
    let username: String?
    let name: String?
  }
  let id: Int?
  let comment: String
  let spoiler: Bool?
  let review: Bool?
  let likes: Int?
  let language: String?
  let userRating: Int?
  let createdAt: String?
  let user: User?

  enum CodingKeys: String, CodingKey {
    case id, comment, spoiler, review, likes, language, user
    case userRating = "user_rating"
    case createdAt = "created_at"
  }
}
