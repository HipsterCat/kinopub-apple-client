//
//  MediaRecordStore.swift
//  KinoPubAppleClient
//

import Foundation
import KinoPubBackend
import KinoPubLogging
import KinoPubMedia
import OSLog

/// One title as the media model knows it: the merged facts with every source's claims,
/// and what the payload that brought them said about the viewer. No words — a card is
/// worded from this at paint time (docs/media-model.md, step 4).
struct MediaRecord: Codable, Hashable, Sendable {
  var entity: MediaEntity
  /// The payload's word on watched / follow / folders (`ViewerState(reportedBy:)`), for a
  /// reader to lay this device's knowledge over. Not the viewer's state itself.
  var reported: ViewerState
  var updatedAt: Date
}

/// **The one place a title's facts are kept**, under its `MediaRef`. Rows keep refs and
/// read titles from here, so a title on three shelves is one record, and the newest
/// payload for it is what every shelf paints.
///
/// Today it is fed by `ContentStore` with the catalogue titles its rows hold, and pruned
/// to those on every save. The player's `TitleSnapshot` and the detail page move onto it
/// in later slices of step 4.
@MainActor
final class MediaRecordStore {
  private(set) var records: [MediaRef: MediaRecord] = [:]
  private let disk: MediaRecordDisk?

  /// `disk: nil` keeps everything in memory — tests and previews.
  init(disk: MediaRecordDisk? = MediaRecordDisk()) {
    self.disk = disk
    self.records = disk?.load() ?? [:]
  }

  func record(for ref: MediaRef) -> MediaRecord? {
    records[ref]
  }

  /// Takes a kino.pub title in through the model and keeps it under its title ref. The
  /// same merge `MediaCard(_ item:)` runs, so a card built from the record reads the same.
  @discardableResult
  func ingest(_ item: MediaItem, at date: Date = Date()) -> MediaRef {
    let ref = item.titleRef
    let entity = MediaAggregator.merge([item.mediaFragment]) ?? item.mediaFragment.entity
    records[ref] = MediaRecord(entity: entity, reported: ViewerState(reportedBy: item), updatedAt: date)
    return ref
  }

  /// Drops every record no row refers to any more, then writes what is left.
  func keepOnly(_ refs: Set<MediaRef>) {
    records = records.filter { refs.contains($0.key) }
    disk?.save(records)
  }

  func clear() {
    records = [:]
    disk?.clear()
  }
}

/// `MediaRecordStore` on disk: one JSON file in `Caches/`, beside the rows. tvOS purges
/// `Caches/` when the app is not running; a missing file is an empty store.
final class MediaRecordDisk {
  private struct Stored: Codable {
    let ref: MediaRef
    let record: MediaRecord
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

  init(directory: URL? = nil) {
    let dir = directory ?? RowSnapshotStore.defaultDirectory
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    self.fileURL = dir.appendingPathComponent("records-v1.json")
  }

  func load() -> [MediaRef: MediaRecord] {
    guard let data = try? Data(contentsOf: fileURL),
          let stored = try? decoder.decode([Stored].self, from: data) else { return [:] }
    return Dictionary(stored.map { ($0.ref, $0.record) }, uniquingKeysWith: { _, last in last })
  }

  func save(_ records: [MediaRef: MediaRecord]) {
    let stored = records.map { Stored(ref: $0.key, record: $0.value) }
    do {
      try encoder.encode(stored).write(to: fileURL, options: [.atomic])
    } catch {
      Logger.app.error("MediaRecordDisk: save failed: \(error.localizedDescription)")
    }
  }

  var diskUsage: Int64 {
    let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
    return (attributes?[.size] as? Int64) ?? 0
  }

  func clear() {
    try? FileManager.default.removeItem(at: fileURL)
  }
}
