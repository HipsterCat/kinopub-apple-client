//
//  EPGProgram.swift
//  KinoPubAppleClient
//
//  One programme on a live channel's schedule (EPG).
//

import Foundation

/// A broadcast on a channel: what it is called, when it starts and when it ends.
struct EPGProgram: Hashable, Codable, Sendable {
  let title: String
  let start: Date
  let stop: Date

  /// On air at `date`.
  func isLive(at date: Date) -> Bool { start <= date && date < stop }
}

extension Array where Element == EPGProgram {
  /// What is on air at `date`, from a schedule in start order.
  func live(at date: Date) -> EPGProgram? {
    first { $0.isLive(at: date) }
  }
}
