//
//  LocalWatchProgressStore.swift
//  KinoPubAppleClient
//
//  Tracks watch progress locally so "Continue Watching", the detail page and the season
//  rail can show what the player just did, before (or without) the backend recording it.
//
//  Reads are synchronous from memory; every write is queued to `WatchLibraryWriter`
//  and persisted with SwiftData in `Caches/` (see `WatchLibrary`).
//
//  Two rules keep it race-free:
//  - A write is queued inside the same lock that changes memory, so the disk sees
//    writes in the order memory did. Queued after `unlock()`, two writers could swap
//    places: progress rolled back after a relaunch, or a cleared title came back.
//  - A payload is encoded where the item is handed in (`cacheItem`, on the main
//    actor), never from the player's tick. `MediaItem` holds `Season`/`Episode`
//    classes the detail page updates in place on the main thread; the tick runs on a
//    background queue (`PlayerTimeObserver`) and must not read them.
//

import Foundation
import KinoPubBackend
import KinoPubLogging
import OSLog
import SwiftData

extension Notification.Name {
  /// Posted after a local resume point is written or cleared. Home and the detail page
  /// repaint from this without invalidating `ContentStore` — the row's TTL is the server
  /// snapshot, not the playhead.
  static let localWatchProgressDidChange = Notification.Name("KinoPub.localWatchProgressDidChange")
}

/// A locally persisted resume point for a media item (or a specific episode of a series).
public struct LocalWatchEntry: Codable, Identifiable {
  public let item: MediaItem
  public var position: Double
  public var duration: Double
  public var season: Int?
  public var episode: Int?
  public var updatedAt: Double

  public var id: Int { item.id }

  /// Watch classification for this resume point — the single source of truth (fraction / finished).
  public var watch: WatchProgress { WatchProgress(position: position, duration: duration) }
  public var progress: Double? { watch.resumeFraction }
  public var finished: Bool { watch.isFinished }
}

protocol LocalWatchProgressProvider {
  var localProgressStore: LocalWatchProgressStore { get }
}

/// Thread-safe store of local resume points, backed by SwiftData.
final class LocalWatchProgressStore: @unchecked Sendable {

  /// Minimum playback before an item is considered "started" and worth resuming — the shared
  /// `WatchProgress` floor, so the local store and the classifier never disagree.
  static let minimumSeconds: Double = WatchProgress.startedSeconds

  private enum Write: Sendable {
    case record(WatchRecordValue)
    case snapshot(itemID: Int, payload: Data)
    case deleteAll(itemID: Int)
    case flush(CheckedContinuation<Void, Never>)
  }

  private let lock = NSLock()
  /// Payloads of titles the user opened this session, plus the persisted ones for titles
  /// that have a resume point (so episode playback, whose `PlayableItem` is an `Episode`,
  /// can still resolve the parent series artwork after a relaunch).
  private var snapshots: [Int: MediaItem] = [:]
  /// Each snapshot's JSON, encoded in `cacheItem` (or read back from disk).
  private var payloads: [Int: Data] = [:]
  /// Titles whose current payload is already on disk — the player writes every ~10s,
  /// and rewriting the same payload on each tick would be pure waste.
  private var persistedSnapshotIDs: Set<Int> = []
  /// One per episode (series) or per title (film), keyed by `WatchRecord.key`.
  private var records: [String: WatchRecordValue] = [:]

  private let writes: AsyncStream<Write>.Continuation

  init(container: ModelContainer = WatchLibrary.makeContainer()) {
    let (stream, continuation) = AsyncStream<Write>.makeStream()
    writes = continuation
    load(from: container)
    importLegacyJSON()

    // One consumer, so writes land in the order they were made.
    let writer = WatchLibraryWriter(modelContainer: container)
    Task.detached(priority: .utility) {
      for await write in stream {
        switch write {
        case .record(let value):
          await writer.upsert(value)
        case .snapshot(let itemID, let payload):
          await writer.upsertSnapshot(itemID: itemID, payload: payload)
        case .deleteAll(let itemID):
          await writer.deleteAll(itemID: itemID)
        case .flush(let continuation):
          continuation.resume()
        }
      }
    }
  }

  /// Remember the artwork/title for an item the user is browsing. In memory only; the
  /// payload reaches disk with the title's first resume point.
  @MainActor
  func cacheItem(_ item: MediaItem) {
    let payload = try? JSONEncoder().encode(item)
    lock.lock(); defer { lock.unlock() }
    snapshots[item.id] = item
    guard let payload, payloads[item.id] != payload else { return }
    payloads[item.id] = payload
    // A newer payload than the one on disk goes out with the next write.
    persistedSnapshotIDs.remove(item.id)
  }

  /// The cached payload for an item, when the user has browsed it this session or it has
  /// a resume point. An `Episode` carries no genres or countries, so track selection
  /// reads them from here.
  func snapshot(for id: Int) -> MediaItem? {
    lock.lock(); defer { lock.unlock() }
    return snapshots[id]
  }

  /// Record a resume point. No-op for live/trailers (non-finite duration) or before the
  /// minimum threshold, or when we have no snapshot to render a card with.
  ///
  /// `position < duration` keeps the exact end-of-file tick for `recordFinished`.
  /// A position already inside the credits window is still written;
  /// `WatchProgress` classifies it as finished on read, so Continue Watching
  /// does not grow a resume bar from it.
  func recordProgress(mediaId: Int, position: Double, duration: Double, season: Int?, episode: Int?) {
    guard duration.isFinite, duration > 0, position < duration else { return }
    let watch = WatchProgress(position: position, duration: duration)
    guard watch.hasStarted else { return }
    if write(mediaId: mediaId, position: position, duration: duration, season: season, episode: episode) {
      notify()
    }
  }

  /// End of playback: keep a finished tombstone so Continue Watching can hide a film
  /// or step a series to the next episode without waiting out Home's TTL, and without
  /// `ContentStore.invalidate(.watch)`.
  func recordFinished(mediaId: Int, duration: Double, season: Int?, episode: Int?) {
    guard duration.isFinite, duration > 0 else { return }
    if write(mediaId: mediaId, position: duration, duration: duration, season: season, episode: episode) {
      notify()
    }
  }

  /// The resume entry for an item, if any (and past the minimum threshold).
  /// A movie (`season == nil`) matches by id alone — there's a single resume point per movie, and
  /// keying it by `episode` (derived from a flaky `videos.first.number`) doesn't round-trip reliably.
  /// A series episode requires an exact `(season, episode)` match.
  func entry(forId id: Int, season: Int?, episode: Int?) -> LocalWatchEntry? {
    lock.lock(); defer { lock.unlock() }
    let key = WatchRecord.key(itemID: id, season: season, episode: episode)
    guard let record = records[key], record.watch.isResumable else { return nil }
    return entryLocked(for: record)
  }

  /// The newest resume point per title, most-recently-watched first. Includes finished
  /// tombstones — Home's overlay needs them to hide a film / advance a series before the
  /// server row refreshes.
  func allEntries() -> [LocalWatchEntry] {
    lock.lock(); defer { lock.unlock() }
    var newest: [Int: WatchRecordValue] = [:]
    for record in records.values where record.watch.state != .unwatched {
      if let existing = newest[record.itemID], existing.updatedAt >= record.updatedAt { continue }
      newest[record.itemID] = record
    }
    return newest.values
      .sorted { $0.updatedAt > $1.updatedAt }
      .compactMap(entryLocked(for:))
  }

  /// Every resume point written for one title — each episode the player touched, not just
  /// the newest. The detail page lays these over its payload.
  func records(forItem itemID: Int) -> [WatchRecordValue] {
    lock.lock(); defer { lock.unlock() }
    return records.values.filter { $0.itemID == itemID }
  }

  func clear(id: Int) {
    lock.lock()
    let keys = records.values.filter { $0.itemID == id }.map(\.key)
    keys.forEach { records[$0] = nil }
    persistedSnapshotIDs.remove(id)
    if !keys.isEmpty { writes.yield(.deleteAll(itemID: id)) }
    lock.unlock()
    guard !keys.isEmpty else { return }
    notify()
  }

  /// Returns once every write queued before it is on disk. Tests only.
  func flush() async {
    await withCheckedContinuation { writes.yield(.flush($0)) }
  }

  // MARK: - Writing

  /// Returns false when there is no payload to draw a card from — the same rule as before.
  private func write(mediaId: Int, position: Double, duration: Double, season: Int?, episode: Int?) -> Bool {
    lock.lock(); defer { lock.unlock() }
    guard snapshots[mediaId] != nil else { return false }
    let value = WatchRecordValue(itemID: mediaId,
                                 season: season,
                                 episode: episode,
                                 position: position,
                                 duration: duration,
                                 updatedAt: Date())
    records[value.key] = value
    writes.yield(.record(value))
    if let payload = payloads[mediaId], persistedSnapshotIDs.insert(mediaId).inserted {
      writes.yield(.snapshot(itemID: mediaId, payload: payload))
    }
    return true
  }

  /// Must be called with `lock` held.
  private func entryLocked(for record: WatchRecordValue) -> LocalWatchEntry? {
    guard let item = snapshots[record.itemID] else { return nil }
    return LocalWatchEntry(item: item,
                           position: record.position,
                           duration: record.duration,
                           season: record.season,
                           episode: record.episode,
                           updatedAt: record.updatedAt.timeIntervalSince1970)
  }

  // MARK: - Loading

  /// Synchronous on purpose: Home paints Continue Watching from this on its first frame.
  /// A throwaway context on this thread; the writer owns its own.
  private func load(from container: ModelContainer) {
    let context = ModelContext(container)
    let decoder = JSONDecoder()
    do {
      for snapshot in try context.fetch(FetchDescriptor<TitleSnapshot>()) {
        if let item = try? decoder.decode(MediaItem.self, from: snapshot.payload) {
          snapshots[snapshot.itemID] = item
          payloads[snapshot.itemID] = snapshot.payload
          persistedSnapshotIDs.insert(snapshot.itemID)
        }
      }
      for record in try context.fetch(FetchDescriptor<WatchRecord>()) {
        let value = WatchRecordValue(itemID: record.itemID,
                                     season: record.season,
                                     episode: record.episode,
                                     position: record.position,
                                     duration: record.duration,
                                     updatedAt: record.updatedAt)
        records[value.key] = value
      }
    } catch {
      Logger.app.error("LocalWatchProgressStore: load failed: \(error.localizedDescription)")
    }
  }

  /// The JSON file the store used before SwiftData, in `Documents/` (iOS/macOS only —
  /// tvOS could never write it). Imported once, then deleted.
  private func importLegacyJSON() {
    guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    else { return }
    let url = documents.appendingPathComponent("local_watch_progress.json")
    guard let data = try? Data(contentsOf: url) else { return }
    defer { try? FileManager.default.removeItem(at: url) }
    guard let legacy = try? JSONDecoder().decode([LocalWatchEntry].self, from: data) else { return }

    for entry in legacy {
      let value = WatchRecordValue(itemID: entry.id,
                                   season: entry.season,
                                   episode: entry.episode,
                                   position: entry.position,
                                   duration: entry.duration,
                                   updatedAt: Date(timeIntervalSince1970: entry.updatedAt))
      if let existing = records[value.key], existing.updatedAt >= value.updatedAt { continue }
      records[value.key] = value
      snapshots[entry.id] = entry.item
      writes.yield(.record(value))
      // Still in `init`: nothing else holds these items yet.
      if let payload = try? JSONEncoder().encode(entry.item) {
        payloads[entry.id] = payload
        persistedSnapshotIDs.insert(entry.id)
        writes.yield(.snapshot(itemID: entry.id, payload: payload))
      }
    }
    Logger.app.info("LocalWatchProgressStore: imported \(legacy.count) legacy resume points")
  }

  private func notify() {
    NotificationCenter.default.post(name: .localWatchProgressDidChange, object: nil)
  }
}
