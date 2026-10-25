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

  /// Hero / SwiftUI call sites still know a URL and a loaded flag; one resolution
  /// is what the slot consumes.
  public init(url: URL?, lookupComplete: Bool) {
    if let url {
      self = .url(url)
    } else {
      self = lookupComplete ? .missing : .pending
    }
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

  /// Cold worker resolve waits up to `IMAGE_WAIT_MS` on the TMDB proxy (default **5 s**)
  /// before 404; the slot stays empty until then, plus a short grace for redirect and decode.
  public static let workerImageResolveWait: TimeInterval = 5
  public static let postResolveGrace: TimeInterval = 1.5
  public static var missTimeout: TimeInterval { workerImageResolveWait + postResolveGrace }

  /// Whether a resolved logo should replace whatever is on screen.
  public func shouldAdoptLogo(elapsed: TimeInterval, alreadyShowingText: Bool) -> Bool {
    switch self {
    case .whenResolved:
      // A successful decode always wins over a timed-out lettered guess — the worker
      // can still be filling KV inside its five-second window.
      return true
    case .whenReady:
      if alreadyShowingText, elapsed > Self.missTimeout { return false }
      return true
    }
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
    // Timeout is an image-load miss. A pending lookup stays empty so a late URL
    // cannot replace already-shown text.
    if hasLogoURL && elapsed >= Self.missTimeout { return .text }
    return showsTextWhileLoading ? .text : .empty
  }
}
