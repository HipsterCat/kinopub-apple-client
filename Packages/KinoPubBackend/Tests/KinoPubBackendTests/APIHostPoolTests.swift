//
//  APIHostPoolTests.swift
//  KinoPubBackendTests
//

import XCTest
@testable import KinoPubBackend

/// Answers per host: a status, or a transport error. Records which URLs were asked.
private final class HostRoutingSession: URLSessionProtocol, @unchecked Sendable {
  enum Reply { case status(Int), error(URLError.Code) }
  var replies: [String: Reply] = [:]
  private(set) var asked: [URL] = []

  func data(for request: URLRequest) async throws -> (Data, URLResponse) {
    let url = request.url!
    asked.append(url)
    let key = url.host! + (url.path.hasPrefix("/api/") ? "/api" : "")
    switch replies[key] ?? .status(200) {
    case .error(let code):
      // As `URLSessionImpl` throws it.
      throw APIClientError.networkError(URLError(code))
    case .status(let code):
      let response = HTTPURLResponse(url: url, statusCode: code, httpVersion: nil, headerFields: nil)!
      return (Data(#"{"user":{"username":"u"}}"#.utf8), response)
    }
  }
}

private struct Probe: Decodable {}

private struct ReadRequest: Endpoint {
  var path: String { "/v1/user" }
  var method: String { "GET" }
  var headers: [String: String]? { nil }
  var parameters: [String: Any]? { nil }
}

private struct WriteRequest: Endpoint {
  var path: String { "/v1/bookmarks/toggle-item" }
  var method: String { "POST" }
  var headers: [String: String]? { nil }
  var parameters: [String: Any]? { ["item": 1] }
}

final class APIHostPoolTests: XCTestCase {

  private let suite = "APIHostPoolTests"

  override func setUp() {
    super.setUp()
    UserDefaults().removePersistentDomain(forName: suite)
  }

  private func makeClient(_ session: HostRoutingSession) -> (APIClient, APIHostPool) {
    let pool = APIHostPool(primary: URL(string: "https://api.service-kp.com")!, defaults: .suite(suite))
    let client = APIClient(baseUrl: "https://api.service-kp.com", session: session, hosts: pool)
    return (client, pool)
  }

  func testConfiguredPrimaryComesBeforeTheFallbacks() {
    let pool = APIHostPool(primary: URL(string: "https://api.service-kp.com/")!, defaults: .suite(suite))
    XCTAssertEqual(pool.hosts.map(\.label), [
      "api.service-kp.com", "api.srvkp.com", "kino.watch/api", "api.boramoraboom.ru", "api.alador.space"
    ])
    XCTAssertEqual(pool.current.label, "api.service-kp.com")
  }

  func testPrefixedHostKeepsItsPrefix() throws {
    let builder = RequestBuilder(baseURL: URL(string: "https://api.service-kp.com")!)
    let request = try XCTUnwrap(builder.build(with: ReadRequest(), host: URL(string: "https://kino.watch/api")!))
    XCTAssertEqual(request.url?.absoluteString, "https://kino.watch/api/v1/user")
  }

  func testGatewayFailureMovesAReadOnAndTheWorkingHostSticks() async throws {
    let session = HostRoutingSession()
    session.replies["api.service-kp.com"] = .status(502)
    let (client, pool) = makeClient(session)

    _ = try await client.performRequest(with: ReadRequest(), decodingType: Probe.self)
    XCTAssertEqual(session.asked.map { $0.host! }, ["api.service-kp.com", "api.srvkp.com"])
    XCTAssertEqual(pool.current.label, "api.srvkp.com")

    // The next request starts on the host that worked.
    _ = try await client.performRequest(with: ReadRequest(), decodingType: Probe.self)
    XCTAssertEqual(session.asked.last?.host, "api.srvkp.com")
    XCTAssertEqual(session.asked.count, 3)

    // And so does the next launch.
    let relaunched = APIHostPool(primary: URL(string: "https://api.service-kp.com")!, defaults: .suite(suite))
    XCTAssertEqual(relaunched.current.label, "api.srvkp.com")
  }

  func testUnreachableHostMovesOnToTheNext() async throws {
    let session = HostRoutingSession()
    session.replies["api.service-kp.com"] = .error(.cannotFindHost)
    session.replies["api.srvkp.com"] = .error(.cannotConnectToHost)
    let (client, pool) = makeClient(session)

    _ = try await client.performRequest(with: ReadRequest(), decodingType: Probe.self)
    XCTAssertEqual(session.asked.last?.absoluteString, "https://kino.watch/api/v1/user")
    XCTAssertEqual(pool.current.label, "kino.watch/api")
    let snapshot = pool.snapshot()
    XCTAssertEqual(snapshot.outcomes["https://api.service-kp.com"]?.kind, .failed(reason: "host not found"))
    XCTAssertNotNil(snapshot.lastSwitch)
  }

  func testAWriteIsNeverSentTwiceAfterAGatewayAnswer() async {
    let session = HostRoutingSession()
    session.replies["api.service-kp.com"] = .status(502)
    let (client, pool) = makeClient(session)

    do {
      _ = try await client.performRequest(with: WriteRequest(), decodingType: Probe.self)
      XCTFail("a 502 is an error")
    } catch {}
    XCTAssertEqual(session.asked.count, 1)
    XCTAssertEqual(pool.current.label, "api.service-kp.com")
  }

  func testAToggleOnGetIsNotRepeatable() {
    XCTAssertFalse(ToggleWatchingRequest(id: 1, video: 1, season: nil).isRepeatable)
    XCTAssertTrue(ReadRequest().isRepeatable)
  }

  func testOnlyCatalogueReadsUseTheNewMirrorsAndTheWinningMirrorStaysSelected() async throws {
    let session = HostRoutingSession()
    let (client, pool) = makeClient(session)
    let established = ["api.service-kp.com", "api.srvkp.com", "kino.watch/api"]
    for host in established + ["api.boramoraboom.ru"] { session.replies[host] = .status(503) }

    _ = try await client.performRequest(with: ReadRequest(), decodingType: Probe.self)
    XCTAssertEqual(pool.current.label, "api.alador.space")
    XCTAssertEqual(session.asked.last?.host, "api.alador.space")
    let relaunched = APIHostPool(defaults: .suite(suite))
    XCTAssertEqual(relaunched.current.label, "api.alador.space")

    let writesAndOAuth: [any Endpoint] = [
      WriteRequest(), VoteRequest(id: 1, like: 1), MarkTimeRequest(id: 1, time: 30),
      ToggleWatchingRequest(id: 1, video: 1, season: nil),
      RefreshTokenRequest(clientID: "fixture", clientSecret: "fixture", refreshToken: "fixture")
    ]
    for request in writesAndOAuth {
      XCTAssertEqual(pool.attemptOrder(for: request).map(\.label), established)
    }
    session.replies["api.service-kp.com"] = .status(200)
    _ = try await client.performRequest(with: writesAndOAuth[0], decodingType: Probe.self)
    XCTAssertEqual(session.asked.last?.host, "api.service-kp.com")
    XCTAssertEqual(pool.current.label, "api.alador.space")
  }

  func testAWriteMovesOnWhenTheHostWasNeverReached() async throws {
    let session = HostRoutingSession()
    session.replies["api.service-kp.com"] = .error(.cannotFindHost)
    let (client, _) = makeClient(session)

    _ = try await client.performRequest(with: WriteRequest(), decodingType: Probe.self)
    XCTAssertEqual(session.asked.map { $0.host! }, ["api.service-kp.com", "api.srvkp.com"])
  }

  func testOfflineDoesNotWalkTheHosts() async {
    let session = HostRoutingSession()
    session.replies["api.service-kp.com"] = .error(.notConnectedToInternet)
    let (client, pool) = makeClient(session)

    do {
      _ = try await client.performRequest(with: ReadRequest(), decodingType: Probe.self)
      XCTFail("offline is an error")
    } catch {}
    XCTAssertEqual(session.asked.count, 1)
    XCTAssertEqual(pool.current.label, "api.service-kp.com")
  }

  func testEveryHostFailingLeavesTheCurrentOneAlone() async {
    let session = HostRoutingSession()
    let (client, pool) = makeClient(session)
    for host in pool.hosts { session.replies[host.label] = .status(502) }

    do {
      _ = try await client.performRequest(with: ReadRequest(), decodingType: Probe.self)
      XCTFail("502 everywhere is an error")
    } catch {}
    XCTAssertEqual(session.asked.count, pool.hosts.count)
    XCTAssertEqual(pool.current.label, "api.service-kp.com")
  }

  func testTheBranchEndpointKeepsItsOwnHost() async throws {
    let session = HostRoutingSession()
    let (client, _) = makeClient(session)
    _ = try? await client.performRequest(with: ItemCollectionsRequest(itemId: 24), decodingType: Probe.self)
    XCTAssertEqual(session.asked.first?.absoluteString, "https://api.srvkp.com/api2/v1.1/items/collections/24")
  }
}
