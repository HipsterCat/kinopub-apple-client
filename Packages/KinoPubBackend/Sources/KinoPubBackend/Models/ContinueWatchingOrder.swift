//
//  ContinueWatchingOrder.swift
//
//

import Foundation

/// Ordering rules for the home screen's "continue watching" row.
public enum ContinueWatchingOrder {

  /// How recently something must have been played to count as "recently started".
  public static let recentWindow: TimeInterval = 7 * 24 * 60 * 60

  /// Titles last touched longer ago than this leave the row, unless they are still
  /// on the watchlist. `/v1/watching/serials` lists every unfinished serial on the
  /// account; ninety days is long enough to resume a show after a break and short
  /// enough to drop years-old junk. The Library tab still has the whole list.
  public static let abandonedAfter: TimeInterval = 90 * 24 * 60 * 60

  /// A sample that never cleared ``WatchProgress/enterContinueWatchingSeconds``
  /// drops off after this, even from the watchlist — sampling is not continuing.
  public static let barelyStartedAfter: TimeInterval = 14 * 24 * 60 * 60

  /// How long the row is allowed to be.
  ///
  /// `/v1/watching/serials` lists **every** unfinished serial on the account, which for
  /// a long-lived account is hundreds of titles — a shelf that scrolls sideways forever
  /// and is, past the first screen, a list of things abandoned years ago. This is a
  /// "carry on with what you were doing" row, not the whole watching list; the Library
  /// tab is where all of it lives, which is where the row's chevron now goes.
  public static let maxItems: Int = 20

  public enum Bucket: Int {
    /// Played within the last week — recently started or resumed.
    case recentlyStarted = 0
    /// On the watchlist with new episodes waiting, and not played this week.
    case recentlyReleased = 1
    /// The rest of the watchlist.
    case watchlist = 2
    /// Everything else still unfinished.
    case rest = 3
  }

  public static func bucket(for item: WatchingItem,
                            watchlistIDs: Set<Int>,
                            lastSeen: [Int: Date],
                            now: Date) -> Bucket {
    if let seen = lastSeen[item.id],
       now.timeIntervalSince(seen) <= recentWindow,
       now >= seen {
      return .recentlyStarted
    }
    let onWatchlist = watchlistIDs.contains(item.id)
    if onWatchlist, item.hasNewEpisodes {
      return .recentlyReleased
    }
    return onWatchlist ? .watchlist : .rest
  }

  /// How far behind a title is, as the sort uses it. Films have no episode counters and
  /// count as zero, which is deliberate: a half-watched film is one press from finished,
  /// so it belongs above a serial with fifty episodes to go.
  static func backlog(_ item: WatchingItem) -> Int {
    item.new ?? 0
  }

  /// Sorts by bucket, then most recently played first, then by the smallest backlog.
  /// The caller's order is only the final tiebreak.
  ///
  /// **Why backlog and not just dates.** `/v1/watching/movies` and `/v1/watching/serials`
  /// carry no timestamp at all — the only dates in this row come from `/v1/history`, and
  /// only for the page of it we ask for. So most of the row is date-less, and before
  /// this the tie went to whatever order the server happened to list things in: a
  /// cartoon last touched years ago sat above a show with one new episode waiting, both
  /// on the watchlist, both undated. `new` is the one signal the payload does carry that
  /// separates them — one or two unwatched episodes is a title being followed, a hundred
  /// and seventy is a title abandoned.
  public static func ordered(items: [WatchingItem],
                             watchlistIDs: Set<Int>,
                             lastSeen: [Int: Date],
                             now: Date = Date()) -> [WatchingItem] {
    items.enumerated().sorted { lhs, rhs in
      let lhsBucket = bucket(for: lhs.element, watchlistIDs: watchlistIDs, lastSeen: lastSeen, now: now)
      let rhsBucket = bucket(for: rhs.element, watchlistIDs: watchlistIDs, lastSeen: lastSeen, now: now)
      if lhsBucket != rhsBucket { return lhsBucket.rawValue < rhsBucket.rawValue }

      switch (lastSeen[lhs.element.id], lastSeen[rhs.element.id]) {
      case let (l?, r?) where l != r: return l > r
      case (nil, .some): return false
      case (.some, nil): return true
      default: break
      }

      let lhsBacklog = backlog(lhs.element)
      let rhsBacklog = backlog(rhs.element)
      if lhsBacklog != rhsBacklog { return lhsBacklog < rhsBacklog }
      return lhs.offset < rhs.offset
    }.map(\.element)
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

  /// Whether this title still belongs on Continue Watching — not the whole
  /// watching list. Watchlist + new episodes always stay. Everything else needs
  /// a date from history (or local resume) within ``abandonedAfter``, and a
  /// sample shorter than ``WatchProgress/enterContinueWatchingSeconds`` drops
  /// after ``barelyStartedAfter``.
  public static func isKept(_ item: WatchingItem,
                            watchlistIDs: Set<Int>,
                            lastSeen: Date?,
                            position: Double?,
                            now: Date = Date()) -> Bool {
    let onWatchlist = watchlistIDs.contains(item.id)
    if onWatchlist, item.hasNewEpisodes { return true }

    if let lastSeen, now >= lastSeen {
      let age = now.timeIntervalSince(lastSeen)
      if let position, position < WatchProgress.enterContinueWatchingSeconds,
         age > barelyStartedAfter {
        return false
      }
      if !onWatchlist, age > abandonedAfter {
        return false
      }
      return true
    }

    return onWatchlist
  }

  public static func kept(items: [WatchingItem],
                          watchlistIDs: Set<Int>,
                          lastSeen: [Int: Date],
                          position: [Int: Double] = [:],
                          now: Date = Date()) -> [WatchingItem] {
    items.filter {
      isKept($0,
             watchlistIDs: watchlistIDs,
             lastSeen: lastSeen[$0.id],
             position: position[$0.id],
             now: now)
    }
  }

  /// Unions movies, unfinished serials and the watchlist without losing either source's
  /// extras (`new` badges live on the watchlist payload). Caller order is preserved for
  /// the tiebreak inside each bucket.
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
