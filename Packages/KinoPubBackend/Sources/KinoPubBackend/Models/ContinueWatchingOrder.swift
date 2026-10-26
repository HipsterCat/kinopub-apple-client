//
//  ContinueWatchingOrder.swift
//
//

import Foundation

/// Ordering rules for the home screen's "continue watching" row.
///
/// **Native first** (Sasha, 2026-10-26): kino.pub already has Continue Watching.
/// `/v1/watching/movies` and `/v1/watching/serials?subscribed=1` *are* the row.
/// `/v1/watching/serials?subscribed=0` is every unfinished series on the account —
/// hundreds, for a long-lived one — and only a title still touched within
/// ``abandonedAfter`` stays. `/v1/history` and this device's resume are dates
/// (and a gap-fill for a title the lists have not caught yet), not the backbone.
///
/// **Where the dates come from** (probed live 2026-10-25): the watching lists
/// carry no timestamp. "Watched when" is the newer of `/v1/history` (newest row
/// per title, so an unstarted next episode inherits the series' last play) and
/// this device's `updatedAt`. A stale Apple TV playhead must not beat a later
/// watch on the phone.
public enum ContinueWatchingOrder {

  /// How long the row is allowed to be. The Library tab holds the whole watching
  /// list, which is where the row's chevron goes.
  public static let maxItems: Int = 20

  /// Titles last touched longer ago than this leave the row, unless they are on
  /// the native lists (unfinished movies, followed series). Ninety days is long
  /// enough to resume a show after a break and short enough to drop years-old
  /// junk from `subscribed=0`.
  public static let abandonedAfter: TimeInterval = 90 * 24 * 60 * 60

  /// A sample that never cleared ``WatchProgress/enterContinueWatchingSeconds``
  /// drops off after this, even from the native lists — sampling is not continuing.
  public static let barelyStartedAfter: TimeInterval = 14 * 24 * 60 * 60

  /// One local resume point, for merging into history recency.
  public struct LocalResume: Equatable, Sendable {
    public var id: Int
    public var updatedAt: Date
    public var position: Double?

    public init(id: Int, updatedAt: Date, position: Double? = nil) {
      self.id = id
      self.updatedAt = updatedAt
      self.position = position
    }
  }

  /// Recency the row ranks and filters by: newest play per title.
  public struct Recency: Equatable, Sendable {
    public var lastSeen: [Int: Date]
    public var position: [Int: Double]

    public init(lastSeen: [Int: Date], position: [Int: Double] = [:]) {
      self.lastSeen = lastSeen
      self.position = position
    }
  }

  /// The newer of two dates. Nil loses to a real date.
  public static func newer(_ a: Date?, _ b: Date?) -> Date? {
    switch (a, b) {
    case let (x?, y?): return max(x, y)
    case let (x?, nil): return x
    case let (nil, y?): return y
    case (nil, nil): return nil
    }
  }

  /// Fold this device's resume into history-derived dates. A stale local
  /// `updatedAt` must not overwrite a later `/v1/history` `last_seen` — that is
  /// how a series watched on the phone sank or looked abandoned on the Apple TV.
  /// Local position is trusted only when local also won the date.
  public static func mergingLocalResume(lastSeen: [Int: Date],
                                        position: [Int: Double] = [:],
                                        local: [LocalResume]) -> Recency {
    var lastSeen = lastSeen
    var position = position
    for entry in local {
      if let current = lastSeen[entry.id], entry.updatedAt < current { continue }
      lastSeen[entry.id] = entry.updatedAt
      if let value = entry.position { position[entry.id] = value }
    }
    return Recency(lastSeen: lastSeen, position: position)
  }

  /// History plus local resume, already collapsed per title.
  public static func recency(history: [HistoryEntry],
                             local: [LocalResume] = []) -> Recency {
    mergingLocalResume(lastSeen: lastSeenByItemID(history),
                       position: positionByItemID(history),
                       local: local)
  }

  /// Whether this title still belongs on Continue Watching.
  ///
  /// Native list members (unfinished movies, `subscribed=1`) stay without a
  /// date. Everything else — `subscribed=0`, history, this device — needs a
  /// date within ``abandonedAfter``. A sample shorter than
  /// ``WatchProgress/enterContinueWatchingSeconds`` drops after
  /// ``barelyStartedAfter``, including from the native lists.
  public static func isKept(_ item: WatchingItem,
                            isNative: Bool,
                            lastSeen: Date?,
                            position: Double?,
                            now: Date = Date()) -> Bool {
    if let lastSeen, now >= lastSeen {
      let age = now.timeIntervalSince(lastSeen)
      if let position, position < WatchProgress.enterContinueWatchingSeconds,
         age > barelyStartedAfter {
        return false
      }
      if isNative { return true }
      return age <= abandonedAfter
    }
    return isNative
  }

  public static func kept(items: [WatchingItem],
                          nativeIDs: Set<Int>,
                          lastSeen: [Int: Date],
                          position: [Int: Double] = [:],
                          now: Date = Date()) -> [WatchingItem] {
    items.filter {
      isKept($0,
             isNative: nativeIDs.contains($0.id),
             lastSeen: lastSeen[$0.id],
             position: position[$0.id],
             now: now)
    }
  }

  /// How far behind a title is, for ties. Films have no episode counters and
  /// count as zero: a half-watched film is one press from finished.
  static func backlog(_ item: WatchingItem) -> Int {
    item.new ?? 0
  }

  /// Newest last-seen first. Undated native titles follow anything with a date.
  /// On a date tie, a native list member beats `subscribed=0`. Then the smaller
  /// backlog, then caller order.
  public static func ordered(items: [WatchingItem],
                             nativeIDs: Set<Int>,
                             lastSeen: [Int: Date]) -> [WatchingItem] {
    items.enumerated().sorted { lhs, rhs in
      switch (lastSeen[lhs.element.id], lastSeen[rhs.element.id]) {
      case let (l?, r?) where l != r: return l > r
      case (.some, nil): return true
      case (nil, .some): return false
      default: break
      }
      let lhsNative = nativeIDs.contains(lhs.element.id)
      let rhsNative = nativeIDs.contains(rhs.element.id)
      if lhsNative != rhsNative { return lhsNative }
      let lhsBacklog = backlog(lhs.element)
      let rhsBacklog = backlog(rhs.element)
      if lhsBacklog != rhsBacklog { return lhsBacklog < rhsBacklog }
      return lhs.offset < rhs.offset
    }.map(\.element)
  }

  /// The row: native movies + followed series, then `subscribed=0` / extras that
  /// still pass the abandoned rules, newest date first, at most ``maxItems``.
  /// `limit` nil returns the whole kept list so a caller can draw past titles
  /// that have nothing to offer.
  public static func row(movies: [WatchingItem],
                         unfinishedSerials: [WatchingItem],
                         watchlist: [WatchingItem],
                         extras: [WatchingItem] = [],
                         lastSeen: [Int: Date],
                         position: [Int: Double] = [:],
                         excluding: Set<Int> = [],
                         limit: Int? = maxItems,
                         now: Date = Date()) -> [WatchingItem] {
    let nativeIDs = Set(movies.map(\.id)).union(watchlist.map(\.id))
    var pool = mergePool(movies: movies, serials: unfinishedSerials, watchlist: watchlist)
    for item in extras where !pool.contains(where: { $0.id == item.id }) {
      pool.append(item)
    }
    pool.removeAll { excluding.contains($0.id) }
    let surviving = kept(items: pool,
                         nativeIDs: nativeIDs,
                         lastSeen: lastSeen,
                         position: position,
                         now: now)
    let sorted = ordered(items: surviving, nativeIDs: nativeIDs, lastSeen: lastSeen)
    if let limit { return Array(sorted.prefix(limit)) }
    return sorted
  }

  /// History has a row per episode; collapse it to the newest play per title.
  ///
  /// An unstarted next episode has no `last_seen` of its own. Rank it by the
  /// newest date among that series' rows in the history page we already fetched
  /// (finished episodes included) — no extra request. Sashimi #651 / #648 / #629.
  public static func lastSeenByItemID(_ history: [HistoryEntry]) -> [Int: Date] {
    history.reduce(into: [Int: Date]()) { result, entry in
      guard let date = entry.lastSeenDate else { return }
      if let existing = result[entry.item.id], existing >= date { return }
      result[entry.item.id] = date
    }
  }

  /// Playback position of the newest history row per title, for the barely-started filter.
  public static func positionByItemID(_ history: [HistoryEntry]) -> [Int: Double] {
    history.reduce(into: [Int: (date: Date, position: Double)]()) { result, entry in
      guard let date = entry.lastSeenDate, let time = entry.time else { return }
      if let existing = result[entry.item.id], existing.date >= date { return }
      result[entry.item.id] = (date, time)
    }.mapValues(\.position)
  }

  /// Unions movies, unfinished serials and the watchlist without losing either source's
  /// extras (`new` badges live on the watchlist payload). Caller order is preserved for
  /// the last tiebreak.
  public static func mergePool(movies: [WatchingItem],
                               serials: [WatchingItem],
                               watchlist: [WatchingItem]) -> [WatchingItem] {
    var order: [Int] = []
    var pool: [Int: WatchingItem] = [:]

    func insert(_ items: [WatchingItem]) {
      for item in items {
        if pool[item.id] == nil {
          order.append(item.id)
          pool[item.id] = item
        } else if let existing = pool[item.id] {
          pool[item.id] = preferred(existing, item)
        }
      }
    }

    insert(serials)
    insert(movies)
    insert(watchlist)
    return order.compactMap { pool[$0] }
  }

  /// Prefer the copy that carries episode counters / a higher `new` badge.
  public static func preferred(_ a: WatchingItem, _ b: WatchingItem) -> WatchingItem {
    let aScore = (a.new ?? 0) * 1000 + (a.total ?? 0)
    let bScore = (b.new ?? 0) * 1000 + (b.total ?? 0)
    return bScore >= aScore ? b : a
  }
}
