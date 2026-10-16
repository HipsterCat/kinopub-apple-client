//
//  WatchProgress.swift
//  KinoPubBackend
//
//  Single source of truth for "how far through a title is the viewer, and is it finished".
//  Everything — the Continue Watching row, the card badge, the player's end-of-playback handling,
//  the series "next episode" logic — classifies progress through THIS type, so the thresholds live
//  in exactly one place (and are unit-tested) instead of being re-derived with magic numbers.
//
//  Backend note: kino.pub derives a video's watched status server-side from the playback position
//  you report via `/v1/watching/marktime`. So you don't "toggle watched" on a normal finish — you
//  just keep reporting the position, and once it crosses the end tolerance the server treats it as
//  watched and drops it from the watching list. `isFinished` is **that rule**: 85% of the runtime,
//  measured (see `watchedFraction`), so a bare play head — this device's, a history row — reads
//  the same as the server's flag on the same title. Where the flag is at hand it still wins
//  (`Episode.isWatched`); the two now only differ while the server has not heard a play head yet.
//

import Foundation

public struct WatchProgress: Equatable, Hashable, Codable, Sendable {

  /// Seconds watched.
  public let position: Double
  /// Total runtime in seconds. May be 0 or non-finite for live channels / trailers — handled as
  /// "no progress".
  public let duration: Double

  // MARK: Thresholds (the only place these numbers exist)

  /// Below this many seconds a title counts as "not really started" (an accidental tap) and is kept
  /// out of Continue Watching.
  public static let startedSeconds: Double = 10

  /// What a title has to clear before it earns a Continue Watching card **the server
  /// never asked for**.
  ///
  /// `startedSeconds` answers "has this begun" — enough to paint a bar on a card that
  /// is already in the row. Putting a brand-new card there is a larger claim, and a
  /// local-only one has nothing to take it back out: the server does not list the
  /// title, so no refresh will drop it. A minute of a trailer or a sampled clip was
  /// the row's most common piece of junk, and 10s is exactly the bar it cleared.
  public static let enterContinueWatchingSeconds: Double = 90

  /// **Watched is 85% of the runtime** — kino.pub's own rule (user's call to match it,
  /// 2026-10-16). Probed live with `marktime` on a 3392 s episode: 2883 s (84.99%) left it
  /// unwatched, 2884 s (85.02%) watched, and lowering the play head unwatched it again — the
  /// server recomputes from the current play head, nothing sticks. 186 play heads on the
  /// account agree (watched from 86.6% up, not at 68.2%). The credits are where people stop;
  /// a remnant of them is not something to continue.
  public static let watchedFraction: Double = 0.85

  /// How long before the end the player's Up Next proposal appears — **when to offer the
  /// next episode, not when this one counts as watched** (that is `watchedFraction`, which
  /// would raise the panel minutes early). 8% of the runtime, floored at 60 s, capped at
  /// 180 s and at half the runtime.
  public static func upNextLeadTime(forDuration duration: Double) -> Double {
    let byFraction = min(max(duration * 0.08, 60), 180)
    return min(byFraction, duration * 0.5)
  }

  public enum State: Equatable {
    /// Not started (or below the "started" floor, or no usable duration).
    case unwatched
    /// Started but not finished. Associated value is the fraction watched (0...1).
    case inProgress(Double)
    /// Watched to (or past) the end / credits.
    case finished
  }

  public init(position: Double, duration: Double) {
    self.position = position
    self.duration = duration
  }

  private var hasUsableDuration: Bool { duration.isFinite && duration > 0 }

  /// Fraction watched, clamped to 0...1. `nil` when there's no usable duration (live / trailer).
  public var fraction: Double? {
    guard hasUsableDuration else { return nil }
    return min(max(position / duration, 0), 1)
  }

  /// Past the start floor (and has a real duration) — i.e. intentionally started.
  public var hasStarted: Bool {
    hasUsableDuration && position >= Self.startedSeconds
  }

  /// Watched to the end / credits.
  public var isFinished: Bool {
    guard hasUsableDuration, position > 0 else { return false }
    return position >= duration * Self.watchedFraction
  }

  public var state: State {
    guard hasUsableDuration, position > 0 else { return .unwatched }
    if isFinished { return .finished }
    guard hasStarted else { return .unwatched }
    return .inProgress(fraction ?? 0)
  }

  /// Belongs in "Continue Watching": started, but not yet finished.
  public var isResumable: Bool {
    if case .inProgress = state { return true }
    return false
  }

  /// Resumable *and* watched long enough to deserve a card of its own — the test for a
  /// title only local progress knows about. See `enterContinueWatchingSeconds`.
  public var earnsContinueWatchingCard: Bool {
    isResumable && position >= Self.enterContinueWatchingSeconds
  }

  /// Fraction to paint on a resume bar. Nil when there is nothing to resume —
  /// unwatched, live, or already watched (`watchedFraction`).
  ///
  /// Cards store this, not a raw `time / duration`. Re-thresholding a stored
  /// fraction (0.95, 0.02) cannot recover `watchedFraction` and will disagree with
  /// Continue Watching the moment skip/outro markers feed this type.
  public var resumeFraction: Double? {
    switch state {
    case .inProgress(let fraction): return fraction
    case .unwatched, .finished: return nil
    }
  }
}
