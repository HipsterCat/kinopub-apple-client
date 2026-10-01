//
//  AuthState.swift
//  KinoPubAppleClient
//
//  Created by Kirill Kunst on 3.08.2023.
//

import Foundation
import KinoPubBackend
import KinoPubLogging
import OSLog

/// Represents the state of the user's authentication.
enum UserState {
  case unauthorized
  case authorized
}

/// Gate for the root UI.
///
/// A Keychain token is enough to mount Tabs immediately (`signedIn`). Refresh /
/// validation runs in the background; only a real grant rejection drops to
/// `signedOut`. Product decision, 2026-10-01 — do not reintroduce a blocking
/// splash that waits on `refreshToken`.
enum AuthPhase: Equatable {
  /// No usable session — device-activation screen.
  case signedOut
  /// Keychain had a token (or activation / refresh just succeeded).
  case signedIn
}

/// Outcome of one refresh attempt. Shared waiters (launch, proactive timer, content
/// 401 recovery) all see the same result.
private enum TokenRefreshOutcome {
  /// New access token is in the Keychain.
  case succeeded
  /// Network blip / timeout / cancelled — keep the session, retry later.
  case transientFailure
  /// Backend rejected the grant — session is over.
  case fatalRejection
}

/// A class that manages the authentication state of the user.
@MainActor
final class AuthState: ObservableObject, UnauthorizedRequestRecovering {
  /// Refresh this far before `expires_in` elapses so content requests never race the clock.
  private static let refreshSkew: TimeInterval = 90

  @Published private(set) var phase: AuthPhase
  @Published var userState: UserState
  /// Back-compat for call sites that still read the flag; mirrors `phase == .signedOut`.
  @Published var shouldShowAuthentication: Bool
  /// True when this session began by exchanging a device code rather than by reviving a
  /// Keychain token — the moment kino.pub expects a full device profile, and the only
  /// one that re-registers it unconditionally.
  @Published private(set) var didActivateDevice = false

  private var authService: AuthorizationService
  private var accessTokenService: AccessTokenService
  private var refreshRetryTask: Task<Void, Never>?
  private var proactiveRefreshTask: Task<Void, Never>?
  private var refreshRetryAttempt = 0
  /// One in-flight refresh shared by launch, proactive timer and every content 401.
  /// Concurrent callers await the same task instead of no-op'ing on `isRefreshing`.
  private var refreshTask: Task<TokenRefreshOutcome, Never>?
  /// Set when a refresh was cut off mid-flight. **The next rejection cannot be trusted
  /// after one of those:** the cancelled request may well have reached kino.pub and
  /// rotated the refresh token there, in which case the following attempt presents a
  /// token the server has already retired and gets a 400 that says nothing about the
  /// session.
  private var lastRefreshWasCancelled = false
  /// Root `.task` re-fires when the hierarchy churns. Bootstrap runs once per
  /// signed-in stretch; later expiry is the proactive timer + 401 recovery.
  private var didBootstrap = false

  /// Initializes the `AuthState` with the provided services.
  /// - Parameters:
  ///   - authService: The authorization service used for authentication.
  ///   - accessTokenService: The access token service used for managing access tokens.
  init(authService: AuthorizationService, accessTokenService: AccessTokenService) {
    self.authService = authService
    self.accessTokenService = accessTokenService
    // Optimistic: a Keychain token is enough to show the shell and cached shelves.
    // Refresh runs by expiry (and on content 401); only a fatal grant rejection
    // sends the user to activation.
    let hasToken = (accessTokenService.token() as AccessToken?) != nil
    if hasToken {
      self.phase = .signedIn
      self.userState = .authorized
      self.shouldShowAuthentication = false
    } else {
      self.phase = .signedOut
      self.userState = .unauthorized
      self.shouldShowAuthentication = true
    }

    // Content 401 → refresh. Prefer the API client's awaitable recovery (retry the
    // failed request); this notification is the belt for anything that bypasses it.
    NotificationCenter.default.addObserver(
      forName: .kinopubUnauthorizedResponse, object: nil, queue: .main
    ) { [weak self] _ in
      self?.handleUnauthorizedResponse()
    }

    UnauthorizedRequestRecovery.shared.recoverer = self
  }

  /// Checks the authentication state of the user.
  func check() async {
    Logger.app.debug("Start auth state checking...")
    guard let _: AccessToken = accessTokenService.token() else {
      markSignedOut(reason: "no token")
      return
    }

    if phase != .signedIn {
      phase = .signedIn
      userState = .authorized
      shouldShowAuthentication = false
    }

    // Hierarchy churn re-fires root `.task` — do not rotate the refresh token again.
    guard !didBootstrap else { return }
    didBootstrap = true

    // Refresh when the access token is already near expiry (or we have no clock yet).
    // Otherwise just arm the timer — no need to hit oauth on every cold launch.
    if accessTokenService.isAccessTokenExpiring(within: Self.refreshSkew) {
      _ = await refreshAccessToken()
    } else {
      scheduleProactiveRefresh()
    }
  }

  /// Device-activation screen got a token — enter the app. `activated` separates that
  /// from a token refresh, which reaches the same state without being a new device.
  func markSignedIn(activated: Bool = false) {
    refreshRetryTask?.cancel()
    refreshRetryTask = nil
    refreshRetryAttempt = 0
    if activated {
      didActivateDevice = true
      didBootstrap = true
    }
    phase = .signedIn
    userState = .authorized
    shouldShowAuthentication = false
    Logger.app.debug("Auth state: authorized")
    scheduleProactiveRefresh()
  }

  /// APIClient calls this after a content 401. Refresh once (shared), then tell the
  /// client whether to retry the original request with a new Bearer token.
  func recoverFromUnauthorized() async -> Bool {
    guard phase == .signedIn else { return false }
    guard let _: AccessToken = accessTokenService.token() else {
      markSignedOut(reason: "401 with empty keychain")
      return false
    }
    Logger.app.info("Content endpoint answered 401 — refreshing the token")
    switch await refreshAccessToken() {
    case .succeeded:
      return true
    case .transientFailure, .fatalRejection:
      return false
    }
  }

  /// Fire-and-forget path for the notification plugin. Same shared refresh; no retry
  /// of the original request here — that is `recoverFromUnauthorized`'s job.
  private func handleUnauthorizedResponse() {
    guard phase == .signedIn else { return }
    guard refreshTask == nil else { return }
    guard let _: AccessToken = accessTokenService.token() else {
      markSignedOut(reason: "401 with empty keychain")
      return
    }
    Logger.app.info("Content endpoint answered 401 — refreshing the token")
    Task { _ = await refreshAccessToken() }
  }

  /// One shared refresh. Concurrent callers await the same task.
  @discardableResult
  private func refreshAccessToken() async -> TokenRefreshOutcome {
    if let refreshTask {
      return await refreshTask.value
    }
    let task = Task { await self.performRefresh() }
    refreshTask = task
    let outcome = await task.value
    refreshTask = nil
    return outcome
  }

  private func performRefresh() async -> TokenRefreshOutcome {
    Logger.app.debug("Refreshing token...")
    do {
      // kino.pub rotates the refresh token on every call, so once a refresh has
      // started it must run to completion: a SwiftUI `.task` dying mid-request used
      // to cancel the URLSession task *after* the server had already rotated, the
      // new token never reached the Keychain, and the next refresh presented the
      // retired one → 400 → forced logout out of nowhere. The unstructured task is
      // not a child of the caller, so the caller's cancellation cannot reach the
      // request, and awaiting `value` is not itself cancellable.
      let job = Task { try await authService.refreshToken() }
      try await job.value
      lastRefreshWasCancelled = false
      markSignedIn()
      return .succeeded
    } catch let error as APIClientError where error.isFatalAuthError && !lastRefreshWasCancelled {
      // The backend explicitly rejected the refresh token — only now is the session
      // really over. Clear Keychain so the next launch does not revive a dead token.
      refreshRetryTask?.cancel()
      refreshRetryTask = nil
      proactiveRefreshTask?.cancel()
      proactiveRefreshTask = nil
      authService.logout(userInitiated: false)
      markSignedOut(reason: "refresh rejected")
      return .fatalRejection
    } catch let error as APIClientError where error.isFatalAuthError {
      // Rejected, but right after a cancelled attempt — one grace round rather than
      // throwing the viewer at the activation screen on our own race.
      Logger.app.warning("Refresh rejected right after a cancelled one — keeping the session for one retry")
      lastRefreshWasCancelled = false
      markSignedIn()
      scheduleRefreshRetry()
      return .transientFailure
    } catch {
      // Timeout / offline / unreachable host: keep the session. The Keychain token
      // may still be valid and every screen has its own error state — logging out
      // over a network hiccup just throws the user at the activation code screen.
      lastRefreshWasCancelled = Self.wasCancelled(error)
      Logger.app.warning("Token refresh failed transiently, keeping the session: \(error)")
      markSignedIn()
      scheduleRefreshRetry()
      return .transientFailure
    }
  }

  /// A cancellation anywhere in the chain — the wrapper carries the `URLError` underneath.
  private static func wasCancelled(_ error: Error) -> Bool {
    if error is CancellationError { return true }
    var stack: [NSError] = [error as NSError]
    while let next = stack.popLast() {
      if next.domain == NSURLErrorDomain, next.code == NSURLErrorCancelled { return true }
      stack.append(contentsOf: next.underlyingErrors.map { $0 as NSError })
    }
    return false
  }

  /// Retries a failed refresh with backoff (5s → 10s → 20s → … capped at 2 min) so a
  /// network blip at launch resolves itself once connectivity returns.
  private func scheduleRefreshRetry() {
    refreshRetryTask?.cancel()
    let delay = min(5 * pow(2.0, Double(refreshRetryAttempt)), 120)
    refreshRetryAttempt += 1
    refreshRetryTask = Task { [weak self] in
      try? await Task.sleep(for: .seconds(delay))
      guard !Task.isCancelled, let self else { return }
      _ = await self.refreshAccessToken()
    }
  }

  /// Refresh shortly before the access token expires, using the clock we wrote on `set`.
  private func scheduleProactiveRefresh() {
    proactiveRefreshTask?.cancel()
    guard phase == .signedIn else { return }
    guard let expiresAt = accessTokenService.accessTokenExpiresAt else {
      // No clock (legacy Keychain entry) — refresh on the next bootstrap / 401 path.
      return
    }
    let delay = expiresAt.timeIntervalSinceNow - Self.refreshSkew
    if delay <= 0 {
      Task { _ = await refreshAccessToken() }
      return
    }
    Logger.app.debug("Scheduling proactive token refresh in \(Int(delay))s")
    proactiveRefreshTask = Task { [weak self] in
      try? await Task.sleep(for: .seconds(delay))
      guard !Task.isCancelled, let self else { return }
      _ = await self.refreshAccessToken()
    }
  }

  /// Logs out the user.
  func logout() {
    refreshRetryTask?.cancel()
    refreshRetryTask = nil
    proactiveRefreshTask?.cancel()
    proactiveRefreshTask = nil
    authService.logout()
    markSignedOut(reason: "logout")
  }

  private func markSignedOut(reason: String) {
    didActivateDevice = false
    didBootstrap = false
    proactiveRefreshTask?.cancel()
    proactiveRefreshTask = nil
    phase = .signedOut
    userState = .unauthorized
    shouldShowAuthentication = true
    Logger.app.info("Auth state: unauthorized (\(reason))")
  }
}
