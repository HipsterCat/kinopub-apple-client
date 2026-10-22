//
//  AuthFlowAndKeychainSyncTests.swift
//  KinoPubAppleClientTests
//

import XCTest
import KinoPubBackend
@testable import KinoPub

@MainActor
final class AuthFlowAndKeychainSyncTests: XCTestCase {

  // MARK: - Test Doubles

  private struct StubConfiguration: Configuration {
    var clientID: String = "test-client-id"
    var clientSecret: String = "test-client-secret"
    var baseURL: String = "https://api.example.com"
    var tmdbProxyBaseURL: String? = nil
  }

  private final class ControllableClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(start: Date = Date(timeIntervalSince1970: 1_700_000_000)) {
      self.current = start
    }

    var now: Date {
      lock.withLock { current }
    }

    func advance(by seconds: TimeInterval) {
      lock.withLock {
        current = current.addingTimeInterval(seconds)
      }
    }
  }

  private final class BackgroundTaskSpy: AuthBackgroundTaskManaging {
    private(set) var beginCount = 0
    private(set) var endCount = 0
    private(set) var isRunning = false
    private var expirationHandler: (@MainActor () -> Void)?

    func beginBackgroundTask(expirationHandler: @escaping @MainActor () -> Void) {
      beginCount += 1
      isRunning = true
      self.expirationHandler = expirationHandler
    }

    func endBackgroundTask() {
      guard isRunning else { return }
      endCount += 1
      isRunning = false
      expirationHandler = nil
    }

    func simulateExpiration() {
      expirationHandler?()
    }
  }

  private final class FeedbackSpy: AuthFeedbackHandling {
    private(set) var prepareCount = 0
    private(set) var authorizedEvents: [Bool] = []

    func prepareForActivation() {
      prepareCount += 1
    }

    func didAuthorize(inBackground: Bool) {
      authorizedEvents.append(inBackground)
    }
  }

  private final class ScriptedAuthService: AuthorizationService, @unchecked Sendable {
    var deviceCodeResponses: [Result<VerificationResponse, Error>] = []
    var tokenResponses: [Result<Void, Error>] = []
    var refreshHandler: (() async throws -> Void)?

    private(set) var fetchDeviceCodeCallCount = 0
    private(set) var polledCodes: [String] = []
    private(set) var logoutCalls: [Bool] = []

    func fetchDeviceCode() async throws -> VerificationResponse {
      fetchDeviceCodeCallCount += 1
      guard !deviceCodeResponses.isEmpty else {
        return VerificationResponse(
          code: "device-\(fetchDeviceCodeCallCount)",
          userCode: "CODE\(fetchDeviceCodeCallCount)",
          verificationUri: "https://kino.pub/device",
          expiresIn: 300,
          interval: 5
        )
      }
      return try deviceCodeResponses.removeFirst().get()
    }

    func fetchToken(by verification: VerificationResponse) async throws {
      polledCodes.append(verification.userCode)
      guard !tokenResponses.isEmpty else {
        throw Self.pendingError
      }
      _ = try tokenResponses.removeFirst().get()
    }

    func refreshToken() async throws {
      try await refreshHandler?()
    }

    func logout() {
      logout(userInitiated: true)
    }

    func logout(userInitiated: Bool) {
      logoutCalls.append(userInitiated)
    }

    static var pendingError: APIClientError {
      let json = #"{"status":400,"error":"authorization_pending"}"#.data(using: .utf8)!
      let backendError = try! JSONDecoder().decode(BackendError.self, from: json)
      return .networkError(backendError)
    }

    static var slowDownError: APIClientError {
      let json = #"{"status":400,"error":"slow_down"}"#.data(using: .utf8)!
      let backendError = try! JSONDecoder().decode(BackendError.self, from: json)
      return .networkError(backendError)
    }

    static var invalidGrantError: APIClientError {
      let json = #"{"status":400,"error":"invalid_grant","error_description":"Expired code"}"#.data(using: .utf8)!
      let backendError = try! JSONDecoder().decode(BackendError.self, from: json)
      return .networkError(backendError)
    }

    static var expiredTokenError: APIClientError {
      let json = #"{"status":400,"error":"expired_token"}"#.data(using: .utf8)!
      let backendError = try! JSONDecoder().decode(BackendError.self, from: json)
      return .networkError(backendError)
    }
  }

  private final class InMemoryKeychainStore: KeychainDataStore {
    var storage: [String: Data] = [:]
    var shouldThrowOnWrite = false
    var shouldThrowOnRead = false
    private(set) var setCallCount = 0

    private struct StoreError: Error {}

    func getData(_ key: String) throws -> Data? {
      if shouldThrowOnRead { throw StoreError() }
      return storage[key]
    }

    func set(_ value: Data, key: String) throws {
      if shouldThrowOnWrite { throw StoreError() }
      setCallCount += 1
      storage[key] = value
    }

    func remove(_ key: String) throws {
      storage.removeValue(forKey: key)
    }

    func removeAll() throws {
      storage.removeAll()
    }
  }

  private final class StubURLSession: URLSessionProtocol {
    var handler: ((URLRequest) async throws -> (Data, URLResponse))?
    private(set) var requestCount = 0

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
      requestCount += 1
      if let handler {
        return try await handler(request)
      }
      throw URLError(.badServerResponse)
    }
  }

  // MARK: - 1. Preserving Active Code Across Background / Foreground

  func testUnexpiredDeviceCodeIsPreservedAcrossBackgroundAndForegroundTransitions() async {
    let clock = ControllableClock()
    let authService = ScriptedAuthService()
    authService.deviceCodeResponses = [
      .success(VerificationResponse(
        code: "dev-1",
        userCode: "KP777",
        verificationUri: "https://kino.pub/device",
        expiresIn: 300,
        interval: 5
      ))
    ]
    authService.tokenResponses = [
      .failure(ScriptedAuthService.pendingError),
      .failure(ScriptedAuthService.pendingError)
    ]

    let authState = AuthState(authService: authService, accessTokenService: AccessTokenServiceMock())
    let bgSpy = BackgroundTaskSpy()
    let feedbackSpy = FeedbackSpy()

    let model = AuthModel(
      authService: authService,
      authState: authState,
      backgroundTaskManager: bgSpy,
      feedbackHandler: feedbackSpy,
      now: { clock.now },
      sleep: { _ in },
      observesSystemLifecycle: false
    )

    await model.requestDeviceCodeIfNeeded()
    XCTAssertEqual(model.deviceCode, "KP777")
    XCTAssertEqual(authService.fetchDeviceCodeCallCount, 1)

    // User copies code and switches to Safari (background).
    model.copyCode()
    XCTAssertEqual(feedbackSpy.prepareCount, 1)

    model.handleDidEnterBackground()
    XCTAssertTrue(model.isInBackground)
    XCTAssertEqual(bgSpy.beginCount, 1)
    XCTAssertTrue(bgSpy.isRunning)

    // Even if a background socket aborts with URLError.networkConnectionLost while switching,
    // the active code must not be discarded or show a false error.
    authService.tokenResponses.insert(.failure(APIClientError.networkError(URLError(.networkConnectionLost))), at: 0)
    let bgPollOutcome = await model.pollOnce()
    XCTAssertEqual(bgPollOutcome, .pending)
    XCTAssertNil(model.errorMessage)
    XCTAssertEqual(model.deviceCode, "KP777")

    // User spends 45 seconds in Safari and returns to the app.
    clock.advance(by: 45)
    await model.handleDidBecomeActive()

    XCTAssertFalse(model.isInBackground)
    XCTAssertFalse(bgSpy.isRunning)
    XCTAssertEqual(bgSpy.endCount, 1)
    XCTAssertEqual(model.deviceCode, "KP777", "Returning from Safari must never regenerate an unexpired code")
    XCTAssertEqual(authService.fetchDeviceCodeCallCount, 1)
    XCTAssertEqual(authService.polledCodes, ["KP777", "KP777"])

    // Re-running requestDeviceCodeIfNeeded (e.g. if SwiftUI re-runs .task) also preserves the code.
    await model.requestDeviceCodeIfNeeded()
    XCTAssertEqual(model.deviceCode, "KP777")
    XCTAssertEqual(authService.fetchDeviceCodeCallCount, 1)
  }

  // MARK: - 2. Immediate Foreground Poll & Completing Auth After Safari Approval

  func testImmediatePollOnForegroundReturnCompletesAuthorizationAndFiresHaptics() async {
    let clock = ControllableClock()
    let authService = ScriptedAuthService()
    authService.deviceCodeResponses = [
      .success(VerificationResponse(
        code: "dev-safari",
        userCode: "AB123",
        verificationUri: "https://kino.pub/device",
        expiresIn: 300,
        interval: 5
      ))
    ]
    // First poll is pending; second poll (when user returns from Safari) succeeds!
    authService.tokenResponses = [
      .failure(ScriptedAuthService.pendingError),
      .success(())
    ]

    let authState = AuthState(authService: authService, accessTokenService: AccessTokenServiceMock())
    let bgSpy = BackgroundTaskSpy()
    let feedbackSpy = FeedbackSpy()

    let model = AuthModel(
      authService: authService,
      authState: authState,
      backgroundTaskManager: bgSpy,
      feedbackHandler: feedbackSpy,
      now: { clock.now },
      sleep: { _ in },
      observesSystemLifecycle: false
    )

    await model.requestDeviceCodeIfNeeded()
    let firstPoll = await model.pollOnce()
    XCTAssertEqual(firstPoll, .pending)
    XCTAssertEqual(authState.phase, .signedOut)

    model.handleDidEnterBackground()
    clock.advance(by: 20)

    // User approved AB123 in Safari and switches back to KinoPub.
    await model.handleDidBecomeActive()

    XCTAssertEqual(authState.phase, .signedIn)
    XCTAssertTrue(authState.didActivateDevice)
    XCTAssertEqual(authService.fetchDeviceCodeCallCount, 1)
    XCTAssertEqual(authService.polledCodes, ["AB123", "AB123"])
    XCTAssertEqual(feedbackSpy.authorizedEvents, [false], "Foreground completion fires haptics with inBackground == false")
    XCTAssertFalse(bgSpy.isRunning)
  }

  func testBackgroundPollSuccessNotifiesInBackgroundAndEndsBackgroundTask() async {
    let clock = ControllableClock()
    let authService = ScriptedAuthService()
    authService.deviceCodeResponses = [
      .success(VerificationResponse(
        code: "dev-bg",
        userCode: "BG999",
        verificationUri: "https://kino.pub/device",
        expiresIn: 300,
        interval: 5
      ))
    ]
    authService.tokenResponses = [
      .success(())
    ]

    let authState = AuthState(authService: authService, accessTokenService: AccessTokenServiceMock())
    let bgSpy = BackgroundTaskSpy()
    let feedbackSpy = FeedbackSpy()

    let model = AuthModel(
      authService: authService,
      authState: authState,
      backgroundTaskManager: bgSpy,
      feedbackHandler: feedbackSpy,
      now: { clock.now },
      sleep: { _ in },
      observesSystemLifecycle: false
    )

    await model.requestDeviceCodeIfNeeded()
    model.handleDidEnterBackground()
    XCTAssertTrue(bgSpy.isRunning)

    // Background poll tick runs while user is still in Safari and succeeds.
    let outcome = await model.pollOnce()
    XCTAssertEqual(outcome, .authorized)
    XCTAssertEqual(authState.phase, .signedIn)
    XCTAssertEqual(feedbackSpy.authorizedEvents, [true], "Background completion triggers local notification + haptics")
    XCTAssertFalse(bgSpy.isRunning)
  }

  // MARK: - 3. Expiration Handling After 5-Minute TTL

  func testCodeExpiresAfterFiveMinutesAndRequiresExplicitRefresh() async {
    let clock = ControllableClock()
    let authService = ScriptedAuthService()
    authService.deviceCodeResponses = [
      .success(VerificationResponse(
        code: "dev-first",
        userCode: "OLD11",
        verificationUri: "https://kino.pub/device",
        expiresIn: 300,
        interval: 5
      )),
      .success(VerificationResponse(
        code: "dev-second",
        userCode: "NEW22",
        verificationUri: "https://kino.pub/device",
        expiresIn: 300,
        interval: 5
      ))
    ]

    let authState = AuthState(authService: authService, accessTokenService: AccessTokenServiceMock())
    let model = AuthModel(
      authService: authService,
      authState: authState,
      backgroundTaskManager: BackgroundTaskSpy(),
      feedbackHandler: FeedbackSpy(),
      now: { clock.now },
      sleep: { _ in },
      observesSystemLifecycle: false
    )

    await model.requestDeviceCodeIfNeeded()
    XCTAssertEqual(model.deviceCode, "OLD11")
    XCTAssertFalse(model.isExpired)

    // At 299 seconds, still valid.
    clock.advance(by: 299)
    XCTAssertFalse(model.checkExpiration())
    XCTAssertFalse(model.isExpired)

    // At 300 seconds, TTL has elapsed -> transitions to expired without silently replacing the code.
    clock.advance(by: 1)
    let outcome = await model.pollOnce()
    XCTAssertEqual(outcome, .expired)
    XCTAssertTrue(model.isExpired)
    XCTAssertEqual(model.deviceCode, "OLD11")
    XCTAssertEqual(authService.fetchDeviceCodeCallCount, 1, "Must not silently fetch a new code on expiration")

    // User taps "Get New Code".
    await model.requestNewCode()
    XCTAssertFalse(model.isExpired)
    XCTAssertEqual(model.deviceCode, "NEW22")
    XCTAssertEqual(authService.fetchDeviceCodeCallCount, 2)
  }

  // MARK: - 4. Error Handling & Manual Retry

  func testNetworkErrorVsPendingVsExpiredAndManualRetry() async {
    let clock = ControllableClock()
    let authService = ScriptedAuthService()
    // 1st device code fetch fails offline; 2nd succeeds.
    authService.deviceCodeResponses = [
      .failure(APIClientError.networkError(URLError(.notConnectedToInternet))),
      .success(VerificationResponse(
        code: "dev-retry",
        userCode: "RT555",
        verificationUri: "kino.pub/device",
        expiresIn: 300,
        interval: 5
      )),
      .success(VerificationResponse(
        code: "dev-after-expired",
        userCode: "EX888",
        verificationUri: "https://kino.pub/device",
        expiresIn: 300,
        interval: 5
      ))
    ]
    authService.tokenResponses = [
      .failure(ScriptedAuthService.pendingError),
      .failure(ScriptedAuthService.slowDownError),
      .failure(APIClientError.httpStatus(502, data: nil)),
      .failure(ScriptedAuthService.expiredTokenError),
      .success(())
    ]

    let authState = AuthState(authService: authService, accessTokenService: AccessTokenServiceMock())
    let model = AuthModel(
      authService: authService,
      authState: authState,
      backgroundTaskManager: BackgroundTaskSpy(),
      feedbackHandler: FeedbackSpy(),
      now: { clock.now },
      sleep: { _ in },
      observesSystemLifecycle: false
    )

    // Initial code fetch fails with network error.
    await model.requestDeviceCodeIfNeeded()
    XCTAssertTrue(model.deviceCode.isEmpty)
    XCTAssertNotNil(model.errorMessage)
    XCTAssertFalse(model.isExpired)

    // User taps Retry -> fetches RT555 and clears errorMessage.
    await model.retry()
    XCTAssertEqual(model.deviceCode, "RT555")
    XCTAssertNil(model.errorMessage)
    XCTAssertEqual(model.activationURL, URL(string: "https://kino.pub/device"))
    XCTAssertTrue(model.shareMessage.contains("RT555"))

    // 1st poll: authorization_pending -> no error, still waiting.
    let pendingOutcome = await model.pollOnce()
    XCTAssertEqual(pendingOutcome, .pending)
    XCTAssertNil(model.errorMessage)

    // 2nd poll: slow_down -> backs off interval from 5s to 10s, no error.
    let slowDownOutcome = await model.pollOnce()
    XCTAssertEqual(slowDownOutcome, .pending)
    XCTAssertNil(model.errorMessage)
    XCTAssertEqual(model.currentPollInterval(), 10)

    // 3rd poll: HTTP 502 server error -> surfaces errorMessage, preserves RT555!
    let serverErrorOutcome = await model.pollOnce()
    if case .failed = serverErrorOutcome {
      // expected
    } else {
      XCTFail("Expected .failed outcome on HTTP 502, got \(serverErrorOutcome)")
    }
    XCTAssertNotNil(model.errorMessage)
    XCTAssertEqual(model.deviceCode, "RT555", "Server error during poll must not wipe the active device code")

    // 4th poll (via retry): server answers expired_token -> marks code expired.
    await model.retry()
    XCTAssertTrue(model.isExpired)
    XCTAssertNil(model.errorMessage)

    // 5th step: user requests a new code after expiration and next poll succeeds.
    await model.retry()
    XCTAssertFalse(model.isExpired)
    XCTAssertEqual(model.deviceCode, "EX888")
    let finalOutcome = await model.pollOnce()
    XCTAssertEqual(finalOutcome, .authorized)
    XCTAssertEqual(authState.phase, .signedIn)
  }

  func testSmartPollingIntervalScalesWithElapsedTimeAndResetsOnInteraction() async {
    let clock = ControllableClock()
    let authService = ScriptedAuthService()
    let authState = AuthState(authService: authService, accessTokenService: AccessTokenServiceMock())
    let model = AuthModel(
      authService: authService,
      authState: authState,
      backgroundTaskManager: BackgroundTaskSpy(),
      feedbackHandler: FeedbackSpy(),
      now: { clock.now },
      sleep: { _ in },
      observesSystemLifecycle: false
    )

    await model.requestDeviceCodeIfNeeded()
    XCTAssertEqual(model.currentPollInterval(), 5)

    // After 75s without interaction, scales to 15s.
    clock.advance(by: 75)
    XCTAssertEqual(model.currentPollInterval(), 15)

    // After 190s without interaction, scales to 25s.
    clock.advance(by: 115)
    XCTAssertEqual(model.currentPollInterval(), 25)

    // Copying the code resets the interaction clock -> back to 5s!
    model.copyCode()
    XCTAssertEqual(model.currentPollInterval(), 5)
  }

  // MARK: - 5. Shared iCloud Keychain Migration & Fallback

  func testKeychainStorageMigratesLocalTokenToSynchronizableStoreAndFallsBackGracefully() {
    let syncedStore = InMemoryKeychainStore()
    let localStore = InMemoryKeychainStore()
    let keychain = KeychainStorageImpl(synchronizableStore: syncedStore, localStore: localStore)

    let tokenKey = Key<AccessToken>(rawValue: "com.soda.kinopub.token.test")
    let legacyToken = AccessToken(accessToken: "legacy-access", refreshToken: "legacy-refresh", expiresIn: 3600)
    localStore.storage[tokenKey.rawValue] = try! JSONEncoder().encode(legacyToken)

    // Reading migrates the legacy local token into the synchronizable iCloud Keychain store
    // and removes the local duplicate.
    let migrated: AccessToken? = keychain.object(for: tokenKey)
    XCTAssertEqual(migrated, legacyToken)
    XCTAssertNotNil(syncedStore.storage[tokenKey.rawValue])
    XCTAssertNil(localStore.storage[tokenKey.rawValue])

    // If synchronizable Keychain is unavailable (e.g. unsigned test environment), writing
    // falls back to the local store without losing the token.
    syncedStore.shouldThrowOnWrite = true
    syncedStore.shouldThrowOnRead = true
    let fallbackToken = AccessToken(accessToken: "fallback-access", refreshToken: "fallback-refresh", expiresIn: 3600)
    keychain.setObject(fallbackToken, for: tokenKey)
    XCTAssertEqual(keychain.object(for: tokenKey), fallbackToken)
  }

  // MARK: - 6. Tandem Token Refresh (Reload-Before-Refresh & Race Recovery)

  func testRefreshTokenAdoptsNewerKeychainTokenWithoutCallingOAuthEndpoint() async throws {
    let syncedStore = InMemoryKeychainStore()
    let localStore = InMemoryKeychainStore()
    let keychain = KeychainStorageImpl(synchronizableStore: syncedStore, localStore: localStore)
    let tokenService = AccessTokenServiceImpl(storage: keychain)

    let initialToken = AccessToken(accessToken: "access-1", refreshToken: "refresh-1", expiresIn: 3600)
    tokenService.set(token: initialToken)
    XCTAssertEqual(tokenService.token(), initialToken)

    // Simulate another Apple device (e.g. Apple TV) refreshing the token and syncing
    // the new token pair into iCloud Keychain.
    let syncedFromAppleTV = AccessToken(accessToken: "access-2", refreshToken: "refresh-2", expiresIn: 3600)
    keychain.setObject(syncedFromAppleTV, for: Key<AccessToken>.token)

    let sessionMock = StubURLSession()
    sessionMock.handler = { request in
      let response = HTTPURLResponse(
        url: request.url ?? URL(string: "https://api.example.com/oauth2/token")!,
        statusCode: 400,
        httpVersion: nil,
        headerFields: nil
      )!
      return (#"{"error":"invalid_grant"}"#.data(using: .utf8)!, response)
    }

    let apiClient = APIClient(baseUrl: "https://api.example.com", session: sessionMock)
    let config = StubConfiguration()
    let authService = AuthorizationServiceImpl(
      apiClient: apiClient,
      configuration: config,
      accessTokenService: tokenService
    )

    // Refreshing reloads Keychain first, sees refresh-2 != refresh-1, and adopts it without hitting network!
    try await authService.refreshToken()
    XCTAssertEqual(sessionMock.requestCount, 0)
    let active: AccessToken? = tokenService.token()
    XCTAssertEqual(active, syncedFromAppleTV)
    XCTAssertFalse(tokenService.isAccessTokenExpiring(within: 90))
  }

  func testRefreshTokenRecoversWhenAnotherDeviceUpdatesKeychainDuringInFlight400() async throws {
    let syncedStore = InMemoryKeychainStore()
    let localStore = InMemoryKeychainStore()
    let keychain = KeychainStorageImpl(synchronizableStore: syncedStore, localStore: localStore)
    let tokenService = AccessTokenServiceImpl(storage: keychain)

    let initialToken = AccessToken(accessToken: "access-1", refreshToken: "refresh-1", expiresIn: 60)
    tokenService.set(token: initialToken)

    let syncedMidFlight = AccessToken(accessToken: "access-2", refreshToken: "refresh-2", expiresIn: 3600)

    final class MidFlightSyncSession: URLSessionProtocol {
      let keychain: KeychainStorageImpl
      let syncedToken: AccessToken

      init(keychain: KeychainStorageImpl, syncedToken: AccessToken) {
        self.keychain = keychain
        self.syncedToken = syncedToken
      }

      func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        // While this device's refresh request is in flight with refresh-1, iCloud Keychain
        // delivers refresh-2 from another device, and the server rejects refresh-1 with 400.
        keychain.setObject(syncedToken, for: Key<AccessToken>.token)
        let response = HTTPURLResponse(
          url: request.url ?? URL(string: "https://api.example.com/oauth2/token")!,
          statusCode: 400,
          httpVersion: nil,
          headerFields: nil
        )!
        let body = #"{"error":"invalid_grant","error_description":"Token already rotated"}"#.data(using: .utf8)!
        return (body, response)
      }
    }

    let apiClient = APIClient(
      baseUrl: "https://api.example.com",
      session: MidFlightSyncSession(keychain: keychain, syncedToken: syncedMidFlight)
    )
    let config = StubConfiguration()
    let authService = AuthorizationServiceImpl(
      apiClient: apiClient,
      configuration: config,
      accessTokenService: tokenService
    )
    let authState = AuthState(authService: authService, accessTokenService: tokenService)

    let recovered = await authState.recoverFromUnauthorized()
    XCTAssertTrue(recovered, "Should adopt the mid-flight synced token and recover instead of logging out")
    XCTAssertEqual(authState.phase, AuthPhase.signedIn)
    XCTAssertEqual(tokenService.token(), syncedMidFlight)
  }

  // MARK: - 7. Universal Apple Client Capabilities (4K + HDR + HEVC + SSL)

  func testUniversalDeviceCapabilitiesAlwaysKeepMaximumPlaybackProfile() {
    var downgradedSettings = DeviceSettings(
      supportSsl: false,
      supportHevc: false,
      supportHdr: false,
      support4k: false,
      mixedPlaylist: false,
      streamingType: 4,
      serverLocation: 1
    )

    let didChange = DeviceCapabilities.applyUniversalProfile(to: &downgradedSettings)
    XCTAssertTrue(didChange)
    XCTAssertTrue(downgradedSettings.support4k)
    XCTAssertTrue(downgradedSettings.supportHdr)
    XCTAssertTrue(downgradedSettings.supportHevc)
    XCTAssertTrue(downgradedSettings.supportSsl)
    XCTAssertTrue(downgradedSettings.mixedPlaylist)

    // Applying again when already at maximum capabilities is a no-op.
    XCTAssertFalse(DeviceCapabilities.applyUniversalProfile(to: &downgradedSettings))

    let request = UpdateDeviceSettingsRequest(id: 42, settings: downgradedSettings)
    XCTAssertEqual(request.parameters?["support4k"] as? Int, 1)
    XCTAssertEqual(request.parameters?["supportHdr"] as? Int, 1)
    XCTAssertEqual(request.parameters?["supportHevc"] as? Int, 1)
    XCTAssertEqual(request.parameters?["supportSsl"] as? Int, 1)
    XCTAssertEqual(request.parameters?["mixedPlaylist"] as? Int, 1)
  }
}
