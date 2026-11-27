//
//  EpisodeRailContextMenuTests.swift
//  PiraticTests
//
//  Episode rail menus: Play + Info only — no bookmark / Follow / Hide (Sasha / KP-23).
//

import XCTest
@testable import Piratic
@testable import KinoPubBackend
import PiraticUI
import PiraticMetadata

@MainActor
final class EpisodeRailContextMenuTests: XCTestCase {

  private func episodeCard() -> MediaCard {
    let episode = Episode(id: 11, title: "Halo", thumbnail: "", duration: 3_120, tracks: 1,
                          number: 2, ac3: 0, audios: [], watched: 0,
                          watching: EpisodeWatching(status: 0, time: 0),
                          subtitles: [], files: [])
    let season = Season(id: 1, title: "Сезон 1", number: 1,
                        watching: SeasonWatching(status: 0), episodes: [episode])
    return MediaCard(episode: episode, in: season, title: "Halo",
                     episodeLabel: "2 серия", dateLabel: nil)
  }

  func testEpisodeRailUsesEnglishNameWhenRussianScheduleOnlyHasANumber() {
    let russian = EpisodeSchedule(episodeNumber: 4, seasonNumber: 1, name: "Эпизод 4")
    let english = EpisodeSchedule(episodeNumber: 4, seasonNumber: 1, name: "The Crossing")
    let enriched = SeasonsRailView.enrichedSchedule(
      nil, from: [russian, english], fallbackSeason: 1, fallbackEpisode: 4)

    XCTAssertEqual(enriched?.name, "The Crossing")
  }

  func testEpisodeGridRefreshesNamesWhenTheScheduleKeepsTheSameSlots() {
    let placeholder = EpisodeSchedule(episodeNumber: 4, seasonNumber: 1, name: "Эпизод 4")
    let named = EpisodeSchedule(episodeNumber: 4, seasonNumber: 1, name: "The Crossing")
    let initial = KinoEpisodeGrid.alignment(seasons: [], official: [placeholder])
    XCTAssertEqual(initial.official.first?.titles, ["Эпизод 4"])

    let refreshed = KinoEpisodeGrid.alignment(seasons: [], official: [named])
    XCTAssertEqual(refreshed.official.first?.titles, ["The Crossing"])
  }

  func testEpisodeRailMenuHasPlayAndInfoWithoutLibraryOrHide() {
    var played = false
    var info = false
    let entries = MediaCardContextMenus.entries(
      for: episodeCard(),
      surface: .episodeRail,
      onPlay: { played = true },
      onGoToTitle: { info = true },
      onToggleWatchlist: { XCTFail("Follow must not appear on episode rail") },
      onToggleBookmarkFolder: { _ in XCTFail("Bookmarks must not appear on episode rail") },
      onCreateBookmarkFolder: { XCTFail("New bookmark folder must not appear on episode rail") },
      onHide: { XCTFail("Hide must not appear on episode rail") }
    )
    let actions = entries.compactMap { entry -> String? in
      if case .action(let action) = entry { return action.id }
      if case .submenu(let id, _, _, _, _) = entry { return id }
      return nil
    }
    XCTAssertTrue(actions.contains("play"))
    XCTAssertTrue(actions.contains("info"))
    XCTAssertFalse(actions.contains("toggle-watchlist"))
    XCTAssertFalse(actions.contains(MediaCardContextMenus.bookmarksMenuID))
    XCTAssertFalse(actions.contains("hide"))
    // Handlers are wired.
    entries.forEach { entry in
      if case .action(let action) = entry {
        if action.id == "play" { action.handler() }
        if action.id == "info" { action.handler() }
      }
    }
    XCTAssertTrue(played)
    XCTAssertTrue(info)
  }
}
