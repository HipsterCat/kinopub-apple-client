//
//  TitleLogoPresentation.swift
//  KinoPubUI
//
//  When a title logo and the lettered name share one slot: what to show while the
//  lookup is in flight, and which completion is allowed to paint. Plozz's
//  `HeroLogoPresentationPolicy` (33c1219) is the prior art — empty while resolving,
//  text only on a confirmed miss, a request token so a stale load cannot overwrite
//  a newer card.
//

import Foundation

/// What occupies the title-logo slot.
public enum TitleLogoMark: Equatable, Sendable {
  /// Layout is reserved; nothing is drawn. Used while a logo is expected.
  case empty
  /// The artwork is on screen.
  case logo
  /// Confirmed miss — 404, no logo in metadata, or the miss timeout.
  case text
}

/// Result of looking up a title logo URL, distinct from loading the image.
public enum TitleLogoResolution: Hashable, Sendable {
  /// Metadata has not answered yet.
  case pending
  /// A logo URL exists (the image may still be loading).
  case url(URL)
  /// Confirmed: this title has no logo.
  case missing

  public var url: URL? {
    if case .url(let url) = self { return url }
    return nil
  }
}

/// Controls when a logo or its text fallback becomes visible.
public enum TitleLogoPresentationPolicy: Equatable, Sendable {
  /// Show the lettered title until a logo paints, then swap. The flicker this
  /// policy exists to retire.
  case whenReady
  /// Keep the slot empty while a lookup or image load is in flight. Text only
  /// after a confirmed miss (no URL, 404, or ``missTimeout``).
  case whenResolved

  /// How long to wait for a logo before treating the lookup as a miss.
  ///
  /// Tuned as 1.5 s: long enough for a warm cache / worker hit, short enough that
  /// a title without a logo is not a blank slot. A later success still warms the
  /// shared cache, but does not replace text already shown for this request.
  public static let missTimeout: TimeInterval = 1.5

  /// Whether a resolved logo should replace whatever is on screen.
  public func shouldAdoptLogo(elapsed: TimeInterval, alreadyShowingText: Bool) -> Bool {
    if alreadyShowingText, elapsed > Self.missTimeout { return false }
    return true
  }

  /// Whether this completion belongs to the card currently on screen.
  public func shouldApply(requestID: Int, current: Int) -> Bool {
    requestID == current
  }

  public var showsTextWhileLoading: Bool { self == .whenReady }

  /// What the slot should draw right now.
  public func mark(
    hasCachedLogo: Bool,
    lookupComplete: Bool,
    hasLogoURL: Bool,
    imageReady: Bool,
    imageFailed: Bool,
    elapsed: TimeInterval
  ) -> TitleLogoMark {
    if hasCachedLogo || imageReady { return .logo }
    if imageFailed { return .text }
    if lookupComplete && !hasLogoURL { return .text }
    if elapsed >= Self.missTimeout { return .text }
    return showsTextWhileLoading ? .text : .empty
  }
}
