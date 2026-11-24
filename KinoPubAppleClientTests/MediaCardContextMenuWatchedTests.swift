//
//  MediaCardContextMenuWatchedTests.swift
//  KinoPubAppleClientTests
//
//  Watched submenu shape for series CW cards; sneak-peek aspect + metadata.
//

import XCTest
@testable import KinoPub
@testable import KinoPubBackend
import KinoPubMedia
import KinoPubUI

@MainActor
final class MediaCardContextMenuWatchedTests: XCTestCase {

  private func seriesCard(watched: Bool = false) -> MediaCard {
    MediaCard(
      id: 42,
      posterURL: "https://example.com/poster.jpg",
      title: "Альтруисты",
      landscapeImageURL: "https://example.com/wide.jpg",
      overlayLabel: "S1, E3",
      itemID: 42,
      video: 3,
      season: 1,
      seasonCount: 2,
      isWatched: watched,
      isSeries: true,
      year: 2024,
      durationSeconds: 50 * 60,
      genres: [Genre(id: "drama", domain: .video,
                     name: LocalizedName(en: "Drama", ru: "Драма"))]
    )
  }

  private func posterCard() -> MediaCard {
    MediaCard(
      id: 7,
      posterURL: "https://example.com/poster.jpg",
      title: "Декстер: Воскрешение",
      isSeries: true,
      year: 2025,
      genres: [Genre(id: "drama", domain: .video,
                     name: LocalizedName(en: "Drama", ru: "Драма"))]
    )
  }

  func testSeriesContinueWatchingUsesWatchedSubmenu() {
    var markedEpisode = false
    let entries = MediaCardContextMenus.entries(
      for: seriesCard(),
      surface: .shelf,
      onToggleWatched: { XCTFail("flat toggle must not appear when submenu is set") },
      watchedSubmenu: .init(
        season: 1,
        episode: 3,
        seasonCount: 2,
        onMarkEpisode: { markedEpisode = true },
        onMarkSeason: {},
        onMarkUnwatchedInSeason: {},
        onMarkAllEpisodes: {}
      )
    )
    let ids = entries.compactMap { entry -> String? in
      if case .submenu(let id, _, _, _, _) = entry { return id }
      if case .action(let action) = entry { return action.id }
      return nil
    }
    XCTAssertTrue(ids.contains(MediaCardContextMenus.watchedMenuID))
    XCTAssertFalse(ids.contains("toggle-watched"))
    guard case .submenu(_, _, _, let children, _) = entries.first(where: {
      if case .submenu(let id, _, _, _, _) = $0 { return id == MediaCardContextMenus.watchedMenuID }
      return false
    }) else {
      return XCTFail("expected watched submenu")
    }
    XCTAssertEqual(children.map(\.id), [
      "mark-episode-watched",
      "mark-season-watched",
      "mark-unwatched-in-season",
      "mark-all-episodes-watched"
    ])
    children.first?.handler()
    XCTAssertTrue(markedEpisode)
  }

  func testAlreadyWatchedStaysFlatMarkAsNew() {
    let entries = MediaCardContextMenus.entries(
      for: seriesCard(watched: true),
      surface: .shelf,
      onToggleWatched: {},
      watchedSubmenu: .init(
        season: 1, episode: 3, seasonCount: 2,
        onMarkEpisode: { XCTFail("submenu must not appear when watched") },
        onMarkSeason: {},
        onMarkUnwatchedInSeason: {},
        onMarkAllEpisodes: {}
      )
    )
    let ids = entries.compactMap { entry -> String? in
      if case .submenu(let id, _, _, _, _) = entry { return id }
      if case .action(let action) = entry { return action.id }
      return nil
    }
    XCTAssertTrue(ids.contains("toggle-watched"))
    XCTAssertFalse(ids.contains(MediaCardContextMenus.watchedMenuID))
  }

  func testPreviewSpecUsesLandscapeForWideCard() {
    let spec = MediaCardContextPreviewSpec.from(card: seriesCard(), surface: .shelf)
    XCTAssertEqual(spec.aspect, .landscape)
    XCTAssertEqual(spec.url?.absoluteString, "https://example.com/wide.jpg")
    XCTAssertEqual(spec.title, "Альтруисты")
    XCTAssertTrue(
      spec.subtitle == "S1, E3 · 50м" || spec.subtitle == "S1, E3 · 50m",
      "unexpected subtitle \(spec.subtitle ?? "nil")"
    )
  }

  func testPreviewSpecUsesPosterAspectAndYearGenre() {
    let spec = MediaCardContextPreviewSpec.from(card: posterCard(), surface: .shelf)
    XCTAssertEqual(spec.aspect, .poster)
    XCTAssertEqual(spec.url?.absoluteString, "https://example.com/poster.jpg")
    XCTAssertEqual(spec.title, "Декстер: Воскрешение")
    // Language follows the process locale; accept either localisation of Drama.
    XCTAssertTrue(
      spec.subtitle == "2025 · Драма" || spec.subtitle == "2025 · Drama",
      "unexpected subtitle \(spec.subtitle ?? "nil")"
    )
    XCTAssertGreaterThan(spec.preferredSize.height, spec.artSize.height)
  }
}
