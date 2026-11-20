//
//  PerfSignpost.swift
//  KinoPubLogging
//
//  One subsystem for scroll / hitch / artwork intervals, so Instruments and
//  `XCTOSSignpostMetric` look in the same place. Compiled in every build;
//  `OSSignposter.isEnabled` is false unless a recording or XCTest metric is
//  attached, so a missed check is one atomic load — not a string, not a log.
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
//    scroll.season     tvOS season-rail page slide
//    page.title        title page open → first paint
//    page.resize       Mac / iPad window size settled
//

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
    hero.start("hero.page", "\(from)->\(to)")
  }

  public static func beginHeroBackdrop(id: String) -> PerfInterval {
    hero.start("hero.backdrop", id)
  }

  public static func noteHeroPage(from: Int, to: Int) {
    heroPageSession.begin("\(from)->\(to)")
  }

  public static func endHeroPage(_ reason: String = "idle") {
    heroPageSession.end(reason)
  }

  // MARK: - Scroll

  public static func beginHomeScroll(_ detail: String = "scroll") {
    homeScrollSession.begin(detail)
  }

  public static func endHomeScroll(_ detail: String = "idle") {
    homeScrollSession.end(detail)
  }

  /// Begin on the first move and end once scrolling has been still for a short
  /// settle. Used where there is no scroll-phase callback (Mac clip-view
  /// bounds, tvOS focus `setContentOffset` that may skip `didEndDecelerating`).
  public static func noteHomeScroll(_ detail: String = "scroll") {
    beginHomeScroll(detail)
    let gen = homeScrollIdleGen.withLock { value -> UInt in
      value += 1
      return value
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
      let current = homeScrollIdleGen.withLock { $0 }
      if current == gen { endHomeScroll("idle") }
    }
  }

  public static func beginSeasonScroll(_ detail: String = "slide") {
    seasonScrollSession.begin(detail)
  }

  public static func endSeasonScroll(_ detail: String = "idle") {
    seasonScrollSession.end(detail)
  }

  // MARK: - Page

  public static func beginTitleOpen(id: String) {
    titleOpen.withLock { slot in
      if slot.id == id, slot.interval != nil { return }
      slot.interval?.end("replaced")
      let interval = page.start("page.title", id)
      if slot.readyID == id, let reason = slot.readyReason {
        interval.end(reason)
        slot = TitleOpenSlot()
      } else {
        slot = TitleOpenSlot(interval: interval, id: id, readyReason: nil, readyID: nil)
      }
    }
  }

  public static func endTitleOpen(reason: String, id: String? = nil) {
    titleOpen.withLock { slot in
      if let interval = slot.interval {
        if let id, slot.id != id { return }
        interval.end(reason)
        slot = TitleOpenSlot()
      } else if let id {
        // `onChange(initial:)` can fire before `onAppear`.
        slot.readyReason = reason
        slot.readyID = id
      }
    }
  }

  public static func cancelTitleOpen(id: String) {
    titleOpen.withLock { slot in
      guard slot.id == id, let interval = slot.interval else { return }
      interval.end("disappear")
      slot = TitleOpenSlot()
    }
  }

  public static func notePageResize(_ size: CGSize) {
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
    let gen = pageResizeGen.withLock { value -> UInt in
      value += 1
      return value
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
      let current = pageResizeGen.withLock { $0 }
      if current == gen { pageResizeSession.end("settled") }
    }
  }

  // MARK: - Sessions

  private static let homeScrollSession = PerfScrollSession(scroll, name: "scroll.home")
  private static let seasonScrollSession = PerfScrollSession(scroll, name: "scroll.season")
  private static let heroPageSession = PerfScrollSession(hero, name: "hero.page")
  private static let pageResizeSession = PerfScrollSession(page, name: "page.resize")
  private static let homeScrollIdleGen = Mutex<UInt>(0)
  private static let pageResizeGen = Mutex<UInt>(0)
  private static let lastResize = Mutex<CGSize>(.zero)
  private static let titleOpen = Mutex<TitleOpenSlot>(TitleOpenSlot())
}

/// One begin/end pair. `end` is idempotent so `defer` and a callback can both fire.
public final class PerfInterval: @unchecked Sendable {
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

extension OSSignposter {
  /// `beginInterval` is already a no-op when nothing is recording. Always call it so
  /// `XCTOSSignpostMetric` in the UI test runner can see the interval in the app.
  public func start(_ name: StaticString, _ detail: String = "") -> PerfInterval {
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
  var readyReason: String?
  var readyID: String?
}
