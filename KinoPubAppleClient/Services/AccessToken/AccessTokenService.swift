//
//  AccessTokenService.swift
//  KinoPubAppleClient
//
//  Created by Kirill Kunst on 27.07.2023.
//

import Foundation
import KinoPubBackend

protocol Token: Codable {
  var accessToken: String { get }
  var refreshToken: String { get }
  var expiresIn: Int { get }
}

protocol AccessTokenService {
  func set<T>(token: T) where T: Token
  func token<T>() -> T? where T: Token
  /// Re-reads the persistent Keychain store and reports whether the stored token changed
  /// externally (for example via iCloud Keychain sync from another device) since this
  /// process last wrote or baseline-observed it.
  func reloadFromKeychain() -> (token: AccessToken?, didChangeExternally: Bool)
  func clear()
  /// `false` when the backend ended the session rather than the user — see the
  /// implementation for why the two cannot be treated the same.
  func clear(userInitiated: Bool)
  /// Absolute expiry of the current access token, recorded when it was stored.
  /// `nil` for tokens written before we persisted the clock (treat as unknown).
  var accessTokenExpiresAt: Date? { get }
  /// `true` when there is no known expiry, or expiry is within `interval` seconds.
  func isAccessTokenExpiring(within interval: TimeInterval) -> Bool
}

protocol AccessTokenServiceProvider {
  var accessTokenService: AccessTokenService { get set }
}

struct AccessTokenServiceMock: AccessTokenService {
  var accessTokenExpiresAt: Date?

  func set<T>(token: T) where T: Token {

  }

  func token<T>() -> T? where T: Token {
    nil
  }

  func reloadFromKeychain() -> (token: AccessToken?, didChangeExternally: Bool) {
    (nil, false)
  }

  func clear() {

  }

  func clear(userInitiated: Bool) {

  }

  func isAccessTokenExpiring(within interval: TimeInterval) -> Bool {
    true
  }
}
