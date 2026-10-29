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
    XCTAssertEqual(card.title, "VA – Back to the Beginning")
  }

  /// The first set watched is not the concert watched.
  func testStaysUntilEverySetIsWatched() throws {
    XCTAssertNotNil(card(try concert([("Mastodon", 15, true), ("Rival Sons", 16, false)])))
    XCTAssertNil(card(try concert([("Mastodon", 15, true), ("Rival Sons", 16, true)])))
  }
}
