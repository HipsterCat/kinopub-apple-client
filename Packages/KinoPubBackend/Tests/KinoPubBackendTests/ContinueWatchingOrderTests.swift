//
//  ContinueWatchingOrderTests.swift
//

import XCTest
@testable import KinoPubBackend

final class ContinueWatchingOrderTests: XCTestCase {

  private let now = Date(timeIntervalSince1970: 1_000_000_000)

  private func item(_ id: Int, new: Int? = nil) -> WatchingItem {
    WatchingItem(id: id,
                 type: "serial",
                 title: "Item \(id)",
                 posters: Posters(small: "", medium: "", big: "", wide: nil),
                 total: 10,
                 watched: 5,
                 new: new)
  }

  private func film(_ id: Int) -> WatchingItem {
    WatchingItem(id: id, type: "movie", title: "Film \(id)",
                 posters: Posters(small: "", medium: "", big: "", wide: nil))
  }

  private func daysAgo(_ days: Double) -> Date {
    now.addingTimeInterval(-days * 24 * 60 * 60)
  }

  private func unix(_ date: Date) -> Int { Int(date.timeIntervalSince1970) }

  private func order(_ items: [WatchingItem],
                     native: Set<Int>,
                     lastSeen: [Int: Date] = [:]) -> [Int] {
    ContinueWatchingOrder.ordered(items: items,
                                  nativeIDs: native,
                                  lastSeen: lastSeen).map(\.id)
  }

  private func kept(_ items: [WatchingItem],
                    native: Set<Int>,
                    lastSeen: [Int: Date] = [:],
                    position: [Int: Double] = [:]) -> [Int] {
    ContinueWatchingOrder.kept(items: items,
                               nativeIDs: native,
                               lastSeen: lastSeen,
                               position: position,
                               now: now).map(\.id)
  }

  // MARK: - Native list drives membership

  /// Unfinished movies and followed series are the row, even with no history date.
  func testNativeMoviesAndFollowedSeriesStayWithoutADate() {
    let movie = film(1)
    let followed = item(2, new: 1)
    let unfollowed = item(3, new: 4)

    XCTAssertEqual(
      kept([movie, followed, unfollowed], native: [1, 2]),
      [1, 2],
      "subscribed=0 with no date is the watching/serials dump"
    )
  }

  func testRowIsTheNativeListsPlusDatedUnfollowedSerials() {
    let movies = [film(10)]
    let watchlist = [item(2, new: 3)]
    let unfinished = [item(2, new: 3), item(3), item(4)]
    let ids = ContinueWatchingOrder.row(
      movies: movies,
      unfinishedSerials: unfinished,
      watchlist: watchlist,
      lastSeen: [3: daysAgo(2), 4: daysAgo(91)],
      now: now
    ).map(\.id)

    XCTAssertEqual(ids.contains(10), true, "watching/movies")
    XCTAssertEqual(ids.contains(2), true, "subscribed=1")
    XCTAssertEqual(ids.contains(3), true, "subscribed=0 touched two days ago")
    XCTAssertEqual(ids.contains(4), false, "subscribed=0 abandoned")
  }

  func testAFinishedLocalFilmIsExcludedFromTheNativeList() {
    XCTAssertEqual(
      ContinueWatchingOrder.row(
        movies: [film(1), film(2)],
        unfinishedSerials: [],
        watchlist: [],
        lastSeen: [:],
        excluding: [1],
        now: now
      ).map(\.id),
      [2]
    )
  }

  func testHistoryAndLocalAreOnlyASupplement() {
    let extra = item(9)
    let ids = ContinueWatchingOrder.row(
      movies: [film(1)],
      unfinishedSerials: [],
      watchlist: [],
      extras: [extra],
      lastSeen: [9: daysAgo(1)],
      now: now
    ).map(\.id)

    XCTAssertEqual(ids.first, 9, "a title the lists missed, dated from history, still appears")
    XCTAssertEqual(
      ContinueWatchingOrder.row(
        movies: [film(1)],
        unfinishedSerials: [],
        watchlist: [],
        extras: [extra],
        lastSeen: [:],
        now: now
      ).map(\.id),
      [1],
      "an undated extra is not a native list member"
    )
  }

  // MARK: - subscribed=0 / abandoned

  func testATitleNotTouchedInNinetyDaysLeavesTheRowUnlessNative() {
    XCTAssertEqual(
      kept([item(1), item(2)], native: [], lastSeen: [1: daysAgo(91), 2: daysAgo(3)]),
      [2]
    )
    XCTAssertEqual(
      kept([item(1)], native: [1], lastSeen: [1: daysAgo(200)]),
      [1],
      "followed series stay even when lastSeen is old"
    )
  }

  func testNinetyDaysExactlyIsStillKept() {
    XCTAssertEqual(
      kept([item(1)], native: [],
           lastSeen: [1: now.addingTimeInterval(-ContinueWatchingOrder.abandonedAfter)]),
      [1]
    )
  }

  func testABarelyStartedTitleDropsAfterTwoWeeks() {
    XCTAssertTrue(
      kept([item(1)], native: [1], lastSeen: [1: daysAgo(15)], position: [1: 40]).isEmpty,
      "40 s fifteen days ago is a sample, not continuing — even on the watchlist"
    )
  }

  func testABarelyStartedTitleStaysWithinTwoWeeks() {
    XCTAssertEqual(
      kept([item(1)], native: [], lastSeen: [1: daysAgo(3)], position: [1: 40]),
      [1]
    )
  }

  /// subscribed=0 with a date, on a tie, sits behind a native list member.
  func testUnfollowedSerialsAreDeprioritisedWhenDatesTie() {
    let date = daysAgo(2)
    XCTAssertEqual(
      order([item(1), item(2)], native: [2], lastSeen: [1: date, 2: date]),
      [2, 1]
    )
  }

  // MARK: - Date max (history vs local)

  func testHistoryNewerThanLocalWins() {
    let history = daysAgo(1)
    let local = daysAgo(40)
    let recency = ContinueWatchingOrder.mergingLocalResume(
      lastSeen: [7: history],
      position: [7: 2_000],
      local: [.init(id: 7, updatedAt: local, position: 30)]
    )
    XCTAssertEqual(recency.lastSeen[7], history)
    XCTAssertEqual(recency.position[7], 2_000, "stale local playhead does not paint the filter")
  }

  func testLocalNewerThanHistoryWins() {
    let history = daysAgo(40)
    let local = daysAgo(1)
    let recency = ContinueWatchingOrder.mergingLocalResume(
      lastSeen: [7: history],
      position: [7: 2_000],
      local: [.init(id: 7, updatedAt: local, position: 400)]
    )
    XCTAssertEqual(recency.lastSeen[7], local)
    XCTAssertEqual(recency.position[7], 400)
  }

  func testAbandonedFilterUsesTheNewerDate() {
    let unfollowed = item(1)
    let localOld = ContinueWatchingOrder.mergingLocalResume(
      lastSeen: [1: daysAgo(2)],
      local: [.init(id: 1, updatedAt: daysAgo(100), position: 400)]
    )
    XCTAssertEqual(
      kept([unfollowed], native: [], lastSeen: localOld.lastSeen, position: localOld.position),
      [1],
      "watched on the phone two days ago; Apple TV resume is 100 days old"
    )

    let historyOld = ContinueWatchingOrder.mergingLocalResume(
      lastSeen: [1: daysAgo(100)],
      local: [.init(id: 1, updatedAt: daysAgo(2), position: 400)]
    )
    XCTAssertEqual(
      kept([unfollowed], native: [], lastSeen: historyOld.lastSeen, position: historyOld.position),
      [1],
      "watched here two days ago; history still has the old phone date"
    )

    let bothOld = ContinueWatchingOrder.mergingLocalResume(
      lastSeen: [1: daysAgo(100)],
      local: [.init(id: 1, updatedAt: daysAgo(95), position: 400)]
    )
    XCTAssertTrue(
      kept([unfollowed], native: [], lastSeen: bothOld.lastSeen, position: bothOld.position).isEmpty
    )
  }

  func testBarelyStartedFilterUsesTheWinningSourcesPosition() {
    let recency = ContinueWatchingOrder.mergingLocalResume(
      lastSeen: [1: daysAgo(20)],
      position: [1: 2_000],
      local: [.init(id: 1, updatedAt: daysAgo(40), position: 20)]
    )
    XCTAssertEqual(
      kept([item(1)], native: [], lastSeen: recency.lastSeen, position: recency.position),
      [1],
      "history is a real watch 20 days ago; stale local 20 s must not look barely-started"
    )
  }

  func testEqualDatesPreferLocal() {
    let date = daysAgo(3)
    let recency = ContinueWatchingOrder.mergingLocalResume(
      lastSeen: [1: date],
      position: [1: 100],
      local: [.init(id: 1, updatedAt: date, position: 500)]
    )
    XCTAssertEqual(recency.position[1], 500)
  }

  // MARK: - Ranking by max date

  func testNewestLastSeenLeads() {
    XCTAssertEqual(
      order([item(1), film(2), item(3)], native: [1, 2, 3],
            lastSeen: [1: daysAgo(10), 2: daysAgo(1), 3: daysAgo(5)]),
      [2, 3, 1]
    )
  }

  func testADatedTitleBeatsAnUndatedNativeOne() {
    XCTAssertEqual(
      order([item(1, new: 3), film(2)], native: [1, 2], lastSeen: [2: daysAgo(1)]),
      [2, 1],
      "a film started yesterday outranks a followed series with no play in the history page"
    )
  }

  func testUndatedNativeTitlesSortByFewestUnwatchedEpisodes() {
    let abandoned = WatchingItem.mock(id: 1, title: "Abandoned", new: 171)
    let followed = WatchingItem.mock(id: 2, title: "Followed", new: 1)
    XCTAssertEqual(
      order([abandoned, followed], native: [1, 2]),
      [2, 1]
    )
  }

  func testAFilmOutranksASerialWithEpisodesToGoWhenBothUndated() {
    XCTAssertEqual(
      order([item(2, new: 8), film(1)], native: [1, 2]),
      [1, 2]
    )
  }

  func testUnknownHistoryKeepsAPIOrderAsTiebreak() {
    XCTAssertEqual(order([item(3), item(1), item(2)], native: [1, 2, 3]), [3, 1, 2])
  }

  func testEmptyInputProducesEmptyOutput() {
    XCTAssertEqual(order([]), native: []), [])
  }

  func testTheRowIsTwentyLong() {
    let movies = (1...30).map { film($0) }
    let ids = ContinueWatchingOrder.row(
      movies: movies,
      unfinishedSerials: [],
      watchlist: [],
      lastSeen: Dictionary(uniqueKeysWithValues: movies.map { ($0.id, daysAgo(Double($0.id))) }),
      now: now
    ).map(\.id)
    XCTAssertEqual(ids, Array(1...20))
  }

  // MARK: - Next-up recency from history

  /// Unstarted next episode has no date of its own. Rank it by the newest play of
  /// that series in the history page we already fetched (Sashimi #651 / #648).
  func testNextEpisodeInheritsTheSeriesLatestHistoryDate() {
    let yesterday = unix(daysAgo(1))
    let history = [
      HistoryEntry(item: .init(id: 1), lastSeen: yesterday),
      HistoryEntry(item: .init(id: 1), lastSeen: yesterday - 2 * 86_400),
      HistoryEntry(item: .init(id: 2), lastSeen: yesterday - 86_400)
    ]
    let lastSeen = ContinueWatchingOrder.lastSeenByItemID(history)
    XCTAssertEqual(lastSeen[1], Date(timeIntervalSince1970: TimeInterval(yesterday)),
                   "max of the series' watched episodes")
    XCTAssertEqual(
      order([item(1, new: 1), item(2)], native: [1, 2], lastSeen: lastSeen),
      [1, 2],
      "the show being watched outranks a two-day-old title"
    )
  }

  func testNextUpInheritsSeriesDateThenMaxesWithLocal() {
    let seriesLastWatch = daysAgo(1)
    let staleLocal = daysAgo(40)
    let history = [
      HistoryEntry(item: .init(id: 1), lastSeen: unix(seriesLastWatch)),
      HistoryEntry(item: .init(id: 1), lastSeen: unix(daysAgo(10)))
    ]
    let recency = ContinueWatchingOrder.recency(
      history: history,
      local: [.init(id: 1, updatedAt: staleLocal, position: 20)]
    )
    XCTAssertEqual(recency.lastSeen[1], seriesLastWatch)
    XCTAssertEqual(
      order([item(1), item(2)], native: [1, 2],
            lastSeen: recency.lastSeen.merging([2: daysAgo(5)]) { current, _ in current }),
      [1, 2]
    )
  }

  func testPositionKeepsTheNewestHistoryRowPerTitle() {
    let history = [
      HistoryEntry(item: .init(id: 7), time: 10, lastSeen: 100),
      HistoryEntry(item: .init(id: 7), time: 400, lastSeen: 300),
      HistoryEntry(item: .init(id: 7), time: 50, lastSeen: 200)
    ]
    XCTAssertEqual(ContinueWatchingOrder.positionByItemID(history)[7], 400)
  }

  func testLastSeenKeepsTheNewestEpisodePerTitle() {
    let history = [
      HistoryEntry(item: .init(id: 7), lastSeen: 100),
      HistoryEntry(item: .init(id: 7), lastSeen: 300),
      HistoryEntry(item: .init(id: 7), lastSeen: 200),
      HistoryEntry(item: .init(id: 9), lastSeen: 50)
    ]
    let collapsed = ContinueWatchingOrder.lastSeenByItemID(history)
    XCTAssertEqual(collapsed[7], Date(timeIntervalSince1970: 300))
    XCTAssertEqual(collapsed[9], Date(timeIntervalSince1970: 50))
  }

  func testLastSeenIgnoresMissingAndZeroTimestamps() {
    let history = [
      HistoryEntry(item: .init(id: 1), lastSeen: nil),
      HistoryEntry(item: .init(id: 2), lastSeen: 0)
    ]
    XCTAssertTrue(ContinueWatchingOrder.lastSeenByItemID(history).isEmpty)
  }

  // MARK: - Pool merge

  func testMergePoolUnionsWatchlistWithoutLosingOrder() {
    let movies = [item(10)]
    let serials = [item(1), item(2)]
    let watchlist = [item(2, new: 3), item(9, new: 1)]

    let merged = ContinueWatchingOrder.mergePool(movies: movies, serials: serials, watchlist: watchlist)

    XCTAssertEqual(merged.map(\.id), [1, 2, 10, 9])
    XCTAssertEqual(merged.first { $0.id == 2 }?.new, 3, "watchlist copy keeps the +N badge")
  }

  func testUnwatchedCountPrefersTotalMinusWatched() {
    let item = WatchingItem(id: 1, type: "serial", title: "S",
                            posters: Posters(small: "", medium: "", big: "", wide: nil),
                            total: 10, watched: 4, new: nil)
    XCTAssertEqual(item.unwatchedCount, 6)
  }

  func testUnwatchedCountFallsBackToNew() {
    let onlyNew = WatchingItem(id: 2, type: "serial", title: "S",
                               posters: Posters(small: "", medium: "", big: "", wide: nil),
                               total: nil, watched: nil, new: 3)
    XCTAssertEqual(onlyNew.unwatchedCount, 3)
    XCTAssertNil(WatchingItem(id: 1, type: "movie", title: "F",
                              posters: Posters(small: "", medium: "", big: "", wide: nil)).unwatchedCount)
  }
}
