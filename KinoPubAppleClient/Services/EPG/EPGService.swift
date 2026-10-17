//
//  EPGService.swift
//  KinoPubAppleClient
//
//  The schedule of kino.pub's live channels. `/v1/tv` sends none (`current` / `playlist` are
//  empty), so it comes from an outside guide, matched to the channels by a table of our own.
//

import Foundation
import KinoPubBackend

protocol EPGService: Sendable {
  /// Each channel's schedule around now, keyed by `TVChannel.id`, in start order. A channel the
  /// guide does not carry, or could not be fetched, is simply absent: the grid shows it without.
  func schedules(for channels: [TVChannel]) async -> [Int: [EPGProgram]]
}

/// Answers with what it is given — previews, fixtures, tests.
struct EPGServiceMock: EPGService {
  var schedules: @Sendable ([TVChannel]) -> [Int: [EPGProgram]] = { _ in [:] }

  func schedules(for channels: [TVChannel]) async -> [Int: [EPGProgram]] {
    schedules(channels)
  }
}
