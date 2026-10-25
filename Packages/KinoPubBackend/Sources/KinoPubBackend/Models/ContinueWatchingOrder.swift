//
//  ContinueWatchingOrder.swift
//
//

import Foundation

/// Ordering rules for the home screen's "continue watching" row.
///
/// **What the row is for** (Sasha, 2026-10-25): what to watch next, not a list of things
/// left unfinished. The next episode of the show just watched, a new episode of a
/// subscription, a fresh bookmark — newest first, on one timeline. A film or episode left
/// half-way stays only while it is fresh; after ``stalledAfter`` it goes behind
/// everything else.
///
/// **Where the dates come from** (probed live 2026-10-25): `/v1/watching/*` carry no date
/// at all, and are sorted by the title's `updated_at` (when it got new content), not by
/// when it was watched. `/v1/watching/serials?subscribed=0` is also capped at 50 titles,
/// and drops a series once every episode is watched. So "watched when" is `/v1/history`
/// and this device; "new episode when" is the title payload's `updated_at`; "bookmarked
/// when" is estimated (``bookmarkDates(folders:)``) — kino.pub keeps no per-item date.
public enum ContinueWatchingOrder {

  /// How long the row is allowed to be. Ten to twelve on a TV (Sasha, 2026-10-25): the
  /// Library tab holds the whole watching list, which is where the row's chevron goes.
  public static let maxItems: Int = 12

  /// Bookmarks are mixed in, not the row: at most a third of it.
  public static let maxBookmarks: Int = 4

  /// A title stopped half-way and not touched for this long is no longer "what I'm
  /// watching" — it sorts behind next episodes, new episodes and bookmarks.
  public static let stalledAfter: TimeInterval = 3 * 24 * 60 * 60

  /// A sample that never cleared ``WatchProgress/enterContinueWatchingSeconds``
  /// drops off after this — sampling is not continuing.
  public static let barelyStartedAfter: TimeInterval = 14 * 24 * 60 * 60

  /// A subscription this many new episodes behind (or fewer) is being followed even when
  /// the history page we read has no play of it. More than that, and nothing watched in
  /// the window, is a subscription abandoned — a hundred and seventy waiting episodes
  /// are not "up next".
  public static let followedBacklog: Int = 3

  /// The viewer's choices (Settings › Home › Continue Watching), like Plex's
  /// "Weeks to consider for Continue Watching" and "Include bookmarks".
  public struct Rules: Equatable, Sendable {
    public var weeks: Int
    public var includesBookmarks: Bool
    public var maxItems: Int

    public static let weekOptions = [1, 2, 4, 8, 12, 26, 52]
    public static let defaultWeeks = 8

    public init(weeks: Int = Rules.defaultWeeks,
                includesBookmarks: Bool = true,
                maxItems: Int = ContinueWatchingOrder.maxItems) {
      self.weeks = max(1, weeks)
      self.includesBookmarks = includesBookmarks
      self.maxItems = maxItems
    }

    /// Anything not watched, released or bookmarked within this leaves the row.
    public var window: TimeInterval { TimeInterval(weeks) * 7 * 24 * 60 * 60 }
  }

  /// One title that could go on the row, with every date we know for it.
  public struct Candidate: Equatable, Sendable {
    public var item: WatchingItem
    /// Newest play of the title: history or this device.
    public var lastSeen: Date?
    /// The newest play stopped mid-video. False when it ran to the credits — then the
    /// card offers the next episode.
    public var stoppedMidway: Bool
    /// Play head of the newest play, for the barely-started rule.
    public var position: Double?
    /// On the viewer's subscriptions (`watching/serials?subscribed=1`).
    public var isSubscribed: Bool
    /// When the title last got new content (`updated_at`), when known.
    public var updatedAt: Date?
    /// When it was bookmarked, estimated. Nil when not bookmarked.
    public var bookmarkedAt: Date?

    public init(item: WatchingItem,
                lastSeen: Date? = nil,
                stoppedMidway: Bool = false,
                position: Double? = nil,
                isSubscribed: Bool = false,
                updatedAt: Date? = nil,
                bookmarkedAt: Date? = nil) {
      self.item = item
      self.lastSeen = lastSeen
      self.stoppedMidway = stoppedMidway
      self.position = position
      self.isSubscribed = isSubscribed
      self.updatedAt = updatedAt
      self.bookmarkedAt = bookmarkedAt
    }
  }

  /// Why a title is on the row, and the date it sorts by.
  public enum Reason: Equatable, Sendable {
    /// Played within the window: next episode, or resume while fresh.
    case watched(Date)
    /// A subscription got a new episode within the window.
    case released(Date)
    /// Bookmarked within the window and never played.
    case bookmarked(Date)

    public var date: Date {
      switch self {
      case .watched(let date), .released(let date), .bookmarked(let date): return date
      }
    }
  }

  /// The newest reason the title belongs on the row, or nil when it does not.
  public static func reason(for candidate: Candidate, rules: Rules, now: Date = Date()) -> Reason? {
    func fresh(_ date: Date?) -> Date? {
      guard let date, date <= now, now.timeIntervalSince(date) <= rules.window else { return nil }
      return date
    }

    var watched = fresh(candidate.lastSeen)
    if watched != nil, let position = candidate.position,
       position < WatchProgress.enterContinueWatchingSeconds,
       let lastSeen = candidate.lastSeen,
       now.timeIntervalSince(lastSeen) > barelyStartedAfter {
      watched = nil
    }

    var released: Date?
    if candidate.isSubscribed, candidate.item.hasNewEpisodes,
       let date = fresh(candidate.updatedAt),
       watched != nil || backlog(candidate.item) <= followedBacklog {
      released = date
    }

    var bookmarked: Date?
    if rules.includesBookmarks, candidate.lastSeen == nil {
      bookmarked = fresh(candidate.bookmarkedAt)
    }

    let reasons: [Reason] = [watched.map(Reason.watched),
                             released.map(Reason.released),
                             bookmarked.map(Reason.bookmarked)].compactMap { $0 }
    return reasons.max { $0.date < $1.date }
  }

  /// Stopped half-way and left alone: still on the row, behind everything else.
  static func isStalled(_ candidate: Candidate, reason: Reason, now: Date) -> Bool {
    guard case .watched(let date) = reason, candidate.stoppedMidway else { return false }
    return now.timeIntervalSince(date) > stalledAfter
  }

  /// How far behind a title is, for ties. Films have no episode counters and count as
  /// zero: a half-watched film is one press from finished.
  static func backlog(_ item: WatchingItem) -> Int {
    item.new ?? 0
  }

  /// The row: titles with a reason, newest reason first, stalled ones last, at most
  /// ``Rules/maxItems`` (and ``maxBookmarks`` of those bookmarks). `limit` overrides the
  /// length, so a caller can take a few spare in case a card cannot be drawn.
  public static func ranked(_ candidates: [Candidate],
                            rules: Rules,
                            limit: Int? = nil,
                            now: Date = Date()) -> [WatchingItem] {
    let scored = candidates.enumerated().compactMap { offset, candidate
      -> (offset: Int, candidate: Candidate, reason: Reason, stalled: Bool)? in
      guard let reason = reason(for: candidate, rules: rules, now: now) else { return nil }
      return (offset, candidate, reason, isStalled(candidate, reason: reason, now: now))
    }
    let sorted = scored.sorted { lhs, rhs in
      if lhs.stalled != rhs.stalled { return !lhs.stalled }
      if lhs.reason.date != rhs.reason.date { return lhs.reason.date > rhs.reason.date }
      let lhsBacklog = backlog(lhs.candidate.item)
      let rhsBacklog = backlog(rhs.candidate.item)
      if lhsBacklog != rhsBacklog { return lhsBacklog < rhsBacklog }
      return lhs.offset < rhs.offset
    }
    var bookmarks = 0
    var result: [WatchingItem] = []
    let length = limit ?? rules.maxItems
    for entry in sorted {
      if case .bookmarked = entry.reason {
        guard bookmarks < maxBookmarks else { continue }
        bookmarks += 1
      }
      result.append(entry.candidate.item)
      if result.count >= length { break }
    }
    return result
  }

  /// A bookmark's date, which kino.pub does not keep per item. A folder's `updated` is
  /// when something was last added to it, and its items come newest first (live
  /// 2026-10-25: «maybe» lists its 78 items roughly newest first; the API takes no
  /// sort). So the folder's first item gets the folder's date and every next one a
  /// second less — the folder's order survives the merge with other dates, and nothing
  /// in a folder untouched for months looks new. A title in several folders keeps the
  /// newest.
  public static func bookmarkDates(folders: [(updated: Date, itemIDs: [Int])]) -> [Int: Date] {
    var result: [Int: Date] = [:]
    for folder in folders {
      for (index, id) in folder.itemIDs.enumerated() {
        let date = folder.updated.addingTimeInterval(-TimeInterval(index))
        if let existing = result[id], existing >= date { continue }
        result[id] = date
      }
    }
    return result
  }

  /// History has a row per episode; collapse it to the newest play per title.
  ///
  /// An unstarted next episode has no `last_seen` of its own. Rank it by the
  /// newest date among that series' rows in the history page we already fetched
  /// (finished episodes included) — no extra request. Sashimi #648 / #629.
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
