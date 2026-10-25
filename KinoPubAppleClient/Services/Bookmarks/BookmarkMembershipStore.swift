//
//  BookmarkMembershipStore.swift
//  KinoPubAppleClient
//
//  Local item → bookmark-folder membership. The catalogue payload already carries
//  `MediaItem.bookmarks` (and MediaCard.viewerState) — we never need
//  `GET /v1/bookmarks/get-item-folders` just to draw a checkmark. Toggles update
//  this store immediately; server hints fill gaps when the payload had folder ids.
//

import Foundation
import KinoPubBackend
import KinoPubUI

/// Persists which bookmark folders contain which titles. Thread-safe, UserDefaults-backed.
/// `@unchecked Sendable` because every mutation of `map` goes through `lock`.
final class BookmarkMembershipStore: @unchecked Sendable {

  static let shared = BookmarkMembershipStore()

  private let defaultsKey = "com.soda.kinopub.bookmarkMembership"
  private let addedKey = "com.soda.kinopub.bookmarkAddedAt"
  private let lock = NSLock()
  /// itemID → folderIDs. Absent key = "never touched locally, trust the card/payload hint".
  private var map: [Int: Set<Int>] = [:]
  /// itemID → when this device last added it to a folder. kino.pub keeps no such date,
  /// and Continue Watching mixes bookmarks in by it.
  private var addedAt: [Int: Date] = [:]

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    load()
  }

  private let defaults: UserDefaults

  /// Resolved membership: local overlay wins; otherwise the server hint from the card/item.
  func folderIDs(for itemID: Int, serverHint: Set<Int> = []) -> Set<Int> {
    lock.lock(); defer { lock.unlock() }
    return map[itemID] ?? serverHint
  }

  func isBookmarked(_ itemID: Int, serverHint: Set<Int> = []) -> Bool {
    lock.lock(); defer { lock.unlock() }
    return !(map[itemID] ?? serverHint).isEmpty
  }

  /// Replace membership from a trusted payload (`MediaItem.bookmarks` on detail, etc.).
  /// The folders this device knows the title is in, or nil when it has never been told.
  func knownFolderIDs(for itemID: Int) -> Set<Int>? {
    lock.lock(); defer { lock.unlock() }
    return map[itemID]
  }

  func replace(itemID: Int, folderIDs: Set<Int>) {
    lock.lock(); defer { lock.unlock() }
    map[itemID] = folderIDs
    persistLocked()
  }

  /// Adopt a non-empty catalogue hint only when we have no local row yet.
  func adoptServerHint(itemID: Int, folderIDs: Set<Int>) {
    guard !folderIDs.isEmpty else { return }
    lock.lock(); defer { lock.unlock() }
    guard map[itemID] == nil else { return }
    map[itemID] = folderIDs
    persistLocked()
  }

  /// Seed from a `MediaItem` when the payload included `bookmarks` (even if empty).
  func seed(from item: MediaItem) {
    guard let bookmarks = item.bookmarks else { return }
    replace(itemID: item.id, folderIDs: Set(bookmarks.map(\.id)))
  }

  @discardableResult
  func toggle(itemID: Int, folderID: Int, serverHint: Set<Int> = []) -> Set<Int> {
    lock.lock(); defer { lock.unlock() }
    var set = map[itemID] ?? serverHint
    if set.contains(folderID) {
      set.remove(folderID)
      if set.isEmpty { addedAt[itemID] = nil }
    } else {
      set.insert(folderID)
      addedAt[itemID] = Date()
    }
    map[itemID] = set
    persistLocked()
    return set
  }

  /// When this device added each title to a bookmark folder, for the ones it did.
  func addedDates() -> [Int: Date] {
    lock.lock(); defer { lock.unlock() }
    return addedAt
  }

  func clear() {
    lock.lock(); defer { lock.unlock() }
    map = [:]
    addedAt = [:]
    defaults.removeObject(forKey: defaultsKey)
    defaults.removeObject(forKey: addedKey)
  }

  // MARK: - Persistence

  private func load() {
    guard let raw = defaults.dictionary(forKey: defaultsKey) as? [String: [Int]] else { return }
    var loaded: [Int: Set<Int>] = [:]
    for (key, value) in raw {
      guard let id = Int(key) else { continue }
      loaded[id] = Set(value)
    }
    map = loaded
    if let rawAdded = defaults.dictionary(forKey: addedKey) as? [String: Double] {
      for (key, value) in rawAdded {
        guard let id = Int(key) else { continue }
        addedAt[id] = Date(timeIntervalSince1970: value)
      }
    }
  }

  private func persistLocked() {
    var raw: [String: [Int]] = [:]
    raw.reserveCapacity(map.count)
    for (id, folders) in map {
      raw["\(id)"] = folders.sorted()
    }
    defaults.set(raw, forKey: defaultsKey)
    defaults.set(Dictionary(uniqueKeysWithValues: addedAt.map { ("\($0.key)", $0.value.timeIntervalSince1970) }),
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
    membership.replace(itemID: itemID, folderIDs: next)
    Task {
      do {
        try await service.toggleBookmark(itemId: itemID, folderId: folderID)
        contentStore.invalidate(family: .bookmarks)
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
