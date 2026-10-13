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

  func testSidebarOrderIsSubscriptionsContinueAllBookmarksThenHistory() {
    XCTAssertEqual(LibrarySection.leadingFixed, [.watchlist, .unwatched, .allBookmarks])
    XCTAssertEqual(LibrarySection.trailingFixed.last, .history)
    XCTAssertEqual(LibrarySection.watchlist.systemImage, "bell.fill")
    XCTAssertEqual(LibrarySection.unwatched.systemImage, "play.circle.fill")
    XCTAssertEqual(LibrarySection.allBookmarks.systemImage, "bookmark.fill")
    XCTAssertEqual(LibrarySection.history.systemImage, "clock.fill")
    XCTAssertNil(LibrarySection.folder(1).systemImage)
    XCTAssertNil(LibrarySection.folder(1).fixedTitle)
  }

  @MainActor
  func testFollowingHeaderCountsUnwatchedEpisodes() {
    let cards = [
      MediaCard(id: 1, posterURL: "", title: "A", unwatchedEpisodes: 2),
      MediaCard(id: 2, posterURL: "", title: "B", unwatchedEpisodes: 154)
    ]
    let model = LibraryModel(contentService: VideoContentServiceMock(),
                             actionsService: UserActionsServiceMock(),
                             authState: AuthState(authService: AuthorizationServiceMock(),
                                                  accessTokenService: AccessTokenServiceMock()),
                             errorHandler: ErrorHandler())
    XCTAssertEqual(model.headerCount(for: .watchlist, cards: cards),
                   UnwatchedEpisodesCountText(156).formatted())
  }


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

  func testATypeFilterKeepsOnlySeries() {
    let movie = MediaCard(id: 1, posterURL: "", title: "Film", isSeries: false, year: 2020)
    let show = MediaCard(id: 2, posterURL: "", title: "Show", isSeries: true, year: 2021)
    var filter = LibraryFilter()
    filter.kinds = [.series]
    let kept = LibrarySectionCatalog.apply(filter, to: [movie, show], sorted: false)
    XCTAssertEqual(kept.map(\.id), [2])
  }

  func testEpisodeCardsFollowSeasonThenEpisodeOrderLikeTheDetailRail() {
    var series = MediaItem.mock(id: 50, type: "serial")
    let s2 = Season(id: 2, title: "", number: 2, watching: SeasonWatching(status: 0),
                    episodes: [
                      Episode(id: 201, title: "B", thumbnail: "b.jpg", duration: 2_400,
                              tracks: 1, number: 1, ac3: 0, audios: [], watched: 0,
                              watching: EpisodeWatching(status: 0, time: 0), subtitles: [], files: []),
                    ])
    let s1 = Season(id: 1, title: "", number: 1, watching: SeasonWatching(status: 0),
                    episodes: [
                      Episode(id: 102, title: "A2", thumbnail: "a2.jpg", duration: 2_400,
                              tracks: 1, number: 2, ac3: 0, audios: [], watched: 0,
                              watching: EpisodeWatching(status: 0, time: 0), subtitles: [], files: []),
                      Episode(id: 101, title: "A1", thumbnail: "a1.jpg", duration: 2_400,
                              tracks: 1, number: 1, ac3: 0, audios: [], watched: 0,
                              watching: EpisodeWatching(status: 0, time: 0), subtitles: [], files: []),
                    ])
    series.seasons = [s2, s1]
    let cards = LibrarySectionCatalog.episodeCards(for: series)
    XCTAssertEqual(cards.map(\.id), [101, 102, 201])
    XCTAssertTrue(cards.allSatisfy(\.isSeries))
    XCTAssertTrue(cards.allSatisfy(\.isLandscape))
    XCTAssertTrue(cards.allSatisfy { $0.primaryAction == .play })
    XCTAssertEqual(cards.map(\.itemID), [50, 50, 50])
    XCTAssertEqual(cards.map(\.season), [1, 1, 2])
  }

  func testContinuePageGroupsPutsMoviesUnderContinueAndEpisodesUnderEpisodes() {
    let movie = MediaCard(id: 1, posterURL: "", title: "Film", isSeries: false,
                          landscapeImageURL: "wide.jpg")
    let episode = MediaCard(id: 10, posterURL: "still.jpg", title: "E1", isSeries: true,
                            landscapeImageURL: "still.jpg")
    let groups = LibrarySectionCatalog.continuePageGroups(from: [movie, episode])
    XCTAssertEqual(groups.map(\.id), ["continue.movies", "continue.episodes"])
    XCTAssertEqual(groups.map(\.isEpisodes), [false, true])
    XCTAssertEqual(groups[0].cards.map(\.id), [1])
    XCTAssertEqual(groups[1].cards.map(\.id), [10])
  }

  func testContinuePageGroupsOmitsAnEmptySide() {
    let episode = MediaCard(id: 10, posterURL: "", title: "E1", isSeries: true)
    XCTAssertEqual(LibrarySectionCatalog.continuePageGroups(from: [episode]).map(\.id),
                   ["continue.episodes"])
    let movie = MediaCard(id: 1, posterURL: "", title: "Film", isSeries: false)
    XCTAssertEqual(LibrarySectionCatalog.continuePageGroups(from: [movie]).map(\.id),
                   ["continue.movies"])
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
