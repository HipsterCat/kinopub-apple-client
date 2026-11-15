//
//  PlaybackSkipTests.swift
//  KinoPubAppleClientTests
//
//  Which skip button the player offers, and when (`PlaybackSkip.offer`).
//

import XCTest
import KinoPubMetadata
@testable import KinoPub

final class PlaybackSkipTests: XCTestCase {

  private var segments: SkipSegments {
    var segments = SkipSegments()
    segments[.recap] = .init(startMs: 0, endMs: 40_000, source: .skipDB)
    segments[.intro] = .init(startMs: 60_000, endMs: 120_000, source: .skipDB)
    segments[.credits] = .init(startMs: 2_500_000, endMs: nil, source: .introdb)
    return segments
  }

  func testOffersTheSegmentPlayingAndJumpsToItsEnd() {
    let offer = PlaybackSkip.offer(at: 61, in: segments, durationSeconds: 2_600, isEpisode: true)
    XCTAssertEqual(offer, .init(kind: .intro, targetSeconds: 120))
  }

  func testNothingBetweenSegmentsOrInTheirLastSeconds() {
    XCTAssertNil(PlaybackSkip.offer(at: 50, in: segments, durationSeconds: 2_600, isEpisode: true))
    XCTAssertNil(PlaybackSkip.offer(at: 118.5, in: segments, durationSeconds: 2_600, isEpisode: true))
  }

  func testOpenEndedCreditsRunToTheEndOfTheStream() {
    let offer = PlaybackSkip.offer(at: 2_510, in: segments, durationSeconds: 2_600, isEpisode: true)
    XCTAssertEqual(offer, .init(kind: .credits, targetSeconds: 2_600))
  }

  func testAFilmIsNeverOfferedItsCredits() {
    XCTAssertNil(PlaybackSkip.offer(at: 2_510, in: segments, durationSeconds: 2_600, isEpisode: false))
    XCTAssertEqual(PlaybackSkip.offer(at: 10, in: segments, durationSeconds: 2_600, isEpisode: false)?.kind, .recap)
  }

  func testClosingCreditsGiveWayToTheNextEpisode() {
    XCTAssertEqual(PlaybackSkip.closingCreditsStart(in: segments, durationSeconds: 2_600), 2_500)
    XCTAssertNil(PlaybackSkip.offer(at: 2_510, in: segments, durationSeconds: 2_600, isEpisode: true,
                                    nextEpisodeAtCredits: true))
    // Credits with a scene after them keep their skip.
    var withScene = segments
    withScene[.credits] = .init(startMs: 2_400_000, endMs: 2_500_000, source: .skipDB)
    XCTAssertNil(PlaybackSkip.closingCreditsStart(in: withScene, durationSeconds: 2_600))
    XCTAssertEqual(PlaybackSkip.offer(at: 2_410, in: withScene, durationSeconds: 2_600, isEpisode: true,
                                      nextEpisodeAtCredits: true)?.kind, .credits)
  }

  func testCountdownRunsOnPlaybackTime() {
    XCTAssertEqual(PlaybackSkip.countdownLeft(at: 60, shownAt: 60), 1)
    XCTAssertEqual(PlaybackSkip.countdownLeft(at: 62.5, shownAt: 60), 0.5, accuracy: 0.001)
    XCTAssertEqual(PlaybackSkip.countdownLeft(at: 70, shownAt: 60), 0)
  }

  func testAutomaticSkipUsesTheChosenDelayAndNeverFiresAtOnce() {
    XCTAssertEqual(PlaybackSkip.countdownLeft(elapsed: 0, delay: 4), 1)
    XCTAssertEqual(PlaybackSkip.countdownLeft(elapsed: 2, delay: 4), 0.5, accuracy: 0.001)
    XCTAssertEqual(PlaybackSkip.countdownLeft(elapsed: 4, delay: 4), 0)
    XCTAssertEqual(PlaybackSkip.countdownLeft(elapsed: 10, delay: 0), 1)
  }

  func testAppleStyleDoesNotPressTheButton() {
    XCTAssertFalse(PlaybackSkip.shouldAutoSkip(style: .apple, countdownLeft: 0))
    XCTAssertFalse(PlaybackSkip.shouldAutoSkip(style: .countdown, countdownLeft: 0.2))
    XCTAssertTrue(PlaybackSkip.shouldAutoSkip(style: .countdown, countdownLeft: 0))
    XCTAssertTrue(PlaybackSkip.shouldAutoSkip(style: .banner, countdownLeft: 0))
    XCTAssertEqual(SkipAutoStyle.allCases.count, 7)
  }

  func testChipStaysDownWhileChromeIsHiddenOrAMenuIsOpen() {
    XCTAssertTrue(SkipChipVisibility.shown(hasOffer: true, controlsVisible: true, menuActive: false))
    XCTAssertFalse(SkipChipVisibility.shown(hasOffer: true, controlsVisible: false, menuActive: false))
    XCTAssertFalse(SkipChipVisibility.shown(hasOffer: true, controlsVisible: true, menuActive: true))
    XCTAssertFalse(SkipChipVisibility.shown(hasOffer: false, controlsVisible: true, menuActive: false))
  }

  func testCountdownClockRoundsUp() {
    XCTAssertEqual(PlaybackSkip.countdownSecondsLeft(countdownLeft: 1, delay: 4), 4)
    XCTAssertEqual(PlaybackSkip.countdownSecondsLeft(countdownLeft: 0.5, delay: 4), 2)
    XCTAssertEqual(PlaybackSkip.countdownSecondsLeft(countdownLeft: 0.01, delay: 4), 1)
  }
}
