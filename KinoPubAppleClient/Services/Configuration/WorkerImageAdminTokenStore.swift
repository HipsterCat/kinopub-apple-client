//
//  WorkerImageAdminTokenStore.swift
//

import Foundation
import KinoPubMetadata

private let service = "com.soda.kinopub.workerImageAdmin"

extension Key where Value == String {
  fileprivate static var workerImageAdminToken: Key<String> { .init(rawValue: "adminToken") }
}

/// Bearer token for the TMDB proxy `/admin/*` routes. Not session-scoped — survives logout.
@MainActor
enum WorkerImageAdminTokenStore {
  private static let storage = KeychainStorageImpl(service: service)

  /// Read from the Keychain once per launch: every card's context menu asks for it from
  /// its body, and a Keychain query per card showed up in the main thread's samples
  /// (2026-11-17). This store is the only writer, so the copy stays true.
  private static var cached: String??

  static var token: String? {
    get {
      if let cached { return cached }
      let raw: String? = storage.object(for: .workerImageAdminToken)
      let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      let value = trimmed.isEmpty ? nil : trimmed
      cached = .some(value)
      return value
    }
    set {
      let trimmed = newValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      let value = trimmed.isEmpty ? nil : trimmed
      storage.setObject(value, for: .workerImageAdminToken)
      cached = .some(value)
    }
  }

  static var isConfigured: Bool { token != nil }

  static func client(proxyBaseURL: URL?) -> WorkerImageAdminClient? {
    guard let baseURL = proxyBaseURL, let token else { return nil }
    return WorkerImageAdminClient(baseURL: baseURL, token: token)
  }
}
