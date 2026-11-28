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
    ContinueWatchingOrder.ranked(candidates, rules: rules ?? self.rules, now: now).map(\.item.id)
  }

  // MARK: - What the row is for (Sasha, 2026-10-25)

  /// One episode of a bookmarked series watched last night: its next episode leads,
  /// ahead of everything left half-way earlier in the week.
  func testNextEpisodeOfTheShowJustWatchedLeads() {
    let justWatched = ContinueWatchingOrder.Candidate(item: item(1), lastSeen: daysAgo(0.2))
    let halfWayMonday = ContinueWatchingOrder.Candidate(item: film(2), lastSeen: daysAgo(4),
                                                        position: 1800)
    let halfWayTuesday = ContinueWatchingOrder.Candidate(item: item(3), lastSeen: daysAgo(3.5),
                                                         position: 600)

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

  func testBookmarkAndFollowedReleaseCompeteByDateRegardlessOfEpisodeCount() {
    var bookmark = ContinueWatchingOrder.Candidate(item: film(1), bookmarkedAt: daysAgo(1))
    let followed = ContinueWatchingOrder.Candidate(item: item(2, new: 170),
                                                   isSubscribed: true, updatedAt: daysAgo(2))
    let oneSlot = ContinueWatchingOrder.Rules(maxItems: 1)

    XCTAssertEqual(ranked([followed, bookmark], rules: oneSlot), [1])
    bookmark.bookmarkedAt = daysAgo(3)
    XCTAssertEqual(ranked([bookmark, followed], rules: oneSlot), [2])
  }

  /// `new` on a title that is not a subscription is not a release reason.
  func testReleaseCountsOnlyForSubscriptions() {
    let notSubscribed = ContinueWatchingOrder.Candidate(item: item(1, new: 1), updatedAt: daysAgo(1))
    XCTAssertEqual(ranked([notSubscribed]), [])
  }

  /// Something left half-way stays near the top while fresh.
  func testAFreshResumeKeepsItsDate() {
    let pausedLastNight = ContinueWatchingOrder.Candidate(item: film(1), lastSeen: daysAgo(0.5),
                                                          position: 2000)
    let nextUpTwoDays = ContinueWatchingOrder.Candidate(item: item(2), lastSeen: daysAgo(2))

    XCTAssertEqual(ranked([nextUpTwoDays, pausedLastNight]), [1, 2])
  }

  func testAnOlderResumeStillUsesItsActivityDate() {
    let stalled = ContinueWatchingOrder.Candidate(item: film(1), lastSeen: daysAgo(4),
                                                  position: 2000)
    let nextUp = ContinueWatchingOrder.Candidate(item: item(2), lastSeen: daysAgo(20))

    XCTAssertEqual(ranked([nextUp, stalled]), [1, 2])
  }

  // MARK: - Weeks to consider

  func testNothingOlderThanTheWindowStays() {
    let inside = ContinueWatchingOrder.Candidate(item: item(1), lastSeen: daysAgo(55))
    let outside = ContinueWatchingOrder.Candidate(item: item(2), lastSeen: daysAgo(57))

    XCTAssertEqual(ranked([inside, outside]), [1], "eight weeks is 56 days")
    XCTAssertEqual(ranked([inside, outside], rules: .init(weeks: 52)), [1, 2])
    XCTAssertEqual(ranked([inside, outside], rules: .init(weeks: 4)), [])
  }

  func testFollowedShowsQualifyWithNoRecentReleaseOrViewingActivity() {
    let undated = ContinueWatchingOrder.Candidate(item: item(1), isSubscribed: true)
    let older = ContinueWatchingOrder.Candidate(item: item(2, new: 12), isSubscribed: true,
                                                updatedAt: daysAgo(60))
    let unrelated = ContinueWatchingOrder.Candidate(item: item(3))
    XCTAssertEqual(ranked([undated, older, unrelated]), [1, 2])
  }

  /// The row reads no history (Sasha, 2026-11-23): a film or series on the server's
  /// unfinished lists stays with no date, behind every dated title, in the list's order.
  func testListedUnfinishedTitlesStayUndatedBehindDatedOnes() {
    let film = ContinueWatchingOrder.Candidate(item: film(1), isListedUnfinished: true)
    let series = ContinueWatchingOrder.Candidate(item: item(2), isListedUnfinished: true)
    let played = ContinueWatchingOrder.Candidate(item: item(3), lastSeen: daysAgo(1))
    XCTAssertEqual(ranked([film, series, played]), [3, 1, 2])
  }

  func testABarelyStartedTitleDropsAfterTwoWeeks() {
    let sampled = ContinueWatchingOrder.Candidate(item: film(1), lastSeen: daysAgo(15),
                                                  position: 30)
    XCTAssertEqual(ranked([sampled]), [])

    var recent = sampled
    recent.lastSeen = daysAgo(2)
    XCTAssertEqual(ranked([recent]), [1])
  }

  /// Home on 2026-11-28: Tulsa King, Dig, Yaga, Blade Runner 2099 all had new episodes
  /// out over the last days, and Yaga and Blade Runner were played on this device today.
  /// The plays lead, newest first, ahead of releases that are older than them.
  func testFreshLocalPlaysOutrankOlderSubscriptionReleases() {
    let tulsa = ContinueWatchingOrder.Candidate(item: item(1, new: 4), isSubscribed: true,
                                                updatedAt: daysAgo(1))
    let dig = ContinueWatchingOrder.Candidate(item: item(2, new: 1), isSubscribed: true,
                                              updatedAt: daysAgo(1.2))
    let yaga = ContinueWatchingOrder.Candidate(item: item(3, new: 2), lastSeen: daysAgo(0.1),
                                               position: 1_360, isSubscribed: true,
                                               updatedAt: daysAgo(1.3))
    let bladeRunner = ContinueWatchingOrder.Candidate(item: item(4, new: 1), lastSeen: daysAgo(0.2),
                                                      position: 2_400, isSubscribed: true,
                                                      updatedAt: daysAgo(2))

    XCTAssertEqual(ranked([tulsa, dig, yaga, bladeRunner]), [3, 4, 1, 2])
  }

  func testQualifyingPlayDateFollowsTheWindowAndTheSampleRule() {
    XCTAssertEqual(ContinueWatchingOrder.qualifyingPlayDate(daysAgo(1), position: 30, rules: rules, now: now),
                   daysAgo(1))
    XCTAssertNil(ContinueWatchingOrder.qualifyingPlayDate(daysAgo(15), position: 30, rules: rules, now: now),
                 "a two-week-old sample does not count")
    XCTAssertEqual(ContinueWatchingOrder.qualifyingPlayDate(daysAgo(15), position: 1_200, rules: rules, now: now),
                   daysAgo(15))
    XCTAssertNil(ContinueWatchingOrder.qualifyingPlayDate(daysAgo(Double(rules.weeks * 7 + 1)), position: 1_200,
                                                          rules: rules, now: now),
                 "outside the window")
    XCTAssertNil(ContinueWatchingOrder.qualifyingPlayDate(nil, position: nil, rules: rules, now: now))
  }

  // MARK: - Bookmarks

  func testBookmarksMixInByDateAdded() {
    let bookmark = ContinueWatchingOrder.Candidate(item: film(1), bookmarkedAt: daysAgo(1))
    let watched = ContinueWatchingOrder.Candidate(item: item(2), lastSeen: daysAgo(2))
    let older = ContinueWatchingOrder.Candidate(item: film(3), bookmarkedAt: daysAgo(3))

    XCTAssertEqual(ranked([older, watched, bookmark]), [1, 2, 3])
    XCTAssertEqual(ranked([older, watched, bookmark], rules: .init(includesBookmarks: false)), [2])
  }

  func testABookmarkDateMovesAPlayedTitleWithoutChangingItsReason() {
    let played = ContinueWatchingOrder.Candidate(item: film(1), lastSeen: daysAgo(10),
                                                 bookmarkedAt: daysAgo(1))
    let newerPlay = ContinueWatchingOrder.Candidate(item: item(2), lastSeen: daysAgo(2))
    let entries = ContinueWatchingOrder.ranked([newerPlay, played], rules: rules, now: now)

    XCTAssertEqual(entries.map(\.item.id), [1, 2])
    XCTAssertEqual(entries.first?.activityDate, daysAgo(1))
    XCTAssertEqual(entries.first?.reason, .watched(daysAgo(10)))
  }

  func testOnlyABookmarkOnlySeriesUsesTheBookmarkReason() {
    let bookmarkOnly = ContinueWatchingOrder.Candidate(
      item: WatchingItem(id: 1, type: "serial", title: "Saved", posters: film(1).posters),
      bookmarkedAt: daysAgo(0.1))
    let release = ContinueWatchingOrder.Candidate(item: item(2, new: 1),
                                                  isSubscribed: true, updatedAt: daysAgo(2),
                                                  bookmarkedAt: daysAgo(0.2))
    let resume = ContinueWatchingOrder.Candidate(item: item(3), lastSeen: daysAgo(1))
    let entries = ContinueWatchingOrder.ranked([resume, release, bookmarkOnly], rules: rules, now: now)

    XCTAssertEqual(entries.map(\.item.id), [1, 2, 3])
    XCTAssertEqual(entries.map(\.reason), [.bookmarked(daysAgo(0.1)), .released(daysAgo(2)), .watched(daysAgo(1))])
  }

  func testBookmarksTakeAtMostAThirdOfTheRow() {
    let bookmarks = (1...8).map {
      ContinueWatchingOrder.Candidate(item: film($0), bookmarkedAt: daysAgo(Double($0) / 10))
    }
    let watched = ContinueWatchingOrder.Candidate(item: item(100), lastSeen: daysAgo(5))

    XCTAssertEqual(ranked(bookmarks + [watched]), [1, 2, 3, 4, 100])
  }

  /// The folder's newest item gets the folder's date; the rest only a date this device
  /// recorded when it added them.
  func testBookmarkDatesTrustOnlyWhatIsKnown() {
    let recent = Date(timeIntervalSince1970: 2_000)
    let old = Date(timeIntervalSince1970: 1_000)
    let addedHere = Date(timeIntervalSince1970: 1_500)
    let dates = ContinueWatchingOrder.bookmarkDates(folders: [
      (updated: old, itemIDs: [5, 6, 8]),
      (updated: recent, itemIDs: [7, 5]),
    ], knownAdds: [8: addedHere, 9: addedHere])

    XCTAssertEqual(dates[7], recent)
    XCTAssertEqual(dates[5], old, "first in the older folder")
    XCTAssertNil(dates[6], "no way to tell when it was added")
    XCTAssertEqual(dates[8], addedHere)
    XCTAssertNil(dates[9], "not in any folder fetched: no longer bookmarked")
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
