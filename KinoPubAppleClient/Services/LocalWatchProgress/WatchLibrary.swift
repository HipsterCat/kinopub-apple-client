//
//  WatchLibrary.swift
//  KinoPubAppleClient
//
//  The SwiftData store behind `LocalWatchProgressStore`: one row per resume point
//  (per episode for a series, per title for a film) and one payload snapshot per
//  title, so a relaunch can still draw the card and resolve the series.
//
//  Where it lives: `Caches/`. tvOS gives an app 500 KB of `UserDefaults` and nothing
//  else that survives — "all other data must be purgeable by the operating system"
//  (App Programming Guide for tvOS) — and `Documents/`, where the old JSON file sat,
//  is not writable on an Apple TV at all. Losing this store costs the local overlay
//  until the next `marktime` round trip, never a user action.
//
//  CloudKit-ready on purpose: every attribute has a default and nothing is
//  `@Attribute(.unique)` — both are CloudKit requirements for a SwiftData schema.
//  Uniqueness is kept by `key` in code instead. Turning on iCloud is then a
//  `ModelConfiguration(cloudKitDatabase:)` change plus the iCloud capability.
//

import Foundation
import KinoPubBackend
import KinoPubLogging
import OSLog
import SwiftData

// MARK: - Models

@Model
final class WatchRecord {
  /// `"<itemID>:m"` for a film, `"<itemID>:<season>:<episode>"` for an episode.
  var key: String = ""
  var itemID: Int = 0
  var season: Int?
  var episode: Int?
  var position: Double = 0
  var duration: Double = 0
  var updatedAt: Date = Date.distantPast

  init(key: String, itemID: Int, season: Int?, episode: Int?,
       position: Double, duration: Double, updatedAt: Date) {
    self.key = key
    self.itemID = itemID
    self.season = season
    self.episode = episode
    self.position = position
    self.duration = duration
    self.updatedAt = updatedAt
  }

  /// A film has one resume point whatever `episode` says — `videos.first.number` does
  /// not round-trip reliably, so it is never part of a film's key.
  static func key(itemID: Int, season: Int?, episode: Int?) -> String {
    guard let season else { return "\(itemID):m" }
    return "\(itemID):\(season):\(episode ?? 0)"
  }
}

@Model
final class TitleSnapshot {
  var itemID: Int = 0
  /// JSON of the `MediaItem` the player last had for this title.
  var payload: Data = Data()
  var updatedAt: Date = Date.distantPast

  init(itemID: Int, payload: Data, updatedAt: Date) {
    self.itemID = itemID
    self.payload = payload
    self.updatedAt = updatedAt
  }
}

// MARK: - Plain values crossing actors

/// `@Model` objects stay inside their context; these are what the store hands around.
struct WatchRecordValue: Sendable, Equatable {
  var itemID: Int
  var season: Int?
  var episode: Int?
  var position: Double
  var duration: Double
  var updatedAt: Date

  var key: String { WatchRecord.key(itemID: itemID, season: season, episode: episode) }
  var watch: WatchProgress { WatchProgress(position: position, duration: duration) }
}

// MARK: - Container

enum WatchLibrary {
  static let schema = Schema([WatchRecord.self, TitleSnapshot.self])

  /// On disk under `Caches/KinoPubLibrary/`. Falls back to memory only if the store
  /// cannot be opened at all (a corrupt file is removed and retried once first), so a
  /// broken cache can never keep the app from launching.
  static func makeContainer() -> ModelContainer {
    let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
      ?? URL(fileURLWithPath: NSTemporaryDirectory())
    let directory = caches.appendingPathComponent("KinoPubLibrary", isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("watch.store")
    let configuration = ModelConfiguration("Watch", schema: schema, url: url, cloudKitDatabase: .none)

    if let container = try? ModelContainer(for: schema, configurations: configuration) {
      return container
    }
    Logger.app.error("WatchLibrary: store at \(url.path) failed to open, recreating it")
    for suffix in ["", "-shm", "-wal"] {
      try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix))
    }
    if let container = try? ModelContainer(for: schema, configurations: configuration) {
      return container
    }
    Logger.app.error("WatchLibrary: falling back to an in-memory store")
    let memory = ModelConfiguration("Watch", schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    // An in-memory store with a valid schema does not fail to open.
    // swiftlint:disable:next force_try
    return try! ModelContainer(for: schema, configurations: memory)
  }
}

// MARK: - Writer

/// Every write goes through here, off the main thread. The player calls in every ~10s,
/// so the caller never waits on disk.
@ModelActor
actor WatchLibraryWriter {

  func upsert(_ value: WatchRecordValue) {
    let key = value.key
    var descriptor = FetchDescriptor<WatchRecord>(predicate: #Predicate { $0.key == key })
    descriptor.fetchLimit = 1
    if let existing = try? modelContext.fetch(descriptor).first {
      existing.position = value.position
      existing.duration = value.duration
      existing.episode = value.episode
      existing.updatedAt = value.updatedAt
    } else {
      modelContext.insert(WatchRecord(key: key,
                                      itemID: value.itemID,
                                      season: value.season,
                                      episode: value.episode,
                                      position: value.position,
                                      duration: value.duration,
                                      updatedAt: value.updatedAt))
    }
    save()
  }

  func upsertSnapshot(itemID: Int, payload: Data) {
    var descriptor = FetchDescriptor<TitleSnapshot>(predicate: #Predicate { $0.itemID == itemID })
    descriptor.fetchLimit = 1
    if let existing = try? modelContext.fetch(descriptor).first {
      existing.payload = payload
      existing.updatedAt = Date()
    } else {
      modelContext.insert(TitleSnapshot(itemID: itemID, payload: payload, updatedAt: Date()))
    }
    save()
  }

  func deleteAll(itemID: Int) {
    try? modelContext.delete(model: WatchRecord.self, where: #Predicate { $0.itemID == itemID })
    try? modelContext.delete(model: TitleSnapshot.self, where: #Predicate { $0.itemID == itemID })
    save()
  }

  private func save() {
    do {
      try modelContext.save()
    } catch {
      Logger.app.error("WatchLibrary: save failed: \(error.localizedDescription)")
    }
  }
}
