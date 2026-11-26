//
//  ContinueWatchingVersionsTests.swift
//  KinoPubAppleClientTests
//
//  A title in several videos on Continue Watching (Sasha, 2026-10-26): the card offers the
//  video the detail page's first play button offers — the next set of a concert, in order —
//  stays until every one is watched, is called «Artist – Show», and names the offered video.
//

import XCTest
import KinoPubBackend
import KinoPubUI
@testable import KinoPub

@MainActor
final class ContinueWatchingVersionsTests: XCTestCase {

  private let posters = Posters(small: "", medium: "", big: "", wide: "https://x/item/wide/1.jpg")

  /// A concert's payload: `videos` as (name, minutes, watched), numbered in order.
  private func concert(_ videos: [(String, Int, Bool)]) throws -> MediaItem {
    let json: [String: Any] = [
      "id": 7, "type": "concert", "subtype": "", "title": "VA / Back to the Beginning",
      "year": 2025, "cast": "", "director": "", "genres": [Any](), "countries": [Any](),
      "duration": ["average": 900, "total": 9000], "langs": 1, "quality": 1080, "plot": "",
      "posters": ["small": "", "medium": "", "big": "", "wide": ""],
      "finished": true, "in_watchlist": false, "subscribed": false,
      "videos": videos.enumerated().map { index, video in
        ["id": 70 + index, "title": video.0, "thumbnail": "", "duration": video.1 * 60,
         "tracks": 1, "number": index + 1, "ac3": 0, "audios": [Any](),
         "watched": video.2 ? 1 : 0,
         "watching": ["status": video.2 ? 1 : -1, "time": video.2 ? video.1 * 60 : 0],
         "subtitles": [Any](), "files": [Any]()] as [String: Any]
      }
    ]
    return try JSONDecoder().decode(MediaItem.self, from: JSONSerialization.data(withJSONObject: json))
  }

  private func card(_ detail: MediaItem) -> MediaCard? {
    HomeCatalog.card(for: WatchingItem(id: 7, type: "concert", title: "VA / Back to the Beginning",
                                       posters: posters, total: nil, watched: nil, new: nil),
                     detail: detail, history: nil, finishedEpisodes: [:], local: nil,
                     isInHistory: true, isInWatchlist: false, cached: nil)
  }

  func testTheNextSetInOrderNotTheLongest() throws {
    let detail = try concert([("Mastodon", 15, true), ("Rival Sons", 16, false),
                              ("Anthrax", 16, false), ("Tom Morello", 41, false)])
    let card = try XCTUnwrap(card(detail))
    XCTAssertEqual(card.video, 2)
    XCTAssertEqual(card.offeredName, "Rival Sons")
    XCTAssertEqual(card.durationSeconds, 16 * 60)
    XCTAssertNil(card.progress, "a set not started yet has no bar")
    XCTAssertEqual(card.title, "VA: Back to the Beginning")
  }

  /// The first set watched is not the concert watched.
  func testStaysUntilEverySetIsWatched() throws {
    XCTAssertNotNil(card(try concert([("Mastodon", 15, true), ("Rival Sons", 16, false)])))
    XCTAssertNil(card(try concert([("Mastodon", 15, true), ("Rival Sons", 16, true)])))
  }

  /// A `subtype: "multi"` film (e.g. "Александр") shows the offered cut/version on line 2,
  /// preferring the version already in progress rather than the first unwatched one.
  func testMultiVersionFilmShowsOfferedVersionName() throws {
    let json: [String: Any] = [
      "id": 99, "type": "movie", "subtype": "multi", "title": "Александр / Alexander",
      "year": 2004, "cast": "", "director": "", "genres": [["id": 9, "title": "Драма"]],
      "countries": [Any](), "duration": ["average": 10500, "total": 21000], "langs": 1,
      "quality": 1080, "plot": "",
      "posters": ["small": "", "medium": "", "big": "", "wide": "https://x/item/wide/99.jpg"],
      "finished": false, "in_watchlist": false, "subscribed": false,
      "videos": [
        ["id": 991, "title": "Театральная версия", "thumbnail": "", "duration": 10500,
         "tracks": 1, "number": 1, "ac3": 0, "audios": [Any](), "watched": 0,
         "watching": ["status": -1, "time": 0], "subtitles": [Any](), "files": [Any]()],
        ["id": 992, "title": "Режиссерская версия", "thumbnail": "", "duration": 12000,
         "tracks": 1, "number": 2, "ac3": 0, "audios": [Any](), "watched": 0,
         "watching": ["status": 0, "time": 1800], "subtitles": [Any](), "files": [Any]()]
      ]
    ]
    let detail = try JSONDecoder().decode(MediaItem.self, from: JSONSerialization.data(withJSONObject: json))
    let watching = WatchingItem(id: 99, type: "movie", subtype: "multi",
                                title: "Александр / Alexander", posters: posters)
    XCTAssertTrue(watching.isMultiVersion)
    let card = try XCTUnwrap(HomeCatalog.card(
      for: watching, detail: detail, history: nil, finishedEpisodes: [:], local: nil,
      isInHistory: false, isInWatchlist: false, cached: nil, reason: .unfinished
    ))
    XCTAssertEqual(card.title, "Александр")
    XCTAssertEqual(card.overlayLabel, "Режиссерская версия")
  }

  /// Single-video concert with `"Artist / Show"`: line 1 is the artist, line 2 is the show.
  func testSingleVideoConcertSplitsShowIntoSubtitle() throws {
    let watching = WatchingItem(id: 101, type: "concert",
                                title: "Morgenshtern / Dead Sea Concert", posters: posters)
    XCTAssertTrue(watching.isConcert)
    let card = try XCTUnwrap(HomeCatalog.card(
      for: watching, detail: nil, history: nil, finishedEpisodes: [:], local: nil,
      isInHistory: false, isInWatchlist: false, cached: nil, reason: .unfinished
    ))
    XCTAssertEqual(card.title, "Morgenshtern")
    XCTAssertEqual(card.overlayLabel, "Dead Sea Concert")
  }

  /// Concert without a slash (e.g. "Chloë") falls back to the reason instead of staying blank.
  func testConcertWithoutSlashUsesReasonSubtitle() throws {
    let watching = WatchingItem(id: 102, type: "concert", title: "Chloë", posters: posters)
    let bookmarked = try XCTUnwrap(HomeCatalog.card(
      for: watching, detail: nil, history: nil, finishedEpisodes: [:], local: nil,
      isInHistory: false, isInWatchlist: false, cached: nil, reason: .bookmarked(Date())
    ))
    XCTAssertEqual(bookmarked.title, "Chloë")
    XCTAssertEqual(bookmarked.overlayLabel, String(localized: "Bookmarked"))

    let unfinished = try XCTUnwrap(HomeCatalog.card(
      for: watching, detail: nil, history: nil, finishedEpisodes: [:], local: nil,
      isInHistory: false, isInWatchlist: false, cached: nil, reason: .unfinished
    ))
    XCTAssertEqual(unfinished.overlayLabel, String(localized: "Left Unfinished"))
  }

  /// Plain films show the reason ("В закладках" / "Недосмотрено"), never year/genre or Ep. 1.
  func testFilmSubtitleIsReasonForBookmarksUnfinishedAndLocalWatch() throws {
    let film = WatchingItem(id: 103, type: "movie", title: "Воскрешённый / Resurrected", posters: posters)
    let bookmarked = try XCTUnwrap(HomeCatalog.card(
      for: film, detail: nil, history: nil, finishedEpisodes: [:], local: nil,
      isInHistory: false, isInWatchlist: false, cached: nil, reason: .bookmarked(Date())
    ))
    XCTAssertEqual(bookmarked.overlayLabel, String(localized: "Bookmarked"))

    let unfinished = try XCTUnwrap(HomeCatalog.card(
      for: film, detail: nil, history: nil, finishedEpisodes: [:], local: nil,
      isInHistory: false, isInWatchlist: false, cached: nil, reason: .unfinished
    ))
    XCTAssertEqual(unfinished.overlayLabel, String(localized: "Left Unfinished"))

    let watched = try XCTUnwrap(HomeCatalog.card(
      for: film, detail: nil, history: nil, finishedEpisodes: [:], local: nil,
      isInHistory: true, isInWatchlist: false, cached: nil, reason: .watched(Date())
    ))
    XCTAssertEqual(watched.overlayLabel, String(localized: "Left Unfinished"))
  }

  /// Series cards keep only the episode line on `overlayLabel` even when detail supplies year/genre.
  func testSeriesSubtitleIgnoresReasonAndKeepsEpisodeLine() {
    XCTAssertEqual(
      HomeCatalog.continueWatchingSubtitle(
        isSeries: true,
        episodeLabel: "1 сезон, 1 серия: Рассвет",
        offeredVersionName: nil,
        concertShow: nil,
        reason: .unfinished
      ),
      "1 сезон, 1 серия: Рассвет"
    )
  }

  /// Local progress overlay on a non-series card preserves concert / version subtitles,
  /// and promotes a bookmarked film that just started playing locally to "Недосмотрено".
  func testLocalOverlayPreservesNonSeriesSubtitle() throws {
    let store = ContentStore(
      disk: RowSnapshotStore(directory: FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)),
      viewer: ViewerStateReaderMock()
    )
    let localStore = LocalWatchProgressStore()
    let concert = try XCTUnwrap(HomeCatalog.card(
      for: WatchingItem(id: 201, type: "concert", title: "Morgenshtern / Dead Sea Concert", posters: posters),
      detail: nil, history: nil, finishedEpisodes: [:], local: nil,
      isInHistory: false, isInWatchlist: false, cached: nil, reason: .unfinished
    ))
    let bookmarkedFilm = try XCTUnwrap(HomeCatalog.card(
      for: WatchingItem(id: 202, type: "movie", title: "Фильм / Film", posters: posters),
      detail: nil, history: nil, finishedEpisodes: [:], local: nil,
      isInHistory: false, isInWatchlist: false, cached: nil, reason: .bookmarked(Date())
    ))
    store.setItems([.card(concert), .card(bookmarkedFilm)], for: .continueWatching)

    localStore.cacheItem(.mock(id: 201, type: "concert"))
    localStore.recordProgress(mediaId: 201, position: 120, duration: 3600, season: nil, episode: 1)
    localStore.cacheItem(.mock(id: 202, type: "movie"))
    localStore.recordProgress(mediaId: 202, position: 120, duration: 3600, season: nil, episode: 1)
    defer {
      localStore.clear(id: 201)
      localStore.clear(id: 202)
    }

    let painted = HomeCatalog.paintedContinueWatchingCards(store: store, localProgressStore: localStore)
    XCTAssertEqual(painted.first { $0.itemID == 201 }?.overlayLabel, "Dead Sea Concert")
    XCTAssertEqual(painted.first { $0.itemID == 202 }?.overlayLabel, String(localized: "Left Unfinished"))
  }
}
