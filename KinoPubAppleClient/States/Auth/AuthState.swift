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

/// A class that manages the authentication state of the user.
@MainActor
final class AuthState: ObservableObject {
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
  private var refreshRetryAttempt = 0
  /// Serializes refresh attempts — startup check, backoff retry and 401-triggered
  /// refreshes must never overlap.
  private var isRefreshing = false
  /// Set when a refresh was cut off mid-flight. **The next rejection cannot be trusted
  /// after one of those:** the cancelled request may well have reached kino.pub and
  /// rotated the refresh token there, in which case the following attempt presents a
  /// token the server has already retired and gets a 400 that says nothing about the
  /// session.
  private var lastRefreshWasCancelled = false
  /// Root `.task` re-fires when the hierarchy churns (iOS player orientation used to).
  /// Bootstrap refresh runs once per signed-in stretch; mid-session expiry is the
  /// 401 observer's job.
  private var didBootstrapRefresh = false

  /// Initializes the `AuthState` with the provided services.
  /// - Parameters:
  ///   - authService: The authorization service used for authentication.
  ///   - accessTokenService: The access token service used for managing access tokens.
  init(authService: AuthorizationService, accessTokenService: AccessTokenService) {
    self.authService = authService
    self.accessTokenService = accessTokenService
    // Optimistic: a Keychain token is enough to show the shell and cached shelves.
    // `check()` still refreshes in the background; only a fatal grant rejection
    // (and the 401 path) send the user to activation. The old blocking `.resolving`
    // splash waited on that refresh and felt hostile on every cold launch.
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

    // A 401 from any content endpoint mid-session → one guarded refresh.
    NotificationCenter.default.addObserver(
      forName: .kinopubUnauthorizedResponse, object: nil, queue: .main
    ) { [weak self] _ in
      self?.handleUnauthorizedResponse() // Call to main actor-isolated instance method 'handleUnauthorizedResponse()' in a synchronous nonisolated context
    }
  }

  /// Checks the authentication state of the user.
  func check() async {
    Logger.app.debug("Start auth state checking...")
    guard let _: AccessToken = accessTokenService.token() else {
      markSignedOut(reason: "no token")
      return
    }

    // Already painted the shell from Keychain — keep it. First bootstrap still
    // refreshes underneath; later `.task` re-fires must not rotate the token again
    // (kino.pub retires the previous refresh token on every success).
    if phase != .signedIn {
      phase = .signedIn
      userState = .authorized
      shouldShowAuthentication = false
    }
    guard !didBootstrapRefresh else { return }
    didBootstrapRefresh = true
    await refreshToken()
  }

  /// Device-activation screen got a token — enter the app. `activated` separates that
  /// from a token refresh, which reaches the same state without being a new device.
  func markSignedIn(activated: Bool = false) {
    refreshRetryTask?.cancel()
    refreshRetryTask = nil
    refreshRetryAttempt = 0
    if activated {
      didActivateDevice = true
      // Fresh grant from device code — no bootstrap refresh needed this stretch.
      didBootstrapRefresh = true
    }
    phase = .signedIn
    userState = .authorized
    shouldShowAuthentication = false
    Logger.app.debug("Auth state: authorized")
  }

  /// A 401 from a content endpoint means the access token died mid-session. One
  /// refresh decides: success rotates quietly, rejection brings the activation
  /// screen, a network failure falls back to the scheduled retries.
  private func handleUnauthorizedResponse() {
    // Already signed out / refresh in flight — swallow. In-flight Home fetches after
    // a fatal refresh used to log this line once per shelf.
    guard phase == .signedIn else { return }
    guard !isRefreshing else { return }
    guard let _: AccessToken = accessTokenService.token() else {
      markSignedOut(reason: "401 with empty keychain")
      return
    }
    Logger.app.info("Content endpoint answered 401 — refreshing the token")
    Task { await refreshToken() }
  }

  private func refreshToken() async {
    guard !isRefreshing else { return }
    isRefreshing = true
    defer { isRefreshing = false }
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
    } catch let error as APIClientError where error.isFatalAuthError && !lastRefreshWasCancelled {
      // The backend explicitly rejected the refresh token — only now is the session
      // really over. Clear Keychain so the next launch does not revive a dead token.
      refreshRetryTask?.cancel()
      refreshRetryTask = nil
      authService.logout(userInitiated: false)
      markSignedOut(reason: "refresh rejected")
    } catch let error as APIClientError where error.isFatalAuthError {
      // Rejected, but right after a cancelled attempt — one grace round rather than
      // throwing the viewer at the activation screen on our own race.
      Logger.app.warning("Refresh rejected right after a cancelled one — keeping the session for one retry")
      lastRefreshWasCancelled = false
      markSignedIn()
      scheduleRefreshRetry()
    } catch {
      // Timeout / offline / unreachable host: keep the session. The Keychain token
      // may still be valid and every screen has its own error state — logging out
      // over a network hiccup just throws the user at the activation code screen.
      lastRefreshWasCancelled = Self.wasCancelled(error)
      Logger.app.warning("Token refresh failed transiently, keeping the session: \(error)")
      markSignedIn()
      scheduleRefreshRetry()
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
      await self.refreshToken()
    }
  }

  /// Logs out the user.
  func logout() {
    refreshRetryTask?.cancel()
    refreshRetryTask = nil
    authService.logout()
    markSignedOut(reason: "logout")
  }

  private func markSignedOut(reason: String) {
    didActivateDevice = false
    didBootstrapRefresh = false
    phase = .signedOut
    userState = .unauthorized
    shouldShowAuthentication = true
    Logger.app.info("Auth state: unauthorized (\(reason))")
  }
}
