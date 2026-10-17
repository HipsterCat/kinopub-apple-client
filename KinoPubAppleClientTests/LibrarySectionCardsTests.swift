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
    XCTAssertEqual(model.headerTitle(for: .watchlist, cards: cards),
                   UnwatchedEpisodesCountText(156).formatted(),
                   "the count is the title — Подписки stays in the sidebar")
    XCTAssertNotEqual(model.headerTitle(for: .watchlist, cards: cards),
                      model.title(for: .watchlist))
  }

  @MainActor
  func testASectionHeaderIsOneLabel() {
    let cards = [
      MediaCard(id: 1, posterURL: "", title: "A"),
      MediaCard(id: 2, posterURL: "", title: "B")
    ]
    let model = LibraryModel(contentService: VideoContentServiceMock(),
                             actionsService: UserActionsServiceMock(),
                             authState: AuthState(authService: AuthorizationServiceMock(),
                                                  accessTokenService: AccessTokenServiceMock()),
                             errorHandler: ErrorHandler())
    XCTAssertEqual(model.headerTitle(for: .unwatched, cards: cards),
                   UnfinishedCountText(2).formatted(),
                   "Continue is «2 недосмотрено», never the bare number")
    XCTAssertEqual(model.headerTitle(for: .history, cards: []),
                   model.title(for: .history),
                   "with no count the section name is the one label")
    XCTAssertEqual(model.headerTitle(for: .folder(1), cards: cards),
                   TotalCountText(2).formatted(),
                   "a folder header is «Всего N», never the bare number")
    XCTAssertEqual(model.headerTitle(for: .allBookmarks, cards: cards),
                   TotalCountText(2).formatted())
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

  func testFollowingUnwatchedHidesCaughtUpSeries() {
    let waiting = MediaCard(id: 1, posterURL: "", title: "A", unwatchedEpisodes: 3)
    let caughtUp = MediaCard(id: 2, posterURL: "", title: "B", unwatchedEpisodes: 0)
    let unknown = MediaCard(id: 3, posterURL: "", title: "C")
    let cards = [waiting, caughtUp, unknown]
    let unwatched = LibrarySectionCatalog.followingPageGroups(from: cards, scope: .unwatched)
    XCTAssertEqual(unwatched.map(\.id), ["following.unwatched"])
    XCTAssertEqual(unwatched[0].cards.map(\.id), [1, 3],
                   "caught-up series leave Unwatched; an unknown count stays")
    let all = LibrarySectionCatalog.followingPageGroups(from: cards, scope: .all)
    XCTAssertEqual(all.map(\.id), ["following.unwatched", "following.watched"])
    XCTAssertEqual(all.map(\.isWatched), [false, true])
    XCTAssertEqual(all[0].cards.map(\.id), [1, 3])
    XCTAssertEqual(all[1].cards.map(\.id), [2])
  }

  func testFollowingAllOmitsAnEmptySide() {
    let caughtUp = MediaCard(id: 2, posterURL: "", title: "B", unwatchedEpisodes: 0)
    XCTAssertEqual(LibrarySectionCatalog.followingPageGroups(from: [caughtUp], scope: .all).map(\.id),
                   ["following.watched"])
    let waiting = MediaCard(id: 1, posterURL: "", title: "A", unwatchedEpisodes: 1)
    XCTAssertEqual(LibrarySectionCatalog.followingPageGroups(from: [waiting], scope: .all).map(\.id),
                   ["following.unwatched"])
  }

#if os(tvOS)
  @MainActor
  func testFollowingHeaderUsesUnwatchedAllInsteadOfType() {
    let catalog = LibrarySectionCatalog(contentService: VideoContentServiceMock(),
                                        authState: AuthState(authService: AuthorizationServiceMock(),
                                                             accessTokenService: AccessTokenServiceMock()),
                                        errorHandler: ErrorHandler())
    let chips = TVSearchFilters.libraryHeaderChips(catalog: catalog, section: .watchlist)
    XCTAssertEqual(chips.map(\.id), [
      TVSearchFilters.sort, TVSearchFilters.followingUnwatched, TVSearchFilters.followingAll
    ])
    XCTAssertTrue(chips[1].isActive, "Unwatched is the default")
    XCTAssertFalse(chips[2].isActive)
    XCTAssertNil(chips[1].menu, "the switch is two Search chips, not a Тип pull-down")
  }

  @MainActor
  func testAFolderHeaderPutsEllipsisBeforeSort() {
    let catalog = LibrarySectionCatalog(contentService: VideoContentServiceMock(),
                                        authState: AuthState(authService: AuthorizationServiceMock(),
                                                             accessTokenService: AccessTokenServiceMock()),
                                        errorHandler: ErrorHandler())
    let chips = TVSearchFilters.libraryHeaderChips(catalog: catalog, section: .folder(1))
    XCTAssertEqual(chips.first?.id, TVSearchFilters.folderActions)
    XCTAssertEqual(chips.first?.systemImage, "ellipsis")
    XCTAssertEqual(chips.first?.showsTitle, false)
    XCTAssertEqual(chips.dropFirst().first?.id, TVSearchFilters.sort)
    let menuIDs = chips.first?.menu?.nodes.compactMap { node -> String? in
      if case let .option(option, _) = node { return option.id }
      return nil
    }
    XCTAssertEqual(menuIDs, [TVSearchFilters.folderRename, TVSearchFilters.folderDelete])
    switch chips.first?.menu?.nodes.last {
    case .option(let option, _)?:
      XCTAssertTrue(option.isDestructive)
    default:
      XCTFail("Delete Folder is the last menu option")
    }
  }
#endif

  func testATypeFilterKeepsOnlySeries() {
    let movie = MediaCard(id: 1, posterURL: "", title: "Film", isSeries: false, year: 2020)
    let show = MediaCard(id: 2, posterURL: "", title: "Show", isSeries: true, year: 2021)
    var filter = LibraryFilter()
    filter.kinds = [.series]
    let kept = LibrarySectionCatalog.apply(filter, to: [movie, show], sorted: false)
    XCTAssertEqual(kept.map(\.id), [2])
  }

  func testContinueCardForASeriesIsTheWideTitleAndPlays() {
    let item = WatchingItem(id: 4, type: "serial", title: "Пантеон / Pantheon",
                            posters: posters, total: 16, watched: 3)
    let card = LibrarySectionCatalog.continueCard(for: item, history: nil)
    XCTAssertEqual(card.id, 4)
    XCTAssertTrue(card.isSeries)
    XCTAssertEqual(card.primaryAction, .play)
    XCTAssertEqual(card.landscapeImageURL, "https://x/item/wide/1.jpg")
  }

  /// Continue is the unfinished series kino.pub lists, less the followed ones —
  /// Subscriptions shows those.
  @MainActor
  func testContinueLeavesOutSubscriptions() async throws {
    let service = VideoContentServiceMock(watchingSerials: { subscribedOnly in
      let posters = Posters(small: "", medium: "", big: "", wide: "https://x/item/wide/1.jpg")
      let followed = WatchingItem(id: 1, type: "serial", title: "A", posters: posters, total: 5, watched: 1)
      let other = WatchingItem(id: 2, type: "serial", title: "B", posters: posters, total: 5, watched: 0)
      return subscribedOnly ? [followed] : [followed, other]
    })
    let store = ContentStore(disk: RowSnapshotStore(directory: FileManager.default.temporaryDirectory
                               .appendingPathComponent(UUID().uuidString, isDirectory: true)),
                             viewer: ViewerStateReaderMock())
    let catalog = LibrarySectionCatalog(contentService: service, authState: Self.authorized(),
                                        errorHandler: ErrorHandler(), store: store)
    await catalog.activate(.unwatched)
    XCTAssertEqual(catalog.cards.map(\.id), [2])
    XCTAssertEqual(catalog.cards.first?.primaryAction, .play)
    XCTAssertEqual(catalog.cards.first?.isLandscape, true)
  }

  @MainActor
  private static func authorized() -> AuthState {
    let state = AuthState(authService: AuthorizationServiceMock(), accessTokenService: AccessTokenServiceMock())
    state.userState = .authorized
    return state
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
