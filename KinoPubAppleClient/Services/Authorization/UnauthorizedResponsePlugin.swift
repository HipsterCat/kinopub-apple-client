//
//  UnauthorizedResponsePlugin.swift
//  KinoPubAppleClient
//

import Foundation
import KinoPubBackend

extension Notification.Name {
  /// Posted when any content (non-oauth) endpoint answers 401 — the access token
  /// died mid-session. `AuthState` listens and runs a guarded token refresh.
  static let kinopubUnauthorizedResponse = Notification.Name("kinopubUnauthorizedResponse")
  /// Posted when a content endpoint says the session is dead for good (`user_banned`,
  /// refused grant). `AuthState` presents device-code auth; personal caches stay until
  /// a *different* account signs in.
  static let kinopubSessionInvalidated = Notification.Name("kinopubSessionInvalidated")
}

/// Watches content endpoints for 401 (refreshable) and hard auth death (ban / refused
/// grant). OAuth endpoints are excluded: the refresh/device flows handle their own
/// failures, and a device-code screen that isn't authorized yet would otherwise spam
/// refresh or sign-out attempts.
final class UnauthorizedResponsePlugin: APIClientPlugin {

  init() {}

  func prepare(_ request: URLRequest) -> URLRequest {
    request
  }

  func willSend(_ request: URLRequest) {}

  func didReceive(_ response: URLResponse, data: Data?) {
    guard let http = response as? HTTPURLResponse,
          http.url?.path.contains("oauth2") == false else { return }

    if http.statusCode == 401 {
      NotificationCenter.default.post(name: .kinopubUnauthorizedResponse, object: nil)
      return
    }

    guard let data,
          let backendError = try? JSONDecoder().decode(BackendError.self, from: data) else {
      return
    }
    let error = APIClientError.networkError(backendError)
    guard error.requiresInteractiveReauthentication else { return }
    NotificationCenter.default.post(name: .kinopubSessionInvalidated, object: nil)
  }
}
