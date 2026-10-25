//
//  ConcertItemTests.swift
//
//  `type: "concert"` — item 126187 ("Schiller / Nature One"), captured from the PWA
//  2026-08-16. `Fixtures/item_126187_concert.json` is that response with the signed CDN
//  URLs replaced, the plot shortened and one of three files dropped. Everything asserted
//  on is verbatim.
//
//  A concert is not a shape we had ever decoded, and it is the first payload seen with
//  `imdb: null` *and* `imdb_rating: 8.1` — a rating with no id behind it.
//

import XCTest
@testable import KinoPubBackend
import KinoPubMedia

final class ConcertItemTests: XCTestCase {

  private func item() throws -> MediaItem {
    let url = try XCTUnwrap(Bundle.module.url(forResource: "item_126187_concert",
                                              withExtension: "json",
                                              subdirectory: "Fixtures"))
    return try JSONDecoder().decode(SingleItemData<MediaItem>.self,
                                    from: Data(contentsOf: url)).item
  }

  func testConcertDecodes() throws {
    let item = try item()
    XCTAssertEqual(item.id, 126187)
    XCTAssertEqual(item.type, "concert")
    XCTAssertEqual(item.videos?.count, 1)
    XCTAssertFalse(item.isSeries)
  }

  /// The one that would have crashed a stricter model: a rating exists without an id.
  /// Both `imdb` and `kinopoisk` are null here while both ratings are populated, so an
  /// external-id lookup must never be gated on "we have a rating".
  func testRatingsSurviveNullExternalIds() throws {
    let item = try item()
    XCTAssertNil(item.imdb)
    XCTAssertNil(item.kinopoisk)
    XCTAssertEqual(item.imdbRating, 8.1)
    XCTAssertEqual(item.kinopoiskRating, 7.295)
  }

  /// `subtype` is an empty string here, not absent and not `"null"` — the multi check
  /// must not trip on it, and neither must the tag strip.
  func testEmptySubtypeIsNotAVersionMarker() throws {
    let item = try item()
    XCTAssertEqual(item.subtype, "")
    XCTAssertFalse(item.isMultiVersion)
    XCTAssertTrue(item.playbackVariants.isEmpty, "One video is not a choice")
    XCTAssertNil(item.contentSubtypeTitleKey)
    XCTAssertNil(item.contentSubtypeRaw)
  }

  /// No trailer on this one — the hero's Trailer button has to cope with `nil`.
  func testTrailerIsAbsent() throws {
    XCTAssertNil(try item().trailer)
    XCTAssertNil(try item().trailerURL)
  }

  /// Single video, so `total == average` and the runtime reads correctly either way.
  func testRuntime() throws {
    let item = try item()
    XCTAssertEqual(item.duration.total, 5257)
    XCTAssertEqual(item.duration.average, 5257)
    XCTAssertTrue(TitleMetaLine(item.mediaEntity).releaseParts(language: .en)
      .contains(RuntimeText(seconds: 5257).text(for: .detailRuntime, language: .en)!))
  }

  /// `audios[].author` is null on an original-language track — the field is only filled
  /// for dubs, and `AudioTracks` must not require it.
  func testOriginalAudioHasNoAuthor() throws {
    let tracks = try item().audioTracks
    XCTAssertEqual(tracks.count, 1)
  }

  /// The setlist, in order: six songs, the unknown one kept in its place with no name
  /// («N/A» on the wire), the empty `artists` and `url` read as nothing.
  func testTheTracklistIsTheSetlist() throws {
    let item = try item()
    XCTAssertEqual(item.tracklist?.count, 6)
    XCTAssertEqual(item.tracklist?.first?.title, "Ruhe")

    let setlist = item.mediaFragment.entity.setlist
    XCTAssertEqual(setlist.count, 6)
    XCTAssertEqual(setlist.first?.title, "Ruhe")
    XCTAssertNil(setlist.first?.artists)
    XCTAssertNil(setlist.first?.audio)
    XCTAssertNil(setlist[3].title, "«N/A» is a song nobody named, not a song called N/A")
  }

  /// A film sends `tracklist` too, with its audio tracks in it («Дубляж», «Оригинал,
  /// Английский»): that is no setlist, and the page must not draw one (Sasha, 2026-10-25).
  func testAFilmsTracklistIsNoSetlist() throws {
    let url = try XCTUnwrap(Bundle.module.url(forResource: "item_126187_concert",
                                              withExtension: "json",
                                              subdirectory: "Fixtures"))
    var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    var payload = try XCTUnwrap(json["item"] as? [String: Any])
    payload["type"] = "movie"
    payload["tracklist"] = [["title": "Дубляж", "artists": "", "url": ""],
                            ["title": "Оригинал, Английский", "artists": "", "url": ""]]
    json["item"] = payload
    let film = try JSONDecoder().decode(SingleItemData<MediaItem>.self,
                                        from: JSONSerialization.data(withJSONObject: json)).item
    XCTAssertEqual(film.tracklist?.count, 2, "decoded as sent")
    XCTAssertTrue(film.mediaFragment.entity.setlist.isEmpty)
    XCTAssertFalse(film.presentation.showsSetlist)
  }

  /// The API documentation spells it `artist`; the live payload `artists`. Both read.
  func testATracklistEntryReadsEitherSpelling() throws {
    let documented = try JSONDecoder().decode(TracklistEntry.self, from: Data(
      #"{"artist": "Schiller", "title": "Ruhe", "url": ""}"#.utf8))
    XCTAssertEqual(documented.artists, "Schiller")
  }
}
