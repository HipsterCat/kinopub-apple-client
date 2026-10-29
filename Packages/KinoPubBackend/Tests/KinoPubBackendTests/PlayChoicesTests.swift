//
//  PlayChoicesTests.swift
//
//  Which videos of a title in several the hero offers, and in what order (`playChoices`):
//  versions of a film, a show with extras, and parts (Sasha, 2026-10-25 / 26). Built from the
//  real concert payload (`item_126187_concert.json`) with its `videos` replaced.
//

import XCTest
@testable import KinoPubBackend

final class PlayChoicesTests: XCTestCase {

  /// `videos` as (minutes, watched), numbered in order.
  private func item(subtype: String = "", _ videos: [(Int, Bool)]) throws -> MediaItem {
    let url = try XCTUnwrap(Bundle.module.url(forResource: "item_126187_concert",
                                              withExtension: "json",
                                              subdirectory: "Fixtures"))
    var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    var payload = try XCTUnwrap(json["item"] as? [String: Any])
    let template = try XCTUnwrap((payload["videos"] as? [[String: Any]])?.first)
    payload["subtype"] = subtype
    payload["videos"] = videos.enumerated().map { index, video in
      var entry = template
      entry["id"] = 1000 + index
      entry["number"] = index + 1
      entry["title"] = "Part \(index + 1)"
      entry["duration"] = video.0 * 60
      entry["watched"] = video.1 ? 1 : 0
      entry["watching"] = ["status": video.1 ? 1 : -1, "time": video.1 ? video.0 * 60 : 0]
      return entry
    }
    json["item"] = payload
    return try JSONDecoder().decode(SingleItemData<MediaItem>.self,
                                    from: JSONSerialization.data(withJSONObject: json)).item
  }

  private func numbers(_ item: MediaItem) -> [Int] { item.playChoices.map(\.number) }

  /// A concert in sets of a size: in order, from the first one not watched — never the
  /// longest first.
  func testPartsPlayInOrderFromTheNextUnwatched() throws {
    let concert = try item([(15, true), (16, true), (16, false), (31, false), (41, false), (16, false)])
    XCTAssertEqual(numbers(concert), [3, 4, 5, 6])
    XCTAssertTrue(concert.isMainVersion(concert.playChoices[0]))
    XCTAssertFalse(concert.isMainVersion(concert.playChoices[2]))
  }

  /// One long set among short ones is a set, not the show.
  func testALongSetAmongShortOnesIsStillAPart() throws {
    let concert = try item([(15, true), (16, false), (16, false), (41, false)])
    XCTAssertNil(concert.dominantVersion)
    XCTAssertEqual(numbers(concert), [2, 3, 4])
  }

  func testPartsAllWatchedStartOver() throws {
    XCTAssertEqual(numbers(try item([(15, true), (16, true), (18, true)])), [1, 2, 3])
  }

  /// One video far longer than the rest: it leads, always, and the extras follow until watched.
  func testAShowWithExtrasLeadsWithTheShow() throws {
    let concert = try item([(4, true), (86, true), (33, false), (4, false)])
    XCTAssertEqual(numbers(concert), [2, 3, 4])
    XCTAssertTrue(concert.isMainVersion(concert.playChoices[0]))
    XCTAssertFalse(concert.isMainVersion(concert.playChoices[1]))
  }

  /// Versions of one film: all of them, in order, watched or not.
  func testVersionsOfAFilmAllStay() throws {
    let film = try item(subtype: "multi", [(140, true), (140, false), (165, false)])
    XCTAssertEqual(numbers(film), [1, 2, 3])
    XCTAssertTrue(film.playChoices.allSatisfy(film.isMainVersion))
  }
}
