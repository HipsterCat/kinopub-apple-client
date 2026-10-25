//
//  ContinueWatchingOrderTests.swift
//

import XCTest
@testable import KinoPubBackend

final class ContinueWatchingOrderTests: XCTestCase {

  private let now = Date(timeIntervalSince1970: 1_000_000_000)
  private let rules = ContinueWatchingOrder.Rules()

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

  private func ranked(_ candidates: [ContinueWatchingOrder.Candidate],
                      rules: ContinueWatchingOrder.Rules? = nil) -> [Int] {
    ContinueWatchingOrder.ranked(candidates, rules: rules ?? self.rules, now: now).map(\.id)
  }

  // MARK: - What the row is for (Sasha, 2026-10-25)

  /// One episode of a bookmarked series watched last night: its next episode leads,
  /// ahead of everything left half-way earlier in the week.
  func testNextEpisodeOfTheShowJustWatchedLeads() {
    let justWatched = ContinueWatchingOrder.Candidate(item: item(1), lastSeen: daysAgo(0.2),
                                                      stoppedMidway: false)
    let halfWayMonday = ContinueWatchingOrder.Candidate(item: film(2), lastSeen: daysAgo(4),
                                                        stoppedMidway: true, position: 1800)
    let halfWayTuesday = ContinueWatchingOrder.Candidate(item: item(3), lastSeen: daysAgo(3.5),
                                                         stoppedMidway: true, position: 600)

    XCTAssertEqual(ranked([halfWayMonday, halfWayTuesday, justWatched]), [1, 3, 2])
  }

  /// A new episode that came out today beats what was already on the row.
  func testNewEpisodeOfASubscriptionOutranksOlderPlays() {
    let released = ContinueWatchingOrder.Candidate(item: item(1, new: 1), lastSeen: daysAgo(7),
                                                   isSubscribed: true, updatedAt: daysAgo(0.1))
    let watchedYesterday = ContinueWatchingOrder.Candidate(item: item(2), lastSeen: daysAgo(1))

    XCTAssertEqual(ranked([watchedYesterday, released]), [1, 2])
  }

  /// Subscriptions with new episodes sort by when the episode came out, newest first.
  func testSubscriptionsSortByRelease() {
    let older = ContinueWatchingOrder.Candidate(item: item(1, new: 1), isSubscribed: true,
                                                updatedAt: daysAgo(5))
    let newer = ContinueWatchingOrder.Candidate(item: item(2, new: 2), isSubscribed: true,
                                                updatedAt: daysAgo(1))

    XCTAssertEqual(ranked([older, newer]), [2, 1])
  }

  /// A hundred and seventy waiting episodes and nothing watched: abandoned, whatever
  /// the release date says.
  func testAnAbandonedSubscriptionIsNotUpNext() {
    let abandoned = ContinueWatchingOrder.Candidate(item: item(1, new: 170), isSubscribed: true,
                                                    updatedAt: daysAgo(1))
    XCTAssertEqual(ranked([abandoned]), [])

    var watched = abandoned
    watched.lastSeen = daysAgo(10)
    XCTAssertEqual(ranked([watched]), [1], "watched within the window: still followed")
  }

  /// `new` on a title that is not a subscription is not a release reason.
  func testReleaseCountsOnlyForSubscriptions() {
    let notSubscribed = ContinueWatchingOrder.Candidate(item: item(1, new: 1), updatedAt: daysAgo(1))
    XCTAssertEqual(ranked([notSubscribed]), [])
  }

  /// Something left half-way stays near the top while fresh.
  func testAFreshResumeKeepsItsDate() {
    let pausedLastNight = ContinueWatchingOrder.Candidate(item: film(1), lastSeen: daysAgo(0.5),
                                                          stoppedMidway: true, position: 2000)
    let nextUpTwoDays = ContinueWatchingOrder.Candidate(item: item(2), lastSeen: daysAgo(2))

    XCTAssertEqual(ranked([nextUpTwoDays, pausedLastNight]), [1, 2])
  }

  /// Stopped half-way days ago: behind a next episode from weeks ago.
  func testAStalledResumeGoesBehindEverythingElse() {
    let stalled = ContinueWatchingOrder.Candidate(item: film(1), lastSeen: daysAgo(4),
                                                  stoppedMidway: true, position: 2000)
    let nextUp = ContinueWatchingOrder.Candidate(item: item(2), lastSeen: daysAgo(20))

    XCTAssertEqual(ranked([stalled, nextUp]), [2, 1])
  }

  // MARK: - Weeks to consider

  func testNothingOlderThanTheWindowStays() {
    let inside = ContinueWatchingOrder.Candidate(item: item(1), lastSeen: daysAgo(55))
    let outside = ContinueWatchingOrder.Candidate(item: item(2), lastSeen: daysAgo(57))

    XCTAssertEqual(ranked([inside, outside]), [1], "eight weeks is 56 days")
    XCTAssertEqual(ranked([inside, outside], rules: .init(weeks: 52)), [1, 2])
    XCTAssertEqual(ranked([inside, outside], rules: .init(weeks: 4)), [])
  }

  func testUndatedTitlesAreDropped() {
    let listedOnly = ContinueWatchingOrder.Candidate(item: item(1, new: 2), isSubscribed: true)
    XCTAssertEqual(ranked([listedOnly]), [])
  }

  func testABarelyStartedTitleDropsAfterTwoWeeks() {
    let sampled = ContinueWatchingOrder.Candidate(item: film(1), lastSeen: daysAgo(15),
                                                  stoppedMidway: true, position: 30)
    XCTAssertEqual(ranked([sampled]), [])

    var recent = sampled
    recent.lastSeen = daysAgo(2)
    XCTAssertEqual(ranked([recent]), [1])
  }

  // MARK: - Bookmarks

  func testBookmarksMixInByDateAdded() {
    let bookmark = ContinueWatchingOrder.Candidate(item: film(1), bookmarkedAt: daysAgo(1))
    let watched = ContinueWatchingOrder.Candidate(item: item(2), lastSeen: daysAgo(2))
    let older = ContinueWatchingOrder.Candidate(item: film(3), bookmarkedAt: daysAgo(3))

    XCTAssertEqual(ranked([older, watched, bookmark]), [1, 2, 3])
    XCTAssertEqual(ranked([older, watched, bookmark], rules: .init(includesBookmarks: false)), [2])
  }

  func testAPlayedBookmarkIsDatedByThePlay() {
    let played = ContinueWatchingOrder.Candidate(item: film(1), lastSeen: daysAgo(10),
                                                 bookmarkedAt: daysAgo(1))
    XCTAssertEqual(ContinueWatchingOrder.reason(for: played, rules: rules, now: now), .watched(daysAgo(10)))
  }

  func testBookmarksTakeAtMostAThirdOfTheRow() {
    let bookmarks = (1...8).map {
      ContinueWatchingOrder.Candidate(item: film($0), bookmarkedAt: daysAgo(Double($0) / 10))
    }
    let watched = ContinueWatchingOrder.Candidate(item: item(100), lastSeen: daysAgo(5))

    XCTAssertEqual(ranked(bookmarks + [watched]), [1, 2, 3, 4, 100])
  }

  /// The folder's newest item gets the folder's date; the rest keep the folder's order.
  func testBookmarkDatesFollowFolderOrder() {
    let recent = Date(timeIntervalSince1970: 2_000)
    let old = Date(timeIntervalSince1970: 1_000)
    let dates = ContinueWatchingOrder.bookmarkDates(folders: [
      (updated: old, itemIDs: [5, 6]),
      (updated: recent, itemIDs: [7, 5]),
    ])

    XCTAssertEqual(dates[7], recent)
    XCTAssertEqual(dates[5], recent.addingTimeInterval(-1), "the newest folder wins")
    XCTAssertEqual(dates[6], old.addingTimeInterval(-1))
  }

  // MARK: - Length

  func testTheRowIsTwelveLong() {
    let candidates = (1...30).map {
      ContinueWatchingOrder.Candidate(item: item($0), lastSeen: daysAgo(Double($0)))
    }
    XCTAssertEqual(ranked(candidates), Array(1...12))
    XCTAssertEqual(ContinueWatchingOrder.ranked(candidates, rules: rules, limit: 16, now: now).count, 16)
  }

  func testEmptyInputProducesEmptyOutput() {
    XCTAssertEqual(ranked([]), [])
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

  // MARK: - History collapsing

  /// Unstarted next episode has no date of its own. Rank it by the newest play of
  /// that series in the history page we already fetched (Sashimi #648).
  func testNextEpisodeInheritsTheSeriesLatestHistoryDate() {
    let yesterday = Int(now.timeIntervalSince1970) - 86_400
    let history = [
      HistoryEntry(item: .init(id: 1), lastSeen: yesterday),
      HistoryEntry(item: .init(id: 1), lastSeen: yesterday - 2 * 86_400),
      HistoryEntry(item: .init(id: 2), lastSeen: yesterday - 86_400)
    ]
    let lastSeen = ContinueWatchingOrder.lastSeenByItemID(history)
    XCTAssertEqual(lastSeen[1], Date(timeIntervalSince1970: TimeInterval(yesterday)),
                   "max of the series' watched episodes")
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

  // MARK: - Backlog tiebreak

  /// Same date: the title with fewer episodes waiting first.
  func testSameDateSortsByFewestUnwatchedEpisodes() {
    let date = daysAgo(1)
    let behind = ContinueWatchingOrder.Candidate(item: item(1, new: 3), lastSeen: date)
    let close = ContinueWatchingOrder.Candidate(item: item(2, new: 1), lastSeen: date)

    XCTAssertEqual(ranked([behind, close]), [2, 1])
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
