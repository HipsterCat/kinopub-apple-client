//
//  ContentStore.swift
//  KinoPubAppleClient
//

import Foundation
import KinoPubBackend
import KinoPubMedia
import KinoPubUI
import OSLog
import KinoPubLogging

/// Owns Home/Library rows so views stop re-fetching them on every tab switch. Views
/// read `cards(_:)` synchronously (paints instantly, even offline); callers kick
/// `refreshIfStale`/`refresh` in the background and read again once it resolves.
///
/// **A row keeps refs; a title's card is worded when the row is read.** A fetch that
/// hands kino.pub titles (`RowItem.title`) puts each into `MediaRecordStore` and keeps
/// only its ref, so a title on several rows is one record and paints the newest payload
/// everywhere. Rows still built from other payloads keep ready-made cards (`.card`).
///
/// **What the viewer has done is read at paint time, not cached.** A title's poster card
/// comes out of `cards(_:)` with watched, progress, follow and folders from `ViewerState`
/// — this device's marks over the payload's word — so a row served from disk never shows
/// yesterday's state. Episode cards (Continue Watching, history) are left to their own
/// rows, which already offer and paint the episode (`ContinueWatchingLocalOverlay`).
///
/// Local mutations (`setItems`, `removeCard`) bump a generation so a slower in-flight
/// fetch that started before them cannot write back over the newer row.
@MainActor
final class ContentStore {
  private(set) var rows: [RowKey: RowState] = [:]
  /// Last refresh failure per key, in memory only. Lets a caller with nothing cached
  /// tell "empty because the fetch failed" apart from "empty because there's genuinely
  /// nothing" — the store itself never surfaces errors, it keeps the stale row.
  private(set) var lastErrors: [RowKey: Error] = [:]
  private var inFlight: [RowKey: Task<Void, Never>] = [:]
  /// Bumped on invalidate / local mutation. An in-flight fetch captures the value
  /// at start and must not write if it changed — that is how "the app requested
  /// constantly but the row never changed": the stale decode landed after a newer
  /// invalidate and stamped `fetchedAt = now`.
  private var generation: [RowKey: Int] = [:]
  private let disk: RowSnapshotStore
  let records: MediaRecordStore
  /// Nil in tests and previews: the cards come out with what their payload reported.
  private let viewer: ViewerStateReading?

  private static let kinopubWideArtworkMigrationKey = "ContentStore.kinopubWideArtwork.v1"

  init(disk: RowSnapshotStore = RowSnapshotStore(),
       records: MediaRecordStore = MediaRecordStore(),
       viewer: ViewerStateReading? = nil) {
    self.disk = disk
    self.records = records
    self.viewer = viewer
    self.rows = disk.loadAll()
    migrateKinopubWideArtworkIfNeeded()
  }

  /// Records cached before `kinopubWideSpecified` / `backdropFromSpecifiedWide` existed
  /// read as ineligible for the hero until catalogue rows refresh and re-ingest.
  private func migrateKinopubWideArtworkIfNeeded() {
    guard !UserDefaults.standard.bool(forKey: Self.kinopubWideArtworkMigrationKey) else { return }
    invalidate(family: .catalog)
    UserDefaults.standard.set(true, forKey: Self.kinopubWideArtworkMigrationKey)
  }

  // MARK: - Reading (synchronous, from memory)

  func cards(_ key: RowKey) -> [MediaCard] {
    (rows[key]?.entries ?? []).compactMap(card(for:))
  }

  /// Every card the store holds, row by row — for searching what is already on screen.
  var allCards: [MediaCard] {
    rows.values.flatMap { $0.entries.compactMap(card(for:)) }
  }

  /// A title's card from its record and the viewer's state now. Nil only for a ref whose
  /// record is gone, which a save never leaves behind.
  private func card(for entry: RowEntry) -> MediaCard? {
    switch entry {
    case .title(let ref):
      guard let record = records.record(for: ref) else { return nil }
      let card = MediaCard(ref: ref,
                           entity: record.entity,
                           state: record.reported,
                           kinopubWideSpecified: record.kinopubWideSpecified)
      // The same two steps a cached card took: the payload's card, then today's state
      // over it (the card's builder does not fill watched or progress).
      guard let viewer else { return card }
      return card.withViewerState(viewer.state(for: ref, reported: record.reported))
    case .card(let card):
      guard let viewer, !card.opensCollection, card.ref.kind == .title else { return card }
      return card.withViewerState(viewer.state(for: card.ref, reported: card.reportedState))
    }
  }

  func lastError(_ key: RowKey) -> Error? {
    lastErrors[key]
  }

  /// When the row was last fetched; nil when nothing is cached. An invalidated row reads
  /// `.distantPast` until it is fetched again.
  func fetchedAt(_ key: RowKey) -> Date? {
    rows[key]?.fetchedAt
  }

  func isStale(_ key: RowKey) -> Bool {
    guard let state = rows[key] else { return true }
    return Date().timeIntervalSince(state.fetchedAt) > key.ttl
  }

  // MARK: - Refreshing

  /// Runs `fetch` only when the cached row is missing or past its TTL. Callers that
  /// need the resolved cards afterward should read `cards(_:)` again — this just
  /// waits for whichever attempt (this one or one already in flight) to finish.
  func refreshIfStale(_ key: RowKey, fetch: @escaping @Sendable () async throws -> [RowItem]) async {
    guard isStale(key) else { return }
    await refresh(key, fetch: fetch)
  }

  /// Unconditional refresh (pull-to-refresh). Two callers asking for the same key at
  /// once share one network request instead of firing two — unless that request was
  /// superseded by an invalidate, in which case we start another.
  func refresh(_ key: RowKey, fetch: @escaping @Sendable () async throws -> [RowItem]) async {
    while true {
      if let existing = inFlight[key] {
        let gen = generation[key] ?? 0
        await existing.value
        if (generation[key] ?? 0) != gen { continue }
        return
      }
      let gen = generation[key] ?? 0
      let task = Task { [weak self] in
        guard let self else { return }
        await self.performFetch(key, fetch: fetch)
      }
      inFlight[key] = task
      await task.value
      inFlight[key] = nil
      // Discarded write (invalidate while we were in flight): the row is still stale.
      // A coalesced waiter already retries; a single caller must too, or Home paints
      // the snapshot it just asked the network to replace.
      if (generation[key] ?? 0) != gen { continue }
      return
    }
  }

  private func performFetch(_ key: RowKey, fetch: @Sendable () async throws -> [RowItem]) async {
    let gen = generation[key] ?? 0
    do {
      let items = try await fetch()
      guard (generation[key] ?? 0) == gen else { return }
      rows[key] = RowState(entries: entries(items), fetchedAt: Date())
      lastErrors[key] = nil
      save()
    } catch {
      // Leave whatever's cached alone: a stale row beats a blank one. Cancellations
      // (superseded by a newer request) don't count as failures.
      let cancelled = (error as? APIClientError)?.isCancellation == true || error is CancellationError
      if !cancelled {
        lastErrors[key] = error
      }
      Logger.app.debug("ContentStore: refresh failed for \(String(describing: key)), keeping cached value: \(error)")
    }
  }

  // MARK: - Local mutation

  /// Overwrite a row with a value we already know is current — e.g. after composing
  /// it from several endpoints. Counts as freshly fetched.
  func setItems(_ items: [RowItem], for key: RowKey) {
    bump(key)
    rows[key] = RowState(entries: entries(items), fetchedAt: Date())
    save()
  }

  /// Append the next page of a paginated row.
  ///
  /// **`fetchedAt` is deliberately left alone.** Appending is not a refresh: if every
  /// loaded page pushed the timestamp forward, a row the user keeps scrolling would
  /// never go stale and would stop refreshing entirely. The TTL still measures from
  /// when page 1 landed, and a refresh legitimately returns the row to page 1.
  ///
  /// Deduplicates by id — kino.pub can repeat an item across page boundaries when the
  /// catalog shifts under the cursor, and a duplicate id in a `ForEach` is a silent
  /// SwiftUI defect, not a cosmetic one.
  func appendItems(_ items: [RowItem], for key: RowKey) {
    guard var state = rows[key] else {
      setItems(items, for: key)
      return
    }
    let known = Set(state.entries.map(\.id))
    let fresh = entries(items).filter { !known.contains($0.id) }
    guard !fresh.isEmpty else { return }
    state.entries.append(contentsOf: fresh)
    rows[key] = state
    save()
  }

  /// Optimistic removal: the card disappears immediately, before the network call
  /// that caused it (hide/mark watched/...) even returns.
  func removeCard(id: Int, from key: RowKey) {
    guard var state = rows[key] else { return }
    bump(key)
    state.entries.removeAll { $0.id == id }
    state.fetchedAt = Date()
    rows[key] = state
    save()
  }

  // MARK: - Records

  /// A fuller payload for a title a row already shows — the detail page's, once it has
  /// loaded. The rows paint it the next time they are read. A title no row shows is not
  /// kept: the store holds what the rows refer to.
  func refreshRecord(with item: MediaItem) {
    guard records.record(for: item.titleRef) != nil else { return }
    records.ingest(item)
    save()
  }

  /// Titles go into the record store, rows keep their refs.
  private func entries(_ items: [RowItem]) -> [RowEntry] {
    items.map { item in
      switch item {
      case .title(let title): return .title(records.ingest(title))
      case .card(let card): return .card(card)
      }
    }
  }

  /// Rows and the records they refer to are written together, and a record no row
  /// refers to any more goes with them.
  private func save() {
    disk.saveAll(rows)
    let refs = rows.values.flatMap(\.entries).compactMap { entry -> MediaRef? in
      if case .title(let ref) = entry { return ref }
      return nil
    }
    records.keepOnly(Set(refs))
  }

  // MARK: - Invalidation

  /// After an action taken elsewhere (toggle bookmark on the detail page, mark
  /// watched, ...) that this store can't see directly: force every row in the family
  /// to refetch next time it's asked for, instead of waiting out its TTL.
  func invalidate(family: RowKey.Family) {
    var didWatch = false
    for key in rows.keys where key.family == family {
      bump(key)
      rows[key]?.fetchedAt = .distantPast
      if family == .watch { didWatch = true }
    }
    if didWatch {
      NotificationCenter.default.post(name: .contentStoreDidInvalidateWatch, object: nil)
    }
  }

  /// The same, for named rows only — when one family member must refetch and the rest
  /// (Home's Continue Watching, which overlays local progress itself) must not.
  func invalidate(_ keys: [RowKey]) {
    var didWatch = false
    for key in keys {
      bump(key)
      rows[key]?.fetchedAt = .distantPast
      if key.family == .watch { didWatch = true }
    }
    if didWatch {
      NotificationCenter.default.post(name: .contentStoreDidInvalidateWatch, object: nil)
    }
  }

  private func bump(_ key: RowKey) {
    generation[key, default: 0] += 1
  }
}

extension Notification.Name {
  /// Posted when a `.watch` row is invalidated (mark watched, hide, pull-to-refresh).
  /// Home refetches Continue Watching; painting from the cached snapshot is not enough.
  static let contentStoreDidInvalidateWatch = Notification.Name("KinoPub.contentStoreDidInvalidateWatch")
}
