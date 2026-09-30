//
//  EpisodeTitleTests.swift
//
//  «Season 1, Episode 1: Эпизод 1» — seen on device 2026-09-29. The name slot held the
//  number spelled out.
//

import XCTest
@testable import KinoPubMedia

final class EpisodeTitleTests: XCTestCase {

  func testANumberSpelledOutIsNotAName() {
    for title in ["Эпизод 1", "эпизод 12", "Серия 3", "Серия №3", "1 серия", "Episode 12",
                  "Ep. 4", "S01E01", "s1 e2", "#5", "7", "Выпуск 10", "Часть 2", "Part 2"] {
      XCTAssertTrue(EpisodeTitle.isPlaceholder(title), title)
      XCTAssertNil(EpisodeTitle.meaningful(title), title)
    }
  }

  func testARealNameIsKept() {
    for title in ["Pilot", "Goodbye Earl", "Эпизод с Ревеккой", "Серия ошибок",
                  "Part of the Plan", "Зима близко"] {
      XCTAssertFalse(EpisodeTitle.isPlaceholder(title), title)
      XCTAssertEqual(EpisodeTitle.meaningful(title), title)
    }
    XCTAssertNil(EpisodeTitle.meaningful("   "))
    XCTAssertNil(EpisodeTitle.meaningful(nil))
  }

  /// kino.pub's placeholder loses to TMDB's real name.
  func testAPlaceholderLosesToARealName() throws {
    let kinopub = MediaFragment(.kinopub, .episode) { $0.title = "Эпизод 1"; $0.episodeNumber = 1 }
    let tmdb = MediaFragment(.tmdb, .episode) { $0.title = "Winter Is Coming"; $0.episodeNumber = 1 }
    XCTAssertEqual(try XCTUnwrap(MediaAggregator.merge([kinopub, tmdb])).title, "Winter Is Coming")
  }

  /// With no name anywhere, the episode line is just its number.
  func testNoNameMeansJustTheNumber() throws {
    let kinopub = MediaFragment(.kinopub, .episode) { entity in
      entity.title = "Эпизод 1"
      entity.seasonNumber = 1
      entity.episodeNumber = 1
    }
    let episode = try XCTUnwrap(MediaAggregator.merge([kinopub]))
    XCTAssertNil(episode.title)
    let show = MediaEntity(kind: .show, title: "Трудно быть богом")
    XCTAssertEqual(PlayerInfo(context: MediaContext(item: episode, parent: show)).subtitle,
                   "Season 1, Episode 1")
  }

  /// Only episodes: a film may well be called "1917".
  func testOnlyEpisodesAreJudged() throws {
    let film = MediaFragment(.kinopub, .movie) { $0.title = "1917" }
    XCTAssertEqual(try XCTUnwrap(MediaAggregator.merge([film])).title, "1917")
  }
}
