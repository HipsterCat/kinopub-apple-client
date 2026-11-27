//
//  PlaybackSkipTests.swift
//  PiraticTests
//
//  Which skip button the player offers, and when (`PlaybackSkip.offer`).
//

import XCTest
import PiraticMetadata
@testable import Piratic

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
    guard let offer else { return }
    XCTAssertTrue(PlaybackSkip.finishesTitle(offer, durationSeconds: 2_600))
    XCTAssertEqual(PlaybackSkip.symbolName(for: offer, durationSeconds: 2_600), "forward.end.fill")
  }

  func testAFilmIsOfferedClosingCreditsThatFinishTheTitle() {
    let offer = PlaybackSkip.offer(at: 2_510, in: segments, durationSeconds: 2_600, isEpisode: false)
    XCTAssertEqual(offer, .init(kind: .credits, targetSeconds: 2_600))
    guard let offer else { return }
    XCTAssertTrue(PlaybackSkip.finishesTitle(offer, durationSeconds: 2_600))
    XCTAssertEqual(PlaybackSkip.symbolName(for: offer, durationSeconds: 2_600), "forward.end.fill")
    XCTAssertEqual(PlaybackSkip.offer(at: 10, in: segments, durationSeconds: 2_600, isEpisode: false)?.kind, .recap)
    // Mid-film credits with a scene after them stay off.
    var withScene = segments
    withScene[.credits] = .init(startMs: 2_400_000, endMs: 2_500_000, source: .skipDB)
    XCTAssertNil(PlaybackSkip.offer(at: 2_410, in: withScene, durationSeconds: 2_600, isEpisode: false))
  }

  func testNormalSkipUsesForwardFillSymbol() {
    guard let offer = PlaybackSkip.offer(at: 61, in: segments, durationSeconds: 2_600, isEpisode: true) else {
      return XCTFail("expected intro skip")
    }
    XCTAssertFalse(PlaybackSkip.finishesTitle(offer, durationSeconds: 2_600))
    XCTAssertEqual(PlaybackSkip.symbolName(for: offer, durationSeconds: 2_600), "forward.fill")
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

  func testMacChipStaysWithTheChromeAndNeverOverAMenu() {
    XCTAssertTrue(SkipChipVisibility.shown(hasOffer: true, controlsVisible: true, menuActive: false, followsChrome: true))
    XCTAssertFalse(SkipChipVisibility.shown(hasOffer: true, controlsVisible: false, menuActive: false, followsChrome: true))
    XCTAssertFalse(SkipChipVisibility.shown(hasOffer: true, controlsVisible: true, menuActive: true, followsChrome: true))
    XCTAssertFalse(SkipChipVisibility.shown(hasOffer: false, controlsVisible: true, menuActive: false, followsChrome: true))
  }

  func testPhoneAndPadChipTakesThePlaceOfTheChrome() {
    XCTAssertTrue(SkipChipVisibility.shown(hasOffer: true, controlsVisible: false, menuActive: false, followsChrome: false))
    XCTAssertFalse(SkipChipVisibility.shown(hasOffer: true, controlsVisible: true, menuActive: false, followsChrome: false))
    XCTAssertFalse(SkipChipVisibility.shown(hasOffer: true, controlsVisible: false, menuActive: true, followsChrome: false))
    XCTAssertFalse(SkipChipVisibility.shown(hasOffer: false, controlsVisible: false, menuActive: false, followsChrome: false))
  }

  func testTVSkipIsActionableOnlyWithChromeDownAndNoMenu() {
    XCTAssertTrue(SkipChipVisibility.actionable(hasOffer: true, transportBarVisible: false, menuActive: false))
    XCTAssertFalse(SkipChipVisibility.actionable(hasOffer: true, transportBarVisible: true, menuActive: false))
    XCTAssertFalse(SkipChipVisibility.actionable(hasOffer: true, transportBarVisible: false, menuActive: true))
    XCTAssertFalse(SkipChipVisibility.actionable(hasOffer: false, transportBarVisible: false, menuActive: false))
  }

  func testCountdownSuspendsWhenSkipWouldBeHidden() {
    // iOS / macOS: chip follows chrome.
    XCTAssertTrue(SkipChipVisibility.countdownSuspended(chromeVisible: false, menuActive: false,
                                                        chipFollowsChrome: true))
    XCTAssertTrue(SkipChipVisibility.countdownSuspended(chromeVisible: true, menuActive: true,
                                                        chipFollowsChrome: true))
    XCTAssertFalse(SkipChipVisibility.countdownSuspended(chromeVisible: true, menuActive: false,
                                                         chipFollowsChrome: true))
    // tvOS: Skip is the inverse of the transport bar.
    XCTAssertTrue(SkipChipVisibility.countdownSuspended(chromeVisible: true, menuActive: false,
                                                        chipFollowsChrome: false))
    XCTAssertTrue(SkipChipVisibility.countdownSuspended(chromeVisible: false, menuActive: true,
                                                        chipFollowsChrome: false))
    XCTAssertFalse(SkipChipVisibility.countdownSuspended(chromeVisible: false, menuActive: false,
                                                         chipFollowsChrome: false))
  }

  func testTransportMenuHeuristicsCoverSpeedAndTrackMenus() {
    XCTAssertTrue(PlayerTransportMenu.looksLikeMenu("AVPlaybackSpeedMenuView"))
    XCTAssertTrue(PlayerTransportMenu.looksLikeMenu("AVMediaSelectionView"))
    XCTAssertTrue(PlayerTransportMenu.looksLikeMenu("UIContextMenuContainer"))
    XCTAssertFalse(PlayerTransportMenu.looksLikeMenu("AVPlaybackControlsView"))
    XCTAssertFalse(PlayerTransportMenu.looksLikeMenu("UILabel"))
  }

  func testCountdownClockRoundsUp() {
    XCTAssertEqual(PlaybackSkip.countdownSecondsLeft(countdownLeft: 1, delay: 4), 4)
    XCTAssertEqual(PlaybackSkip.countdownSecondsLeft(countdownLeft: 0.5, delay: 4), 2)
    XCTAssertEqual(PlaybackSkip.countdownSecondsLeft(countdownLeft: 0.01, delay: 4), 1)
  }
}
