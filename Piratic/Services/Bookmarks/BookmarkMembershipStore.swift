//
//  BookmarkMembershipStore.swift
//  Piratic
//
//  Local item → bookmark-folder membership. The catalogue payload already carries
//  `MediaItem.bookmarks` (and MediaCard.viewerState) — we never need
//  `GET /v1/bookmarks/get-item-folders` just to draw a checkmark. Toggles update
//  this store immediately; server hints fill gaps when the payload had folder ids.
//

import Foundation
import KinoPubBackend
import PiraticUI
import Synchronization

/// Persists which bookmark folders contain which titles. Thread-safe, UserDefaults-backed.
final class BookmarkMembershipStore: Sendable {

  static let shared = BookmarkMembershipStore()

  private let defaultsKey = "com.soda.kinopub.bookmarkMembership"
  private let addedKey = "com.soda.kinopub.bookmarkAddedAt"

  private struct State {
    /// itemID → folderIDs. Absent key = "never touched locally, trust the card/payload hint".
    var map: [Int: Set<Int>] = [:]
    /// itemID → when this device last added it to a folder. kino.pub keeps no such date,
    /// and Continue Watching mixes bookmarks in by it.
    var addedAt: [Int: Date] = [:]
  }

  private let state: Mutex<State>
  private let suite: DefaultsSuite

  init(defaults suite: DefaultsSuite = .standard) {
    self.suite = suite
    state = Mutex(Self.load(from: suite.defaults, mapKey: defaultsKey, addedKey: addedKey))
  }

  /// Resolved membership: local overlay wins; otherwise the server hint from the card/item.
  func folderIDs(for itemID: Int, serverHint: Set<Int> = []) -> Set<Int> {
    state.withLock { $0.map[itemID] } ?? serverHint
  }

  func isBookmarked(_ itemID: Int, serverHint: Set<Int> = []) -> Bool {
    !folderIDs(for: itemID, serverHint: serverHint).isEmpty
  }

  /// Replace membership from a trusted payload (`MediaItem.bookmarks` on detail, etc.).
  /// The folders this device knows the title is in, or nil when it has never been told.
  func knownFolderIDs(for itemID: Int) -> Set<Int>? {
    state.withLock { $0.map[itemID] }
  }

  func replace(itemID: Int, folderIDs: Set<Int>) {
    state.withLock { state in
      state.map[itemID] = folderIDs
      persist(state)
    }
  }

  /// Adopt a non-empty catalogue hint only when we have no local row yet.
  func adoptServerHint(itemID: Int, folderIDs: Set<Int>) {
    guard !folderIDs.isEmpty else { return }
    state.withLock { state in
      guard state.map[itemID] == nil else { return }
      state.map[itemID] = folderIDs
      persist(state)
    }
  }

  /// Seed from a `MediaItem` when the payload included `bookmarks` (even if empty).
  func seed(from item: MediaItem) {
    guard let bookmarks = item.bookmarks else { return }
    replace(itemID: item.id, folderIDs: Set(bookmarks.map(\.id)))
  }

  @discardableResult
  func toggle(itemID: Int, folderID: Int, serverHint: Set<Int> = []) -> Set<Int> {
    state.withLock { state in
      var set = state.map[itemID] ?? serverHint
      if set.contains(folderID) {
        set.remove(folderID)
        if set.isEmpty { state.addedAt[itemID] = nil }
      } else {
        set.insert(folderID)
        state.addedAt[itemID] = Date()
      }
      state.map[itemID] = set
      persist(state)
      return set
    }
  }

  /// When this device added each title to a bookmark folder, for the ones it did.
  func addedDates() -> [Int: Date] {
    state.withLock { $0.addedAt }
  }

  /// Record the date only after kino.pub accepts the optimistic change.
  func confirmToggle(itemID: Int, folderID: Int, addedAt: Date?) {
    state.withLock { state in
      guard let folders = state.map[itemID] else { return }
      if let addedAt, folders.contains(folderID) {
        state.addedAt[itemID] = max(state.addedAt[itemID] ?? .distantPast, addedAt)
      } else if folders.isEmpty {
        state.addedAt[itemID] = nil
      }
      persist(state)
    }
  }

  func clear() {
    state.withLock { state in
      state = State()
      let defaults = suite.defaults
      defaults.removeObject(forKey: defaultsKey)
      defaults.removeObject(forKey: addedKey)
    }
  }

  // MARK: - Persistence

  private static func load(from defaults: UserDefaults, mapKey: String, addedKey: String) -> State {
    var state = State()
    guard let raw = defaults.dictionary(forKey: mapKey) as? [String: [Int]] else { return state }
    for (key, value) in raw {
      guard let id = Int(key) else { continue }
      state.map[id] = Set(value)
    }
    if let rawAdded = defaults.dictionary(forKey: addedKey) as? [String: Double] {
      for (key, value) in rawAdded {
        guard let id = Int(key) else { continue }
        state.addedAt[id] = Date(timeIntervalSince1970: value)
      }
    }
    return state
  }

  /// Holding `state`, so the disk sees writes in the order memory did.
  private func persist(_ state: State) {
    let defaults = suite.defaults
    var raw: [String: [Int]] = [:]
    raw.reserveCapacity(state.map.count)
    for (id, folders) in state.map {
      raw["\(id)"] = folders.sorted()
    }
    defaults.set(raw, forKey: defaultsKey)
    defaults.set(Dictionary(uniqueKeysWithValues: state.addedAt.map { ("\($0.key)", $0.value.timeIntervalSince1970) }),
                 forKey: addedKey)
  }
}

// MARK: - Toggle

/// The one way a title goes into or out of a bookmark folder, wherever the control is:
/// the detail page's Bookmark menu, the Home hero's, a card's context menu. Membership
/// flips here at once, the HUD says what happened, kino.pub is told, and a failure puts
/// the old membership back. Two copies of this (detail and cards) had drifted: one
/// showed the HUD, the other did not (Sasha, 2026-10-25).
@MainActor
enum BookmarkFolderToggle {
  /// Flips `folderID` for `itemID`, starting from `current`. Returns the new membership
  /// and the HUD to show; `onFailure` gets the membership put back and the error.
  static func toggle(itemID: Int,
                     folderID: Int,
                     current: Set<Int>,
                     service: VideoContentService,
                     contentStore: ContentStore,
                     membership: BookmarkMembershipStore = .shared,
                     onFailure: @escaping @MainActor (Set<Int>, Error) -> Void) -> (folderIDs: Set<Int>, hud: HudToast) {
    var next = current
    let added = next.insert(folderID).inserted
    if !added { next.remove(folderID) }
    let addedAt = added ? Date() : nil
    membership.replace(itemID: itemID, folderIDs: next)
    Task {
      do {
        try await service.toggleBookmark(itemId: itemID, folderId: folderID)
        membership.confirmToggle(itemID: itemID, folderID: folderID, addedAt: addedAt)
        BookmarkFoldersStore.shared.invalidate()
        contentStore.invalidateBookmarkMembership()
      } catch {
        membership.replace(itemID: itemID, folderIDs: current)
        onFailure(current, error)
      }
    }
    let hud = added
      ? HudToast(systemImage: "bookmark.fill", title: "Bookmarked".localized)
      : HudToast(systemImage: "bookmark", title: "Removed".localized)
    return (next, hud)
  }
}
