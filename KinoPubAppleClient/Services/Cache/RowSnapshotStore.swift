//
//  RowSnapshotStore.swift
//  KinoPubAppleClient
//

import Foundation
import KinoPubBackend
import KinoPubLogging
import KinoPubMedia
import KinoPubUI
import OSLog

/// One place in a row. A title is only its ref — its facts are in `MediaRecordStore` and
/// its card is worded when the row is read. Everything not yet on the model (episode
/// cards, collections, `/v1/watching` and history tiles) is still a ready-made card.
enum RowEntry: Codable, Hashable {
  case title(MediaRef)
  case card(MediaCard)

  /// What the row deduplicates and removes by — the card's id, a title's item id.
  var id: Int {
    switch self {
    case .title(let ref): return ref.itemID
    case .card(let card): return card.id
    }
  }
}

/// What a row's fetch hands `ContentStore`: a kino.pub title, which the store keeps as a
/// record + ref, or a card that is not on the model yet.
enum RowItem {
  case title(MediaItem)
  case card(MediaCard)
}

/// One cached row: its entries and when they were last fetched. No pagination here —
/// these are the fixed-size summary rows on Home/Library, not the paginated grids.
struct RowState: Codable {
  var entries: [RowEntry]
  var fetchedAt: Date
}

/// Persists `ContentStore`'s rows to a single JSON file in `Caches/`, so a cold start
/// paints yesterday's rows before the network answers. `Caches/` is purged by the OS
/// when the app isn't running (tvOS in particular) — that's fine, the store treats a
/// missing snapshot exactly like an empty one and refetches.
final class RowSnapshotStore {
  private struct StoredRow: Codable {
    let key: RowKey
    let state: RowState
  }

  private let fileURL: URL
  private let encoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return encoder
  }()
  private let decoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }()

  /// The rows written before titles became refs: plain cards. Read once, as `.card`
  /// entries, so the first launch after the change still paints yesterday's rows.
  private struct LegacyRow: Codable {
    struct State: Codable {
      var cards: [MediaCard]
      var fetchedAt: Date
    }
    let key: RowKey
    let state: State
  }

  static var defaultDirectory: URL {
    let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
      ?? URL(fileURLWithPath: NSTemporaryDirectory())
    return caches.appendingPathComponent("KinoPubContentStore", isDirectory: true)
  }

  private let legacyURL: URL

  init(directory: URL? = nil) {
    let dir = directory ?? Self.defaultDirectory
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    // Versioned filename. A snapshot written before `MediaCard.watchedAt` existed
    // decodes cleanly with a nil date, which is worse than not decoding at all: the
    // whole history list silently files itself under "Earlier" until the TTL expires.
    // Bumping the name retires those snapshots instead of reasoning about them.
    self.fileURL = dir.appendingPathComponent("rows-v3.json")
    self.legacyURL = dir.appendingPathComponent("rows-v2.json")
  }

  func loadAll() -> [RowKey: RowState] {
    if let data = try? Data(contentsOf: fileURL),
       let stored = try? decoder.decode([StoredRow].self, from: data) {
      return Dictionary(uniqueKeysWithValues: stored.map { ($0.key, $0.state) })
    }
    guard let data = try? Data(contentsOf: legacyURL),
          let legacy = try? decoder.decode([LegacyRow].self, from: data) else { return [:] }
    return Dictionary(uniqueKeysWithValues: legacy.map {
      ($0.key, RowState(entries: $0.state.cards.map(RowEntry.card), fetchedAt: $0.state.fetchedAt))
    })
  }

  func saveAll(_ rows: [RowKey: RowState]) {
    let stored = rows.map { StoredRow(key: $0.key, state: $0.value) }
    do {
      let data = try encoder.encode(stored)
      try data.write(to: fileURL, options: [.atomic])
      try? FileManager.default.removeItem(at: legacyURL)
    } catch {
      Logger.app.error("RowSnapshotStore: save failed: \(error.localizedDescription)")
    }
  }

  /// Bytes on disk — for the Settings storage screen. 0 when there is no snapshot yet.
  var diskUsage: Int64 {
    let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
    return (attributes?[.size] as? Int64) ?? 0
  }

  /// Deletes the snapshot file. The next `loadAll()` simply sees an empty cache and refetches.
  func clear() {
    try? FileManager.default.removeItem(at: fileURL)
    try? FileManager.default.removeItem(at: legacyURL)
  }
}
