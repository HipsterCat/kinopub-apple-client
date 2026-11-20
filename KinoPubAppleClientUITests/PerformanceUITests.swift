//
//  PerformanceUITests.swift
//  KinoPubAppleClientUITests
//
//  Apple-style UI performance tests for scroll, hero paging, title open and
//  (on Mac) window resize. Signpost names match `PerfSignpost.Interval`.
//
//  tvOS walks the DEBUG fixtures (no kino.pub session). iOS / Mac Home needs
//  `~/.kinopub-dev-session.json` and skips in CI when it is missing.
//
//  These tests record metrics. They do not fail on hitch-time noise — there is
//  no stored baseline. Numbers land in the xcresult and in
//  `docs/engineering/performance.md`.
//

import XCTest

final class PerformanceUITests: XCTestCase {
  private var app: XCUIApplication!

  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  private var measureOptions: XCTMeasureOptions {
    let options = XCTMeasureOptions()
    options.iterationCount = 3
    return options
  }

  private func signpost(_ category: String, _ name: String) -> XCTOSSignpostMetric {
    XCTOSSignpostMetric(subsystem: "com.soda.kinopub.perf", category: category, name: name)
  }

  // MARK: - tvOS

#if os(tvOS)
  func testHomeShelfScroll() {
    launchTemplates()
    XCTAssertTrue(app.collectionViews["kinopub.page.templates"].waitForExistence(timeout: 20),
                  "templates gallery did not appear")
    Thread.sleep(forTimeInterval: 1.0)

    measure(metrics: [
      XCTClockMetric(),
      XCTMemoryMetric(),
      signpost("scroll", "scroll.home")
    ], options: measureOptions) {
      for _ in 0..<5 {
        XCUIRemote.shared.press(.down)
        Thread.sleep(forTimeInterval: 0.45)
      }
      for _ in 0..<5 {
        XCUIRemote.shared.press(.up)
        Thread.sleep(forTimeInterval: 0.45)
      }
      Thread.sleep(forTimeInterval: 0.8)
    }
  }

  func testHeroCarouselPaging() throws {
    launchTemplates(hero: true)
    XCTAssertTrue(waitForHeroFocus(timeout: 20), "hero did not take focus")
    focusHeroNext()

    measure(metrics: [
      XCTClockMetric(),
      XCTMemoryMetric(),
      signpost("hero", "hero.page")
    ], options: measureOptions) {
      for _ in 0..<4 {
        XCUIRemote.shared.press(.select)
        Thread.sleep(forTimeInterval: 0.9)
      }
      Thread.sleep(forTimeInterval: 0.5)
    }
  }

  func testTitlePageOpen() {
    launchDetail("list")
    let first = app.buttons["kinopub.fixture.awaiting"]
    XCTAssertTrue(first.waitForExistence(timeout: 20), "fixture list did not appear")
    Thread.sleep(forTimeInterval: 0.8)

    measure(metrics: [
      XCTClockMetric(),
      XCTMemoryMetric(),
      signpost("page", "page.title"),
      signpost("hero", "hero.backdrop")
    ], options: measureOptions) {
      XCUIRemote.shared.press(.select)
      XCTAssertTrue(
        app.buttons["kinopub.hero.play"].waitForExistence(timeout: 15)
          || app.buttons["kinopub.hero.follow"].waitForExistence(timeout: 2),
        "title page did not open"
      )
      Thread.sleep(forTimeInterval: 0.6)
      XCUIRemote.shared.press(.menu)
      XCTAssertTrue(first.waitForExistence(timeout: 10), "Menu did not return to the list")
      Thread.sleep(forTimeInterval: 0.4)
    }
  }

  func testSeasonRailScroll() throws {
    launchDetail("seasonStrip", extra: ["-featureFlag.rivuletSeasonRail", "YES"])
    XCTAssertTrue(waitForHeroFocus(timeout: 20), "title hero did not take focus")

    measure(metrics: [
      XCTClockMetric(),
      XCTMemoryMetric(),
      signpost("scroll", "scroll.season")
    ], options: measureOptions) {
      XCUIRemote.shared.press(.down)
      Thread.sleep(forTimeInterval: 1.2)
      for _ in 0..<4 {
        XCUIRemote.shared.press(.right)
        Thread.sleep(forTimeInterval: 0.45)
      }
      XCUIRemote.shared.press(.menu)
      Thread.sleep(forTimeInterval: 1.0)
    }
  }

  private func launchTemplates(hero: Bool = false) {
    app = XCUIApplication()
    app.launchArguments += ["-ui-testing", "-KINOPUBTemplatesGallery",
                            "-KINOPUBForceColorScheme", "dark"]
    if hero { app.launchArguments.append("-KINOPUBTemplatesHero") }
    app.launch()
  }

  private func launchDetail(_ fixture: String, extra: [String] = []) {
    app = XCUIApplication()
    app.launchArguments += extra
    app.launchArguments += ["-ui-testing",
                            "-KINOPUBDetailFixture", fixture,
                            "-KINOPUBForceColorScheme", "dark",
                            "-AppleLanguages", "(ru)"]
    app.launch()
  }

  private func waitForHeroFocus(timeout: TimeInterval) -> Bool {
    app.descendants(matching: .any)
      .matching(NSPredicate(format: "identifier BEGINSWITH %@ AND hasFocus == true", "kinopub.hero."))
      .firstMatch
      .waitForExistence(timeout: timeout)
  }

  private func focusHeroNext() {
    var focused = app.descendants(matching: .any)
      .matching(NSPredicate(format: "identifier == %@ AND hasFocus == true", "kinopub.hero.next"))
      .firstMatch
    var steps = 0
    while !focused.exists, steps < 5 {
      XCUIRemote.shared.press(.right)
      Thread.sleep(forTimeInterval: 0.4)
      focused = app.descendants(matching: .any)
        .matching(NSPredicate(format: "identifier == %@ AND hasFocus == true", "kinopub.hero.next"))
        .firstMatch
      steps += 1
    }
  }
#endif

  // MARK: - iOS

#if os(iOS)
  func testHomeShelfScroll() throws {
    launchWithSessionIfAny()
    let scroll = try requireHomeScroll()
    var metrics: [XCTMetric] = [
      XCTClockMetric(),
      XCTMemoryMetric(),
      signpost("scroll", "scroll.home")
    ]
    metrics.append(XCTOSSignpostMetric.scrollingAndDecelerationMetric)

    measure(metrics: metrics, options: measureOptions) {
      scroll.swipeUp(velocity: .fast)
      Thread.sleep(forTimeInterval: 0.6)
      scroll.swipeDown(velocity: .fast)
      Thread.sleep(forTimeInterval: 0.6)
    }
  }

  func testHeroCarouselPaging() throws {
    launchWithSessionIfAny()
    let scroll = try requireHomeScroll()
    // The hero is a horizontal pager at the top of Home.
    measure(metrics: [
      XCTClockMetric(),
      XCTMemoryMetric(),
      signpost("hero", "hero.page")
    ], options: measureOptions) {
      scroll.swipeLeft(velocity: .fast)
      Thread.sleep(forTimeInterval: 0.7)
      scroll.swipeLeft(velocity: .fast)
      Thread.sleep(forTimeInterval: 0.7)
    }
  }

  func testTitlePageOpen() throws {
    launchWithSessionIfAny()
    let card = app.scrollViews.buttons
      .matching(NSPredicate(format: "label CONTAINS ', '"))
      .firstMatch
    guard card.waitForExistence(timeout: 30) else {
      throw XCTSkip("no Home cards — no kino.pub session on this simulator")
    }

    measure(metrics: [
      XCTClockMetric(),
      XCTMemoryMetric(),
      signpost("page", "page.title")
    ], options: measureOptions) {
      card.tap()
      let play = app.buttons
        .matching(NSPredicate(format: "identifier == 'kinopub.hero.play' OR label BEGINSWITH 'Play' OR label BEGINSWITH 'Смотреть'"))
        .firstMatch
      XCTAssertTrue(play.waitForExistence(timeout: 15), "title page did not open")
      Thread.sleep(forTimeInterval: 0.4)
      app.navigationBars.buttons.firstMatch.tap()
      Thread.sleep(forTimeInterval: 0.5)
    }
  }
#endif

  // MARK: - Mac

#if os(macOS)
  func testHomeWindowResize() throws {
    launchWithSessionIfAny()
    let window = app.windows.firstMatch
    guard window.waitForExistence(timeout: 30) else {
      throw XCTSkip("no window")
    }
    try requireHomeScroll()

    let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.98))
    let squeezed = start.withOffset(CGVector(dx: -220, dy: -160))

    measure(metrics: [
      XCTClockMetric(),
      XCTMemoryMetric(),
      signpost("page", "page.resize")
    ], options: measureOptions) {
      start.click(forDuration: 0.05, thenDragTo: squeezed)
      Thread.sleep(forTimeInterval: 0.5)
      squeezed.click(forDuration: 0.05, thenDragTo: start)
      Thread.sleep(forTimeInterval: 0.5)
    }
  }

  func testHomeShelfScroll() throws {
    launchWithSessionIfAny()
    let scroll = try requireHomeScroll()
    measure(metrics: [
      XCTClockMetric(),
      XCTMemoryMetric(),
      signpost("scroll", "scroll.home")
    ], options: measureOptions) {
      scroll.scroll(byDeltaX: 0, deltaY: -400)
      Thread.sleep(forTimeInterval: 0.4)
      scroll.scroll(byDeltaX: 0, deltaY: 400)
      Thread.sleep(forTimeInterval: 0.4)
    }
  }
#endif

  // MARK: - Shared (iOS / Mac)

#if os(iOS) || os(macOS)
  private func launchWithSessionIfAny() {
    app = XCUIApplication()
    app.launchArguments += ["-ui-testing"]
    if let session = UITestDevSession.json {
      app.launchEnvironment["KINOPUB_DEV_SESSION"] = session
    }
    app.launch()
  }

  private func requireHomeScroll() throws -> XCUIElement {
    guard UITestDevSession.json != nil else {
      throw XCTSkip("no kino.pub session on this simulator")
    }
    let scroll = app.scrollViews.firstMatch
    _ = scroll.waitForExistence(timeout: 30)
    let card = app.scrollViews.buttons
      .matching(NSPredicate(format: "label CONTAINS ', '"))
      .firstMatch
    if !card.waitForExistence(timeout: 8) {
      throw XCTSkip("no Home content — no kino.pub session on this simulator")
    }
    return scroll
  }
#endif
}
