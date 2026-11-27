//
//  UserProfileCache.swift
//  Piratic
//

import Foundation
import KinoPubBackend
import PiraticLogging
import OSLog
import Observation

/// Persists the sidebar profile (name, subscription days, avatar) to `Caches/`, so a
/// cold start paints the last known profile before the network answers — and an
/// offline start doesn't show a blank row. Same deal as `RowSnapshotStore`: a
/// missing or OS-purged snapshot just means "fetch fresh".
@MainActor
final class UserProfileCache {
  static let shared = UserProfileCache()

  private let userFileURL: URL
  private let avatarFileURL: URL

  init(directory: URL? = nil) {
    let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
      ?? URL(fileURLWithPath: NSTemporaryDirectory())
    let dir = directory ?? caches.appendingPathComponent("PiraticProfile", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    self.userFileURL = dir.appendingPathComponent("user.json")
    self.avatarFileURL = dir.appendingPathComponent("avatar")
  }

  func loadUser() -> UserData? {
    guard let data = try? Data(contentsOf: userFileURL) else { return nil }
    return try? JSONDecoder().decode(UserData.self, from: data)
  }

  func loadAvatar() -> Data? {
    try? Data(contentsOf: avatarFileURL)
  }

  func save(user: UserData) {
    do {
      let data = try JSONEncoder().encode(user)
      try data.write(to: userFileURL, options: [.atomic])
    } catch {
      Logger.app.error("UserProfileCache: save user failed: \(error.localizedDescription)")
    }
  }

  func saveAvatar(_ data: Data) {
    do {
      try data.write(to: avatarFileURL, options: [.atomic])
    } catch {
      Logger.app.error("UserProfileCache: save avatar failed: \(error.localizedDescription)")
    }
  }

  func clearAvatar() {
    try? FileManager.default.removeItem(at: avatarFileURL)
  }

  /// Drops the cached profile and avatar — previous account's name must not linger.
  func clear() {
    try? FileManager.default.removeItem(at: userFileURL)
    clearAvatar()
  }
}

/// The signed-in account's profile, one per app. Seeded from `UserProfileCache` at
/// launch and trusted: `/v1/user` is asked again only when the copy is older than
/// `freshFor`, never more than once at a time, and not again for `retryAfterFailure`
/// after it failed. A failure keeps the copy, shows nothing and signs nobody out.
///
/// Before (2026-11-22): every Settings screen `.task` asked `/v1/user` and toasted a
/// failure; with the API answering 502, Sasha's iPad sent it several times a second.
@MainActor
@Observable
final class UserProfileStore {
  static let shared = UserProfileStore()

  /// Subscription days are the fastest-moving field, and they move once a day.
  static let freshFor: TimeInterval = 6 * 60 * 60
  static let retryAfterFailure: TimeInterval = 10 * 60

  private(set) var user: UserData?

  @ObservationIgnored private let cache: UserProfileCache
  @ObservationIgnored private let defaults: UserDefaults
  @ObservationIgnored private var lastFailure: Date?
  @ObservationIgnored private var inFlight: Task<UserData?, Never>?
  private static let savedAtKey = "PiraticUserProfileSavedAt"

  init(cache: UserProfileCache = .shared, defaults: UserDefaults = .standard) {
    self.cache = cache
    self.defaults = defaults
    self.user = cache.loadUser()
  }

  private var savedAt: Date? {
    defaults.object(forKey: Self.savedAtKey) as? Date
  }

  /// Asks `/v1/user` only when the copy is missing or stale; otherwise returns it.
  @discardableResult
  func refreshIfStale(using service: UserService, now: Date = Date()) async -> UserData? {
    if let user, let savedAt, now.timeIntervalSince(savedAt) < Self.freshFor {
      return user
    }
    if let lastFailure, now.timeIntervalSince(lastFailure) < Self.retryAfterFailure {
      return user
    }
    if let inFlight {
      return await inFlight.value
    }
    let task = Task<UserData?, Never> { [weak self] in
      do {
        let fresh = try await service.fetchUserData()
        self?.save(fresh)
        return fresh
      } catch {
        if !(error is CancellationError) {
          self?.lastFailure = Date()
          Logger.app.info("UserProfileStore: /v1/user failed, keeping the cached profile: \(error.localizedDescription)")
        }
        return self?.user
      }
    }
    inFlight = task
    let result = await task.value
    inFlight = nil
    return result
  }

  /// A profile fetched elsewhere (sign-in reconciliation).
  func save(_ fresh: UserData) {
    user = fresh
    lastFailure = nil
    cache.save(user: fresh)
    defaults.set(Date(), forKey: Self.savedAtKey)
  }

  /// Sign-out: the previous account's name must not linger.
  func clear() {
    inFlight?.cancel()
    inFlight = nil
    user = nil
    lastFailure = nil
    cache.clear()
    defaults.removeObject(forKey: Self.savedAtKey)
  }
}
