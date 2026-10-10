//
//  LibrarySectionCardsTests.swift
//  KinoPubAppleClientTests
//

import XCTest
import KinoPubBackend
import KinoPubMedia
import KinoPubUI
@testable import KinoPub

final class LibrarySectionCardsTests: XCTestCase {

  private let posters = Posters(small: "s.jpg",
                                medium: "https://x/item/medium/1.jpg",
                                big: "https://x/item/big/1.jpg",
                                wide: "https://x/item/wide/1.jpg")

  func testFollowingSubtitleIsTheUnwatchedCount() {
    let item = WatchingItem(id: 1, type: "serial", title: "Дом Дракона / House of the Dragon",
                            posters: posters, total: 18, watched: 16, new: nil)
    let card = LibrarySectionCatalog.followingCard(for: item)
    XCTAssertEqual(card.unwatchedEpisodes, 2)
    XCTAssertEqual(card.subtitle, EpisodesLeftText(2)?.formatted())
    XCTAssertFalse(card.isLandscape)
    XCTAssertEqual(card.primaryAction, .openDetail)
  }

  func testFollowingCaughtUpHasNoSubtitle() {
    let item = WatchingItem(id: 2, type: "serial", title: "The Bear",
                            posters: posters, total: 28, watched: 28, new: 0)
    let card = LibrarySectionCatalog.followingCard(for: item)
    XCTAssertEqual(card.unwatchedEpisodes, 0)
    XCTAssertNil(card.subtitle)
  }

  func testContinueCardIsLandscapeWideArtAndPlays() {
    let item = WatchingItem(id: 3, type: "movie", title: "Дюна / Dune", posters: posters)
    let history = HistoryEntry(
      item: .init(id: 3, type: "movie", title: "Дюна / Dune", posters: posters),
      media: .init(id: 9, number: 1, snumber: 0, thumbnail: "thumb.jpg", duration: 90 * 60),
      time: 47 * 60,
      lastSeen: 1_700_000_000
    )
    let card = LibrarySectionCatalog.continueCard(for: item, history: history)
    XCTAssertEqual(card.landscapeImageURL, "https://x/item/wide/1.jpg")
    XCTAssertNotEqual(card.landscapeImageURL, "thumb.jpg")
    XCTAssertEqual(card.title, "Дюна")
    XCTAssertEqual(card.primaryAction, .play)
    XCTAssertEqual(card.subtitle, RemainingText(progress: history.progress ?? 0,
                                                durationSeconds: 90 * 60).formatted(.medium))
  }

  func testHistoryCardPlaysUsesWideArtAndWordsTheEpisode() {
    let entry = HistoryEntry(
      item: .init(id: 8, type: "serial", title: "Пантеон / Pantheon", posters: posters),
      media: .init(id: 971, number: 6, snumber: 2, thumbnail: "thumb.jpg", duration: 2500),
      time: 400,
      lastSeen: 1_700_000_000
    )
    let card = HistoryView.card(for: entry, id: 42)
    XCTAssertEqual(card.primaryAction, .play)
    XCTAssertEqual(card.landscapeImageURL, "https://x/item/wide/1.jpg")
    XCTAssertNotEqual(card.landscapeImageURL, "thumb.jpg")
    XCTAssertTrue(card.title.contains("Пантеон"))
    XCTAssertTrue(card.title.contains(EpisodeText(season: 2, number: 6).text(for: .historyRow)))
    XCTAssertEqual(card.subtitle, HistoryEventText(entry.lastSeenDate)?.formatted())
    XCTAssertNil(card.overlayLabel)
  }

  func testHistoryGroupsByDayWithTodayYesterdayAndTheDate() {
    let calendar = Calendar.current
    let now = Date()
    let today = now
    let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
    let older = calendar.date(from: DateComponents(year: 2026, month: 9, day: 15, hour: 10))!
    let cards = [
      historyCard(id: 1, lastSeen: today.timeIntervalSince1970),
      historyCard(id: 2, lastSeen: yesterday.timeIntervalSince1970),
      historyCard(id: 3, lastSeen: older.timeIntervalSince1970)
    ]
    let sections = HistorySectioning.day.sections(for: cards)
    XCTAssertEqual(sections.map(\.id), [
      "\(calendar.startOfDay(for: today).timeIntervalSince1970)",
      "\(calendar.startOfDay(for: yesterday).timeIntervalSince1970)",
      "\(calendar.startOfDay(for: older).timeIntervalSince1970)"
    ])
    XCTAssertEqual(sections[0].title, HistoryDayText(calendar.startOfDay(for: today)).formatted())
    XCTAssertEqual(sections[1].title, HistoryDayText(calendar.startOfDay(for: yesterday)).formatted())
    XCTAssertEqual(sections[2].title, HistoryDayText(calendar.startOfDay(for: older)).formatted())
  }

  private func historyCard(id: Int, lastSeen: TimeInterval) -> MediaCard {
    MediaCard(id: id, posterURL: "", title: "T\(id)",
              watchedAt: Date(timeIntervalSince1970: lastSeen),
              landscapeImageURL: "wide.jpg")
  }
}
