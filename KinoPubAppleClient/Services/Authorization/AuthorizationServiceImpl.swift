//
//  AuthorizationServiceImpl.swift
//  KinoPubAppleClient
//
//  Created by Kirill Kunst on 26.07.2023.
//

import Foundation
import KinoPubBackend

final class AuthorizationServiceImpl: AuthorizationService, @unchecked Sendable {
  
  private let apiClient: APIClient
  private var configuration: Configuration
  private var accessTokenService: AccessTokenService

  init(apiClient: APIClient, configuration: Configuration, accessTokenService: AccessTokenService) {
    self.apiClient = apiClient
    self.configuration = configuration
    self.accessTokenService = accessTokenService
  }

  func fetchDeviceCode() async throws -> VerificationResponse {
    let request = DeviceCodeRequest(grantType: .deviceCode, clientID: configuration.clientID, clientSecret: configuration.clientSecret)
    return try await apiClient.performRequest(with: request, decodingType: VerificationResponse.self)
  }

  func fetchToken(by verification: VerificationResponse) async throws {
    let request = DeviceCodeRequest(grantType: .deviceToken, clientID: configuration.clientID, clientSecret: configuration.clientSecret, code: verification.code)
    let token = try await apiClient.performRequest(with: request, decodingType: AccessToken.self)
    accessTokenService.set(token: token)
  }

  func refreshToken() async throws {
    // Re-read Keychain before hitting `/oauth2/token`: if another Apple device already
    // refreshed the token in iCloud Keychain, adopt the synced token instead of sending
    // a stale `refresh_token` that kino.pub has already retired.
    let preflight = accessTokenService.reloadFromKeychain()
    guard let token = preflight.token else {
      recordDevSession("refresh skipped: no token in keychain")
      return
    }
    if preflight.didChangeExternally {
      recordDevSession("refresh skipped: adopted a token synced into keychain", token)
      return
    }

    let request = RefreshTokenRequest(clientID: configuration.clientID,
                                      clientSecret: configuration.clientSecret,
                                      refreshToken: token.refreshToken)
    recordDevSession("refresh start", token)
    do {
      let newToken = try await apiClient.performRequest(with: request, decodingType: AccessToken.self)
      recordDevSession("refresh ok, new", newToken)
      accessTokenService.set(token: newToken)
    } catch {
      recordDevSession("refresh failed: \(error)", token)
      // If another device rotated the refresh token while our request was in flight (or
      // iCloud Keychain finished syncing right after we started), adopt the newer
      // Keychain token instead of treating the 400 as a dead session.
      let postFailure = accessTokenService.reloadFromKeychain()
      if let synced = postFailure.token,
         (synced.refreshToken != token.refreshToken || synced.accessToken != token.accessToken) {
        recordDevSession("refresh failure absorbed: keychain has a newer token", synced)
        return
      }
#if DEBUG && (targetEnvironment(simulator) || os(macOS))
      // kino.pub rotates refresh tokens: refreshing invalidates the token that was used.
      // Debug builds share one session file, so a second build refreshing a minute later
      // presents a token the backend already retired and gets a 400 — even though the
      // session is perfectly alive under the *new* token. Adopt whatever the shared file
      // holds now before treating this as a dead session.
      if let shared = DevSessionMirror.load(), shared.refreshToken != token.refreshToken {
        DevSessionMirror.record("refresh failure absorbed: adopting the shared file", shared)
        accessTokenService.set(token: shared)
        return
      }
#endif
      recordDevSession("refresh failed for good: session is over", token)
      throw error
    }
  }

  /// Debug builds only: a line in the shared dev-session log (`DevSessionMirror.record`).
  private func recordDevSession(_ event: String, _ token: AccessToken? = nil) {
#if DEBUG && (targetEnvironment(simulator) || os(macOS))
    DevSessionMirror.record(event, token)
#endif
  }

  func logout() {
    logout(userInitiated: true)
  }

  func logout(userInitiated: Bool) {
    accessTokenService.clear(userInitiated: userInitiated)
    BookmarkMembershipStore.shared.clear()
    // Folder names outlive a session on disk, so they have to go with the account.
    Task { @MainActor in BookmarkFoldersStore.shared.clear() }
#if os(tvOS)
    // The shelf showed this account's titles; signed out, it is the static image again.
    Task { @MainActor in TopShelfPublisher.clear() }
#endif
    AppContext.shared.libraryState.clear()
    // The device record belonged to the account we just left — the next activation has
    // to register its identity and streaming profile from scratch.
    DeviceProfileRegistry.reset()
    // Do NOT clear ResponseCache — we only cache immutable reference lists
    // (genres/countries). Those never change per account on kino.pub.
  }

}
