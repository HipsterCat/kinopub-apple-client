//
//  WatchProgressTests.swift
//  KinoPubBackendTests
//
//  Exhaustive edge-case coverage for the watched / in-progress / finished classifier.
//

import XCTest
@testable import KinoPubBackend

final class WatchProgressTests: XCTestCase {

  // MARK: No usable duration (live channels, trailers, bad data)

  func testZeroDurationIsUnwatched() {
    let p = WatchProgress(position: 120, duration: 0)
    XCTAssertNil(p.fraction)
    XCTAssertFalse(p.isFinished)
    XCTAssertFalse(p.hasStarted)
    XCTAssertFalse(p.isResumable)
    XCTAssertEqual(p.state, .unwatched)
  }

  func testNonFiniteDurationIsUnwatched() {
    for d in [Double.nan, .infinity, -.infinity] {
      let p = WatchProgress(position: 120, duration: d)
      XCTAssertNil(p.fraction, "duration \(d)")
      XCTAssertEqual(p.state, .unwatched, "duration \(d)")
      XCTAssertFalse(p.isFinished)
    }
  }

  func testNegativeDurationIsUnwatched() {
    let p = WatchProgress(position: 50, duration: -100)
    XCTAssertNil(p.fraction)
    XCTAssertEqual(p.state, .unwatched)
  }

  // MARK: Not started

  func testZeroPositionIsUnwatched() {
    let p = WatchProgress(position: 0, duration: 3600)
    XCTAssertEqual(p.fraction, 0)
    XCTAssertEqual(p.state, .unwatched)
    XCTAssertFalse(p.isResumable)
  }

  func testNegativePositionIsUnwatchedAndClampsFractionToZero() {
    let p = WatchProgress(position: -30, duration: 3600)
    XCTAssertEqual(p.fraction, 0)
    XCTAssertEqual(p.state, .unwatched)
  }

  func testBelowStartFloorIsUnwatched() {
    // 5s into an hour — an accidental tap, should not appear in Continue Watching.
    let p = WatchProgress(position: 5, duration: 3600)
    XCTAssertFalse(p.hasStarted)
    XCTAssertEqual(p.state, .unwatched)
    XCTAssertFalse(p.isResumable)
    XCTAssertEqual(p.fraction ?? -1, 5.0 / 3600.0, accuracy: 1e-9)
  }

  func testExactlyAtStartFloorIsInProgress() {
    let p = WatchProgress(position: WatchProgress.startedSeconds, duration: 3600)
    XCTAssertTrue(p.hasStarted)
    XCTAssertTrue(p.isResumable)
    if case .inProgress = p.state {} else { XCTFail("expected inProgress, got \(p.state)") }
  }

  // MARK: In progress

  func testMidwayIsInProgressWithFraction() {
    let p = WatchProgress(position: 1800, duration: 3600)
    XCTAssertEqual(p.fraction, 0.5)
    XCTAssertTrue(p.isResumable)
    XCTAssertFalse(p.isFinished)
    XCTAssertEqual(p.state, .inProgress(0.5))
  }

  // MARK: Finished — kino.pub's 85%

  /// The probe that set the rule: «Трудно быть богом» S1E10, 3392 s, 2026-10-16.
  func testWatchedIsEightyFivePercentAsTheServerSaysIt() {
    XCTAssertFalse(WatchProgress(position: 2883, duration: 3392).isFinished, "84.99%")
    XCTAssertTrue(WatchProgress(position: 2884, duration: 3392).isFinished, "85.02%")
  }

  /// VisionQuest S1E2: 2434 of 2706 s, `watched: 1` on its page — and now on Home too.
  func testThePlayHeadThatHomeCalledInProgress() {
    let p = WatchProgress(position: 2434, duration: 2706)
    XCTAssertTrue(p.isFinished)
    XCTAssertFalse(p.isResumable)
    XCTAssertNil(p.resumeFraction)
  }

  /// Invasion S3E10 at 68% stays a resume, as the server's flag does (`watched: 0`).
  func testWellBeforeTheThresholdIsInProgress() {
    let p = WatchProgress(position: 2122, duration: 3111)
    XCTAssertFalse(p.isFinished)
    XCTAssertTrue(p.isResumable)
  }

  func testExactlyAtDurationIsFinished() {
    let p = WatchProgress(position: 3600, duration: 3600)
    XCTAssertTrue(p.isFinished)
    XCTAssertEqual(p.fraction, 1)
    XCTAssertEqual(p.state, .finished)
  }

  func testPastDurationIsFinishedAndFractionClampedToOne() {
    // Rounding / over-report should never read >1 or flip back to in-progress.
    let p = WatchProgress(position: 3650, duration: 3600)
    XCTAssertTrue(p.isFinished)
    XCTAssertEqual(p.fraction, 1)
    XCTAssertEqual(p.state, .finished)
  }

  func testShortClipClassification() {
    XCTAssertEqual(WatchProgress(position: 52, duration: 60).state, .finished)   // 86.7%
    XCTAssertTrue(WatchProgress(position: 40, duration: 60).isResumable)         // 66.7%
    XCTAssertEqual(WatchProgress(position: 5, duration: 60).state, .unwatched)   // below start floor
  }

  // MARK: Up Next lead time (when to offer the next episode — not "watched")

  func testUpNextLeadTimeIsFlooredAndCapped() {
    XCTAssertEqual(WatchProgress.upNextLeadTime(forDuration: 7200), 180)   // 8% = 576 → cap 180
    XCTAssertEqual(WatchProgress.upNextLeadTime(forDuration: 1800), 144)   // 8% = 144
    XCTAssertEqual(WatchProgress.upNextLeadTime(forDuration: 600), 60)     // 8% = 48 → floor 60
    XCTAssertEqual(WatchProgress.upNextLeadTime(forDuration: 60), 30)      // half a short clip
  }

  // MARK: Continue-watching gate

  func testIsResumableOnlyForInProgress() {
    XCTAssertFalse(WatchProgress(position: 0, duration: 3600).isResumable)        // unwatched
    XCTAssertTrue(WatchProgress(position: 1800, duration: 3600).isResumable)      // in progress
    XCTAssertFalse(WatchProgress(position: 3599, duration: 3600).isResumable)     // finished
    XCTAssertFalse(WatchProgress(position: 100, duration: 0).isResumable)         // live
  }

  func testResumeFractionIsNilOutsideInProgress() {
    XCTAssertNil(WatchProgress(position: 5, duration: 3600).resumeFraction)
    XCTAssertEqual(WatchProgress(position: 1800, duration: 3600).resumeFraction, 0.5)
    XCTAssertNil(WatchProgress(position: 3599, duration: 3600).resumeFraction)
    // 10s into an hour is started, but far below a 0.02 UI fudge — the bar still paints.
    let justStarted = WatchProgress(position: WatchProgress.startedSeconds, duration: 3600)
    XCTAssertEqual(justStarted.resumeFraction ?? -1, 10.0 / 3600.0, accuracy: 1e-9)
  }
}

/// The id every `/v1/watching*` call must carry is the **item's**, never the episode's.
/// `/v1/watching?id=928900&season=1&video=2` answered 404 live: 928900 is the media id
/// of episode 2, and the item is 87940.
final class WatchingMetadataIdentityTests: XCTestCase {

  private func episode(id: Int, number: Int) -> Episode {
    Episode(id: id, title: "Трек \(number)", thumbnail: "", duration: 3064, tracks: 1,
            number: number, ac3: 0, audios: [], watched: 0,
            watching: EpisodeWatching(status: 0, time: 0), subtitles: [], files: [])
  }

  private func season(mediaId: Int?) -> Season {
    let episodes = [
      episode(id: 928899, number: 1),
      episode(id: 928900, number: 2)
    ]
    let season = Season(id: 1, title: "Сезон 1", number: 1,
                        watching: SeasonWatching(status: 0), episodes: episodes)
    season.mediaId = mediaId
    return season
  }

  func testStampingASeasonStampsItsEpisodes() {
    let season = self.season(mediaId: 87940)
    XCTAssertEqual(season.episodes.map(\.mediaId), [87940, 87940])
  }

  func testEpisodeReportsTheItemIdNotItsOwn() {
    let episode = season(mediaId: 87940).episodes[1]
    XCTAssertEqual(episode.id, 928900)
    XCTAssertEqual(episode.metadata.id, 87940)
    XCTAssertEqual(episode.metadata.video, 2)
    XCTAssertTrue(episode.metadata.isResolved)
  }

  /// An unstamped episode must report *nothing* rather than its own media id — that id
  /// may well be a real item id belonging to some other title.
  func testUnstampedEpisodeIsUnresolvedRatherThanWrong() {
    let episode = season(mediaId: nil).episodes[1]
    XCTAssertNotEqual(episode.metadata.id, episode.id)
    XCTAssertFalse(episode.metadata.isResolved)
  }
  // MARK: - Earning a Continue Watching card

  /// The floor for "has begun" is 10s and stays there — it paints a bar. Earning a card
  /// the server never listed is a separate, higher bar, because nothing takes that card
  /// back out again.
  func testAMinuteOfATrailerDoesNotEarnACard() {
    let watch = WatchProgress(position: 55, duration: 3600)
    XCTAssertTrue(watch.isResumable, "55s is past the started floor")
    XCTAssertFalse(watch.earnsContinueWatchingCard)
  }

  func testPastTheEntryFloorEarnsACard() {
    let watch = WatchProgress(position: 95, duration: 3600)
    XCTAssertTrue(watch.earnsContinueWatchingCard)
  }

  func testAFinishedTitleNeverEarnsACard() {
    let watch = WatchProgress(position: 3595, duration: 3600)
    XCTAssertTrue(watch.isFinished)
    XCTAssertFalse(watch.earnsContinueWatchingCard)
  }

}
