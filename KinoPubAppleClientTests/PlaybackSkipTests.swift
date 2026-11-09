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
}
