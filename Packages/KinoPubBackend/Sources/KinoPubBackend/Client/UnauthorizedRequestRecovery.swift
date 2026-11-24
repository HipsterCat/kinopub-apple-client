//
//  UnauthorizedRequestRecovery.swift
//  KinoPubBackend
//
//  Content 401 → refresh → retry. The app installs a recoverer (AuthState); the
//  API client awaits it once before failing the caller's request.
//

import Foundation
import Synchronization

/// Refreshes the access token after a content endpoint answered 401.
/// Return `true` only when the caller should retry with a new Authorization header.
public protocol UnauthorizedRequestRecovering: AnyObject, Sendable {
  func recoverFromUnauthorized() async -> Bool
}

/// Shared hook so `APIClient` does not need a reference to the app's `AuthState`.
public final class UnauthorizedRequestRecovery: Sendable {
  public static let shared = UnauthorizedRequestRecovery()

  private struct Installed {
    weak var recoverer: UnauthorizedRequestRecovering?
  }

  /// Written by the app on the main actor, read by whichever thread a request ends on.
  private let installed = Mutex(Installed())

  /// Installed by the app once `AuthState` exists. Weak so teardown cannot retain it.
  public var recoverer: UnauthorizedRequestRecovering? {
    get { installed.withLock { $0.recoverer } }
    set { installed.withLock { $0.recoverer = newValue } }
  }

  private init() {}

  public func recover() async -> Bool {
    guard let recoverer else { return false }
    return await recoverer.recoverFromUnauthorized()
  }
}
