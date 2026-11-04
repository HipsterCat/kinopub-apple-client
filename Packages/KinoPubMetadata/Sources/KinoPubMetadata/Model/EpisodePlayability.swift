//
//  EpisodePlayability.swift
//

import Foundation

/// What a known air date may do to an episode kino.pub already has.
///
/// A file on the service is playable whatever TMDB, TVDB or IMDb say about the
/// premiere (Sasha, 2026-10-31). Dexter S2E1 was badged «Завтра» and would not
/// open; the file was already there, and the date later moved. A date a few days
/// out is that lag. A date further out, with the file already up, is an early drop
/// and may wear «Премьера» — the tile still plays.
public enum EpisodePlayability {

  /// Days past today before a future premiere on an available file counts as an
  /// early drop rather than a date the catalog has not caught up with.
  public static let earlyDropLeadDays = 7

  public enum Decision: Equatable, Sendable {
    /// `premiere` is the optional early-drop badge. Never a reason to block playback.
    case playable(premiere: Bool)
    /// Not on kino.pub. The schedule, if any, says when.
    case unavailable
  }

  /// `onService` is kino.pub listing the episode with a file ladder or a runtime.
  /// A `nolinks` payload still lists the ladder, and the duration is on the episode
  /// either way — both mean the file is there.
  public static func decision(onService: Bool,
                              airDate: Date?,
                              now: Date = Date(),
                              calendar: Calendar = .current) -> Decision {
    guard onService else { return .unavailable }
    guard let airDate else { return .playable(premiere: false) }
    let days = calendar.dateComponents(
      [.day],
      from: calendar.startOfDay(for: now),
      to: calendar.startOfDay(for: airDate)).day ?? 0
    return .playable(premiere: days > earlyDropLeadDays)
  }

  public static func onService(fileCount: Int, durationSeconds: Int) -> Bool {
    fileCount > 0 || durationSeconds >= 60
  }
}
