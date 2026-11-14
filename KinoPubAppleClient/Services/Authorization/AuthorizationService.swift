//
//  AuthorizationService.swift
//  KinoPubAppleClient
//
//  Created by Kirill Kunst on 26.07.2023.
//

import Foundation
import KinoPubBackend

enum MockError: Error {
  case mock
}

protocol AuthorizationService: Sendable {
  func fetchDeviceCode() async throws -> VerificationResponse
  func fetchToken(by verification: VerificationResponse) async throws
  func refreshToken() async throws
  func logout()
  /// `false` when the backend rejected the session rather than the user signing out.
  /// System-forced logout clears credentials only; personal caches stay until a
  /// different account signs in (`clearPersonalSessionData`).
  func logout(userInitiated: Bool)
  /// Bookmarks, continue-watching, subscriptions / watchlist rows, local watch history
  /// and optimistic library state for the previous account.
  func clearPersonalSessionData()
}

protocol AuthorizationServiceProvider {
  var authService: AuthorizationService { get set }
}

struct AuthorizationServiceMock: AuthorizationService {

  func fetchDeviceCode() async throws -> VerificationResponse {
    throw MockError.mock
  }

  func fetchToken(by verification: VerificationResponse) async throws {
    throw MockError.mock
  }

  func refreshToken() async throws {
    throw MockError.mock
  }
  
  func logout() {

  }

  func logout(userInitiated: Bool) {

  }

  func clearPersonalSessionData() {

  }

}
