import Foundation

public struct TraktCommentReply: Identifiable, Equatable, Sendable {
  public let id: Int
  public let author: String?
  public let text: String
  public let postedAt: Date?
  public let isSpoiler: Bool

  public init(id: Int, author: String?, text: String, postedAt: Date? = nil, isSpoiler: Bool = false) {
    self.id = id
    self.author = author
    self.text = text
    self.postedAt = postedAt
    self.isSpoiler = isSpoiler
  }
}

public protocol TraktRepliesService: Sendable {
  func replies(to commentID: Int) async throws -> [TraktCommentReply]
}

/// Trakt's public replies use only a client ID. This transport has no kino.pub auth plugins.
public struct TraktRepliesServiceImpl: TraktRepliesService {
  private let clientID: @Sendable () -> String?
  private let session: any URLSessionProtocol
  private let builder = RequestBuilder(baseURL: URL(string: "https://api.trakt.tv")!)

  public init(clientID: @escaping @Sendable () -> String?,
              session: any URLSessionProtocol = URLSessionImpl(session: .shared)) {
    self.clientID = clientID
    self.session = session
  }

  public func replies(to commentID: Int) async throws -> [TraktCommentReply] {
    guard commentID > 0, let clientID = clientID(), !clientID.isEmpty else { return [] }
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    var replies: [TraktCommentReply] = []
    var seen: Set<Int> = []
    var page = 1

    while true {
      try Task.checkCancellation()
      guard var request = builder.build(with: RepliesEndpoint(commentID: commentID, page: page, clientID: clientID)) else {
        throw APIClientError.invalidUrlParams
      }
      request.timeoutInterval = 15
      let (data, response) = try await session.data(for: request)
      guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
      guard (200..<300).contains(http.statusCode) else { throw APIClientError.httpStatus(http.statusCode, data: nil) }
      let comments = try decoder.decode([ReplyDTO].self, from: data)
      let next = comments.filter { seen.insert($0.id).inserted }
      replies += next.map(\.reply).filter { !$0.text.isEmpty || $0.isSpoiler }
      let pageCount = http.value(forHTTPHeaderField: "X-Pagination-Page-Count").flatMap(Int.init) ?? page
      guard !next.isEmpty, page < pageCount else { return replies }
      page += 1
    }
  }

  private struct RepliesEndpoint: Endpoint {
    let commentID: Int
    let page: Int
    let clientID: String

    var path: String { "/comments/\(commentID)/replies" }
    var method: String { "GET" }
    var parameters: [String: Any]? { ["page": page, "limit": 100] }
    var headers: [String: String]? {
      ["trakt-api-key": clientID, "trakt-api-version": "2", "Content-Type": "application/json"]
    }
  }

  private struct ReplyDTO: Decodable {
    struct User: Decodable {
      let name: String?
      let username: String?
    }

    let id: Int
    let comment: String
    let createdAt: String?
    let spoiler: Bool?
    let user: User?

    var reply: TraktCommentReply {
      let name = [user?.name, user?.username].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .first { !$0.isEmpty }
      let date = createdAt.flatMap { timestamp in
        (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(timestamp))
          ?? (try? Date.ISO8601FormatStyle().parse(timestamp))
      }
      return TraktCommentReply(
        id: id, author: name, text: comment.trimmingCharacters(in: .whitespacesAndNewlines), postedAt: date,
        isSpoiler: spoiler == true || comment.localizedCaseInsensitiveContains("[spoiler]")
      )
    }
  }
}

public struct TraktRepliesServiceMock: TraktRepliesService {
  private let repliesByComment: [Int: [TraktCommentReply]]

  public init(repliesByComment: [Int: [TraktCommentReply]] = [:]) {
    self.repliesByComment = repliesByComment
  }

  public func replies(to commentID: Int) async throws -> [TraktCommentReply] {
    repliesByComment[commentID] ?? []
  }
}
