//
//  PerfSignpost.swift
//  KinoPubLogging
//
//  One subsystem for scroll / hitch / artwork intervals, so Instruments and
//  `XCTOSSignpostMetric` look in the same place. Compiled in every build.
//  Hot paths (`noteHomeScroll`, `notePageResize`, artwork begin) return before
//  any lock, string or `asyncAfter` unless `OSSignposter.isEnabled` — false
//  unless a recording or XCTest metric is attached.
//
//  Subsystem: `com.soda.kinopub.perf`
//  Categories: `artwork`, `hero`, `scroll`, `page`
//
//  Interval names (match these in XCTest and the playbook):
//    artwork.request   request → decoded image (tier + pixel size + bytes on end)
//    artwork.display   the bitmap was assigned to a view
//    hero.page         Home hero turned to another title
//    hero.backdrop     page-backdrop crossfade (tvOS title page)
//    scroll.home       Home / templates vertical shelf scroll
//    scroll.season     tvOS season-rail fold + horizontal rail, one interval per gesture
//    page.title        navigation push → first painted item
//    page.resize       Mac / iPad window size settled
//

import CoreGraphics
import Foundation
import OSLog
import Synchronization

/// Lightweight Instruments / XCTest signposts around scrolling and artwork.
public enum PerfSignpost {
  public static let subsystem = "com.soda.kinopub.perf"

  public static let artwork = OSSignposter(subsystem: subsystem, category: "artwork")
  public static let hero = OSSignposter(subsystem: subsystem, category: "hero")
  public static let scroll = OSSignposter(subsystem: subsystem, category: "scroll")
  public static let page = OSSignposter(subsystem: subsystem, category: "page")

  /// String names for `XCTOSSignpostMetric(subsystem:category:name:)`.
  public enum Interval {
    public static let artworkRequest = "artwork.request"
    public static let artworkDisplay = "artwork.display"
    public static let heroPage = "hero.page"
    public static let heroBackdrop = "hero.backdrop"
    public static let scrollHome = "scroll.home"
    public static let scrollSeason = "scroll.season"
    public static let pageTitle = "page.title"
    public static let pageResize = "page.resize"
  }

  // MARK: - Artwork

  public static func beginArtworkRequest(url: URL, pixelSize: CGSize) -> PerfInterval {
    guard artwork.isEnabled else { return .disabled }
    let size = pixelSize == .zero ? "full" : "\(Int(pixelSize.width))x\(Int(pixelSize.height))"
    return artwork.start("artwork.request", "\(url.lastPathComponent) \(size)")
  }

  public static func emitArtworkDisplay(url: URL, bytes: Int, pixelSize: CGSize) {
    guard artwork.isEnabled else { return }
    let size = pixelSize == .zero ? "full" : "\(Int(pixelSize.width))x\(Int(pixelSize.height))"
    artwork.emit("artwork.display", "\(url.lastPathComponent) \(size) \(bytes)B")
  }

  // MARK: - Hero

  public static func beginHeroPage(from: Int, to: Int) -> PerfInterval {
    guard hero.isEnabled else { return .disabled }
    return hero.start("hero.page", "\(from)->\(to)")
  }

  public static func beginHeroBackdrop(id: String) -> PerfInterval {
    guard hero.isEnabled else { return .disabled }
    return hero.start("hero.backdrop", id)
  }

  public static func noteHeroPage(from: Int, to: Int) {
    guard hero.isEnabled else { return }
    heroPageSession.begin("\(from)->\(to)")
  }

  public static func endHeroPage(_ reason: String = "idle") {
    guard hero.isEnabled else { return }
    heroPageSession.end(reason)
  }

  // MARK: - Scroll

  public static func beginHomeScroll(_ detail: String = "scroll") {
    guard scroll.isEnabled else { return }
    homeScrollIdle.cancel()
    homeScrollSession.begin(detail)
  }

  public static func endHomeScroll(_ detail: String = "idle") {
    guard scroll.isEnabled else { return }
    homeScrollIdle.cancel()
    homeScrollSession.end(detail)
  }

  /// Begin on the first move and end once scrolling has been still for a short
  /// settle. Used where there is no scroll-phase callback (Mac clip-view
  /// bounds, tvOS focus `setContentOffset` that may skip `didEndDecelerating`).
  ///
  /// Settle is ~80 ms after the last `didScroll` — long enough for deceleration
  /// frames, short enough that a 0.45 s remote cadence is not one giant interval.
  /// Prefer `endHomeScroll` from `didEndDecelerating` / `didEndScrollingAnimation`
  /// when those fire.
  ///
  /// A no-op unless a recording is attached — `scrollViewDidScroll` is every frame.
  public static func noteHomeScroll(_ detail: String = "scroll") {
    guard scroll.isEnabled else { return }
    homeScrollSession.begin(detail)
    homeScrollIdle.reschedule()
  }

  public static func beginSeasonScroll(_ detail: String = "slide") {
    guard scroll.isEnabled else { return }
    seasonScrollIdle.cancel()
    seasonScrollSession.begin(detail)
  }

  public static func endSeasonScroll(_ detail: String = "idle") {
    guard scroll.isEnabled else { return }
    seasonScrollIdle.cancel()
    seasonScrollSession.end(detail)
  }

  /// Horizontal rail / tab scroll. Same settle as `noteHomeScroll`. The Rivulet
  /// CADisplayLink fold uses `beginSeasonScroll` / `endSeasonScroll` instead.
  public static func noteSeasonScroll(_ detail: String = "rail") {
    guard scroll.isEnabled else { return }
    seasonScrollSession.begin(detail)
    seasonScrollIdle.reschedule()
  }

  // MARK: - Page

  public static func beginTitleOpen(id: String) {
    guard page.isEnabled else { return }
    titleOpen.withLock { slot in
      if slot.id == id, slot.interval != nil { return }
      slot.interval?.end("replaced")
      slot = TitleOpenSlot(interval: page.start("page.title", id), id: id)
    }
  }

  /// Ends the open interval, or no-ops. Does not stash a leftover `readyID` —
  /// a re-appear `end` would otherwise swallow the next push of the same title.
  public static func endTitleOpen(reason: String, id: String? = nil) {
    guard page.isEnabled else { return }
    titleOpen.withLock { slot in
      guard let interval = slot.interval else { return }
      if let id, slot.id != id { return }
      interval.end(reason)
      slot = TitleOpenSlot()
    }
  }

  public static func cancelTitleOpen(id: String) {
    titleOpen.withLock { slot in
      if slot.id == id {
        slot.interval?.end("disappear")
        slot = TitleOpenSlot()
      }
    }
  }

  public static func notePageResize(_ size: CGSize) {
    guard page.isEnabled else { return }
    let bucket = CGSize(
      width: (size.width / 64).rounded() * 64,
      height: (size.height / 64).rounded() * 64
    )
    let changed = lastResize.withLock { last -> Bool in
      guard last != bucket else { return false }
      last = bucket
      return true
    }
    guard changed else { return }
    pageResizeSession.begin("\(Int(size.width))x\(Int(size.height))")
    pageResizeIdle.reschedule()
  }

  // MARK: - Sessions

  private static let homeScrollSession = PerfScrollSession(scroll, name: "scroll.home")
  private static let seasonScrollSession = PerfScrollSession(scroll, name: "scroll.season")
  private static let heroPageSession = PerfScrollSession(hero, name: "hero.page")
  private static let pageResizeSession = PerfScrollSession(page, name: "page.resize")
  /// After the last scroll frame. Shorter than a remote press gap (~0.45 s) so
  /// each gesture is its own interval; longer than one display frame so
  /// deceleration still counts as the same gesture.
  private static let homeScrollIdle = IdleEnd(session: homeScrollSession, delay: 0.08)
  private static let seasonScrollIdle = IdleEnd(session: seasonScrollSession, delay: 0.08)
  private static let pageResizeIdle = IdleEnd(session: pageResizeSession, delay: 0.3)
  private static let lastResize = Mutex<CGSize>(.zero)
  private static let titleOpen = Mutex<TitleOpenSlot>(TitleOpenSlot())
}

/// One begin/end pair. `end` is idempotent so `defer` and a callback can both fire.
public final class PerfInterval: @unchecked Sendable {
  /// Shared no-op when nothing is recording. `end` is a lock + nil check.
  public static let disabled = PerfInterval(poster: PerfSignpost.artwork, name: "disabled", state: nil)

  private let poster: OSSignposter
  private let name: StaticString
  private var state: OSSignpostIntervalState?
  private let lock = NSLock()

  fileprivate init(poster: OSSignposter, name: StaticString, state: OSSignpostIntervalState?) {
    self.poster = poster
    self.name = name
    self.state = state
  }

  public func end(_ detail: String = "") {
    lock.lock()
    defer { lock.unlock() }
    guard let state else { return }
    self.state = nil
    if detail.isEmpty {
      poster.endInterval(name, state)
    } else {
      poster.endInterval(name, state, "\(detail, privacy: .public)")
    }
  }

  public func endArtwork(tier: String, bytes: Int, pixelSize: CGSize) {
    let size = pixelSize == .zero ? "full" : "\(Int(pixelSize.width))x\(Int(pixelSize.height))"
    end("\(tier) \(size) \(bytes)B")
  }
}

/// One open interval at a time for a continuous gesture (scroll, hero page).
public final class PerfScrollSession: @unchecked Sendable {
  private let poster: OSSignposter
  private let name: StaticString
  private let lock = NSLock()
  private var interval: PerfInterval?

  public init(_ poster: OSSignposter, name: StaticString) {
    self.poster = poster
    self.name = name
  }

  public func begin(_ detail: String = "") {
    guard poster.isEnabled else { return }
    lock.lock()
    defer { lock.unlock() }
    guard interval == nil else { return }
    interval = poster.start(name, detail)
  }

  public func end(_ detail: String = "") {
    lock.lock()
    defer { lock.unlock() }
    interval?.end(detail)
    interval = nil
  }
}

/// One cancelled-and-replaced `DispatchWorkItem` instead of a block per frame.
private final class IdleEnd: @unchecked Sendable {
  private let session: PerfScrollSession
  private let delay: TimeInterval
  private let lock = NSLock()
  private var work: DispatchWorkItem?

  init(session: PerfScrollSession, delay: TimeInterval) {
    self.session = session
    self.delay = delay
  }

  func reschedule() {
    lock.lock()
    work?.cancel()
    let item = DispatchWorkItem { [session] in session.end("idle") }
    work = item
    lock.unlock()
    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
  }

  func cancel() {
    lock.lock()
    work?.cancel()
    work = nil
    lock.unlock()
  }
}

extension OSSignposter {
  /// Skip `beginInterval` and the detail string when nothing is recording.
  /// `XCTOSSignpostMetric` sets `isEnabled`, so UI tests still see the interval.
  public func start(_ name: StaticString, _ detail: String = "") -> PerfInterval {
    guard isEnabled else { return .disabled }
    let id = makeSignpostID()
    let state: OSSignpostIntervalState
    if detail.isEmpty {
      state = beginInterval(name, id: id)
    } else {
      state = beginInterval(name, id: id, "\(detail, privacy: .public)")
    }
    return PerfInterval(poster: self, name: name, state: state)
  }

  public func emit(_ name: StaticString, _ detail: String = "") {
    guard isEnabled else { return }
    if detail.isEmpty {
      emitEvent(name, id: makeSignpostID())
    } else {
      emitEvent(name, id: makeSignpostID(), "\(detail, privacy: .public)")
    }
  }
}

private struct TitleOpenSlot: Sendable {
  var interval: PerfInterval?
  var id: String?
}
