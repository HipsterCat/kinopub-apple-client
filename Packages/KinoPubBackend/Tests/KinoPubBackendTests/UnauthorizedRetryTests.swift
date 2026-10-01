import XCTest
@testable import KinoPubBackend

/// Content 401 must await recovery and retry once — not fail the caller's request
/// while a refresh is still in flight.
final class UnauthorizedRetryTests: XCTestCase {

  private final class Recoverer: UnauthorizedRequestRecovering, @unchecked Sendable {
    var recoverCalls = 0
    var shouldRecover = true

    func recoverFromUnauthorized() async -> Bool {
      recoverCalls += 1
      return shouldRecover
    }
  }

  private var sessionMock: URLSessionMock!
  private var apiClient: APIClient!
  private var recoverer: Recoverer!

  override func setUp() {
    super.setUp()
    sessionMock = URLSessionMock()
    apiClient = APIClient(baseUrl: "https://api.example.com", session: sessionMock)
    recoverer = Recoverer()
    UnauthorizedRequestRecovery.shared.recoverer = recoverer
  }

  override func tearDown() {
    UnauthorizedRequestRecovery.shared.recoverer = nil
    apiClient = nil
    sessionMock = nil
    recoverer = nil
    super.tearDown()
  }

  func testContent401_RecoversAndRetries() async throws {
    let unauthorized = HTTPURLResponse(
      url: URL(string: "https://api.example.com/v1/items/1")!,
      statusCode: 401,
      httpVersion: nil,
      headerFields: nil
    )
    let ok = HTTPURLResponse(
      url: URL(string: "https://api.example.com/v1/items/1")!,
      statusCode: 200,
      httpVersion: nil,
      headerFields: nil
    )
    sessionMock.results = [
      (Data(), unauthorized, nil),
      (#"{"status":200}"#.data(using: .utf8), ok, nil)
    ]

    struct StatusOnly: Decodable { let status: Int }
    let response: StatusOnly = try await apiClient.performRequest(
      with: RequestData(path: "/v1/items/1", method: "GET"),
      decodingType: StatusOnly.self
    )

    XCTAssertEqual(response.status, 200)
    XCTAssertEqual(recoverer.recoverCalls, 1)
    XCTAssertEqual(sessionMock.requestCount, 2)
  }

  func testContent401_WhenRecoveryFails_DoesNotRetry() async {
    let unauthorized = HTTPURLResponse(
      url: URL(string: "https://api.example.com/v1/items/1")!,
      statusCode: 401,
      httpVersion: nil,
      headerFields: nil
    )
    sessionMock.results = [(Data(), unauthorized, nil)]
    recoverer.shouldRecover = false

    do {
      struct StatusOnly: Decodable { let status: Int }
      let _: StatusOnly = try await apiClient.performRequest(
        with: RequestData(path: "/v1/items/1", method: "GET"),
        decodingType: StatusOnly.self
      )
      XCTFail("Expected httpStatus(401)")
    } catch let error as APIClientError {
      guard case .httpStatus(let code, _) = error else {
        return XCTFail("Expected httpStatus, got \(error)")
      }
      XCTAssertEqual(code, 401)
      XCTAssertEqual(recoverer.recoverCalls, 1)
      XCTAssertEqual(sessionMock.requestCount, 1)
    } catch {
      XCTFail("Unexpected \(error)")
    }
  }

  func testOAuth401_DoesNotAttemptRecovery() async {
    let unauthorized = HTTPURLResponse(
      url: URL(string: "https://api.example.com/oauth2/token")!,
      statusCode: 401,
      httpVersion: nil,
      headerFields: nil
    )
    sessionMock.results = [(Data(), unauthorized, nil)]

    do {
      let _: AccessToken = try await apiClient.performRequest(
        with: RequestData(path: "/oauth2/token", method: "POST"),
        decodingType: AccessToken.self
      )
      XCTFail("Expected failure")
    } catch {
      XCTAssertEqual(recoverer.recoverCalls, 0)
      XCTAssertEqual(sessionMock.requestCount, 1)
    }
  }
}
