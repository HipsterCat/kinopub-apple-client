//
//  MultiVersionItemTests.swift
//
//  Against the real `GET /v1/items/124447` response — the title ROADMAP.md used as the
//  multi-version probe. `Fixtures/item_124447_multi.json` is that payload with the long
//  signed CDN URLs replaced, the subtitle list cut from 55 entries to 2, audio cut to 2,
//  files cut to 2 per video, and the plot/cast shortened. Nothing the decoder reads or
//  these tests assert on was changed — in particular `duration`, `subtype`, and both
//  videos' `id` / `number` / `title` / `watching` are verbatim.
//

import XCTest
@testable import KinoPubBackend

final class MultiVersionItemTests: XCTestCase {

  private func item() throws -> MediaItem {
    let url = try XCTUnwrap(Bundle.module.url(forResource: "item_124447_multi",
                                              withExtension: "json",
                                              subdirectory: "Fixtures"))
    let data = try Data(contentsOf: url)
    // The exact envelope `VideoContentServiceImpl` decodes `GET /v1/items/{id}` into.
    return try JSONDecoder().decode(SingleItemData<MediaItem>.self, from: data).item
  }

  /// The whole point: this payload must decode at all. Every field `Video` requires is
  /// non-optional, so one missing key on a real response is a blank detail page.
  func testTheRealPayloadDecodes() throws {
    let item = try item()
    XCTAssertEqual(item.id, 124447)
    XCTAssertEqual(item.type, "movie")
    XCTAssertEqual(item.subtype, "multi")
    XCTAssertEqual(item.videos?.count, 2)
    XCTAssertFalse(item.isSeries, "A multi-version film has no seasons and must not read as a series")
  }

  func testVersionsBecomePlaybackVariantsInNumberOrder() throws {
    let variants = try item().playbackVariants
    XCTAssertEqual(variants.map(\.title), ["24 fps", "48 fps"])
    XCTAssertEqual(variants.map(\.id), [1149307, 1155958])
    XCTAssertEqual(variants.map(\.number), [1, 2])
  }

  /// A variant reports against the *film*, differing only by `video`. This is the shape
  /// `MediaItem` already sent for a single-video film, so playback reporting is unchanged
  /// except that it now names the right encoding.
  func testVariantMetadataPointsAtTheFilmAndTheVideoNumber() throws {
    let variants = try item().playbackVariants
    XCTAssertEqual(variants.map(\.metadata.id), [124447, 124447])
    XCTAssertEqual(variants.map(\.metadata.video), [1, 2])
    XCTAssertTrue(variants.allSatisfy { $0.metadata.season == nil })
  }

  /// Subtitles are per version, not per film — on this title 24 fps carries them and
  /// 48 fps carries none. Reading them off `videos.first` handed the 48 fps player a
  /// subtitle list that does not belong to it.
  func testSubtitlesBelongToTheVariantNotTheFilm() throws {
    let variants = try item().playbackVariants
    XCTAssertFalse(variants[0].subtitles.isEmpty)
    XCTAssertTrue(variants[1].subtitles.isEmpty)
  }

  /// `duration.total` is the sum of both encodings (8634 + 8634). Rendering it made a
  /// 2 h 24 min film claim 4 h 48 min.
  func testRuntimeUsesTheFilmsLengthNotTheSumOfItsVersions() throws {
    let item = try item()
    XCTAssertEqual(item.duration.total, 17268)
    XCTAssertEqual(item.duration.average, 8634)
    XCTAssertTrue(item.releaseLine.contains(Duration.compact(seconds: 8634)),
                  "releaseLine was \(item.releaseLine)")
    XCTAssertFalse(item.releaseLine.contains(Duration.compact(seconds: 17268)))
  }

  /// Both versions are watched on this account, so Play offers to start over — and the
  /// verdict is reached by looking at every version, not only the first.
  func testPlaybackActionConsidersEveryVersion() throws {
    XCTAssertEqual(try item().playbackAction, .playAgain)
  }

  /// Each version's play button says how far into *that* version you are. Both are
  /// watched on this account, so both offer to start over; both carry their names.
  func testEachVersionCarriesItsOwnPlaybackStateAndName() throws {
    let variants = try item().playbackVariants
    XCTAssertEqual(variants.map(\.playbackButtonContent),
                   [.playAgain(season: nil, episode: nil), .playAgain(season: nil, episode: nil)])
    XCTAssertEqual(variants.map(\.name), ["24 fps", "48 fps"])
  }

  /// One version half-watched, the other untouched, neither named: the started one
  /// resumes at its own position, the other plays fresh, and there is no name for a
  /// button to show (the numbered `title` stays for the rail).
  func testVersionStateComesFromThatVersionAlone() throws {
    func video(id: Int, number: Int, time: Int) -> Video {
      Video(id: id, title: "  ", thumbnail: "", duration: 6000, tracks: 1, number: number, ac3: 0,
            audios: [], watched: 0, watching: EpisodeWatching(status: 0, time: time),
            subtitles: [], files: [])
    }
    let first = PlaybackVariant(video: video(id: 1, number: 1, time: 3000), mediaId: 9, movieTitle: "Film")
    let second = PlaybackVariant(video: video(id: 2, number: 2, time: 0), mediaId: 9, movieTitle: "Film")
    guard case .resume(let progress, let season, let episode, let duration) = first.playbackButtonContent else {
      return XCTFail("a started version should resume, got \(first.playbackButtonContent)")
    }
    XCTAssertEqual(progress, 0.5, accuracy: 0.01)
    XCTAssertNil(season)
    XCTAssertNil(episode)
    XCTAssertEqual(duration, 6000)
    XCTAssertEqual(second.playbackButtonContent, .play(season: nil, episode: nil))
    XCTAssertNil(first.name)
    XCTAssertEqual(first.title, "Version 1")
  }

  /// A single-video film has nothing to choose between, so no rail and no behaviour
  /// change: `playbackVariants` is empty and the runtime still comes from `total`.
  func testSingleVideoFilmHasNoVariants() throws {
    let item = MediaItem.mock()
    XCTAssertTrue(item.playbackVariants.isEmpty)
    XCTAssertFalse(item.isMultiVersion)
  }
}
