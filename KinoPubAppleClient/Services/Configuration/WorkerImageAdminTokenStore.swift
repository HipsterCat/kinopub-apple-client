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

  static var token: String? {
    get {
      let raw: String? = storage.object(for: .workerImageAdminToken)
      let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      return trimmed.isEmpty ? nil : trimmed
    }
    set {
      let trimmed = newValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      storage.setObject(trimmed.isEmpty ? nil : trimmed, for: .workerImageAdminToken)
    }
  }

  static var isConfigured: Bool { token != nil }

  static func client(proxyBaseURL: URL?) -> WorkerImageAdminClient? {
    guard let baseURL = proxyBaseURL, let token else { return nil }
    return WorkerImageAdminClient(baseURL: baseURL, token: token)
  }
}
