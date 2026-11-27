import Foundation
import Testing
@testable import KinoPubBackend

struct TraktRepliesServiceTests {
  @Test func readsReplyPagesWithTraktHeaders() async throws {
    let session = URLSessionMock()
    let response = try #require(HTTPURLResponse(
      url: URL(string: "https://api.trakt.tv/comments/58/replies")!, statusCode: 200, httpVersion: nil,
      headerFields: ["X-Pagination-Page-Count": "2"]
    ))
    let first = """
      [{"id":59,"comment":"First reply","created_at":"2026-07-21T12:30:00.000Z",
        "user":{"name":"FrameByFrame","username":"frames"}}]
      """
    let second = """
      [{"id":60,"comment":"[spoiler]Plot[/spoiler]","created_at":"2026-07-22T12:30:00Z",
        "user":{"name":"","username":"viewer"}}]
      """
    session.results = [(Data(first.utf8), response, nil), (Data(second.utf8), response, nil)]
    let service = TraktRepliesServiceImpl(clientID: { "fixture-client" }, session: session)

    let replies = try await service.replies(to: 58)
    #expect(replies.map(\.id) == [59, 60])
    #expect(replies.map(\.author) == ["FrameByFrame", "viewer"])
    #expect(replies.first?.text == "First reply")
    #expect(replies.allSatisfy { $0.postedAt != nil })
    #expect(replies.last?.isSpoiler == true)
    #expect(session.requestCount == 2)
    let request = try #require(session.lastRequest)
    #expect(request.url?.host == "api.trakt.tv")
    #expect(request.url?.path == "/comments/58/replies")
    #expect(request.url?.query?.contains("page=2") == true)
    #expect(request.httpMethod == "GET")
    #expect(request.value(forHTTPHeaderField: "trakt-api-key") == "fixture-client")
    #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
  }

  @Test func skipsTheRequestWhenTraktIsDisabled() async throws {
    let session = URLSessionMock()
    let service = TraktRepliesServiceImpl(clientID: { nil }, session: session)
    let replies = try await service.replies(to: 58)
    #expect(replies.isEmpty)
    #expect(session.requestCount == 0)
  }
}
