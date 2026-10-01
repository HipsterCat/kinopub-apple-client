//
//  UnauthorizedRequestRecovery.swift
//  KinoPubBackend
//
//  Content 401 → refresh → retry. The app installs a recoverer (AuthState); the
//  API client awaits it once before failing the caller's request.
//

import Foundation

/// Refreshes the access token after a content endpoint answered 401.
/// Return `true` only when the caller should retry with a new Authorization header.
public protocol UnauthorizedRequestRecovering: AnyObject {
  func recoverFromUnauthorized() async -> Bool
}

/// Shared hook so `APIClient` does not need a reference to the app's `AuthState`.
public final class UnauthorizedRequestRecovery: @unchecked Sendable {
  public static let shared = UnauthorizedRequestRecovery()

  /// Installed by the app once `AuthState` exists. Weak so teardown cannot retain it.
  public weak var recoverer: UnauthorizedRequestRecovering?

  private init() {}

  public func recover() async -> Bool {
    guard let recoverer else { return false }
    return await recoverer.recoverFromUnauthorized()
  }
}
