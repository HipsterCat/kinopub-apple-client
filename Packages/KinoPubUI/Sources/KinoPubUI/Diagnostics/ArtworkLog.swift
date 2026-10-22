#if os(tvOS)
//
//  ArtworkLog.swift
//  KinoPubUI
//
//  Tracing for the TVUIKit artwork path. It exists because of a question that was
//  unanswerable from the screen: when a rail shows monograms instead of faces, is the
//  request failing, or was it never made? Those two look identical and have opposite
//  fixes — one is the photo source, the other is the code that decides there is no
//  photo to fetch. `requested` / `skipped` separate them on the first frame.
//
//  Read it with either:
//    Console.app → filter subsystem `artwork`
//    xcrun simctl spawn booted log stream --predicate 'category == "artwork"'
//

import OSLog
import Foundation

public enum ArtworkLog {

  /// Off in release builds; the instrumentation compiles away with it.
  public static var isEnabled: Bool = {
#if DEBUG
    true
#else
    false
#endif
  }()

  private static let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "Kinopub Soda",
    category: "artwork"
  )

  /// A cell asked for a URL we did not already have decoded.
  public static func requested(_ url: URL, by owner: String) {
    guard isEnabled else { return }
    logger.debug("↓ GET  \(owner, privacy: .public) · \(url.lastPathComponent, privacy: .public)")
  }

  /// A cell had nothing to ask for. This is the line that says "no photo was known",
  /// as opposed to "the photo failed" — the distinction the whole log exists for.
  public static func skipped(by owner: String, reason: String) {
    guard isEnabled else { return }
    logger.info("· SKIP \(owner, privacy: .public) · \(reason, privacy: .public)")
  }

  /// Served from the decoded-image cache without touching the network or a decode.
  public static func servedFromMemory(_ url: URL, by owner: String) {
    guard isEnabled else { return }
    logger.debug("✓ MEM  \(owner, privacy: .public) · \(url.lastPathComponent, privacy: .public)")
  }

  /// - Parameter from: which tier answered — `memory`, `disk` or `network`. More useful
  ///   than a byte count now that the pipeline owns both caches: a rail that re-fetches
  ///   over the network on every scroll pass is a cache-key bug, and this is where it shows.
  public static func loaded(_ url: URL, from tier: String) {
    guard isEnabled else { return }
    logger.debug("✓ LOAD \(url.lastPathComponent, privacy: .public) · \(tier, privacy: .public)")
  }

  /// Where a hero / banner picture actually came from: the URL asked for, the URL that
  /// answered after redirects (the worker's `/img` 302s to TMDB, tvoe, Kinopoisk…),
  /// and which candidate of the slot's fallback chain it was. Logged in every build —
  /// a handful of lines per screen, and the only way to tell "wrong picture" from
  /// "right route, wrong fallback" without a debugger.
  public static func source(_ slot: String, id: Int?, asked: URL, answered: URL?,
                            tier: String, candidate: Int = 0, of count: Int = 1) {
    let idText = id.map(String.init) ?? "?"
    let answeredText = answered?.absoluteString ?? "(\(tier), no redirect info)"
    logger.notice("◎ SRC  \(slot, privacy: .public) id=\(idText, privacy: .public) [\(candidate + 1)/\(count)] \(answeredText, privacy: .public) ← \(asked.absoluteString, privacy: .public) · \(tier, privacy: .public)")
  }

  /// Every candidate of a slot failed: the slot stays empty (or lettered, for a logo).
  public static func exhausted(_ slot: String, id: Int?, tried: [URL]) {
    let idText = id.map(String.init) ?? "?"
    let list = tried.map(\.absoluteString).joined(separator: " | ")
    logger.notice("◌ NONE \(slot, privacy: .public) id=\(idText, privacy: .public) tried \(list, privacy: .public)")
  }

  public static func failed(_ url: URL, reason: String) {
    guard isEnabled else { return }
    logger.error("✖ FAIL \(url.absoluteString, privacy: .public) · \(reason, privacy: .public)")
  }
}
#endif
