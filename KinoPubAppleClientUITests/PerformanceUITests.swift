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
//  Metrics: `XCTOSSignpostMetric` on our intervals (the hitch stand-in on
//  tvOS, where Apple's scrolling hitch metrics do not apply) and
//  `XCTMemoryMetric(application:)`. Empty signpost metrics fail the test
//  (XCTest otherwise drops them and stays green). No `XCTClockMetric` — the
//  walks wait for the remote / animation, and a clock metric would measure
//  those waits.
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

  private func signpost(_ category: String, _ name: String) -> XCTMetric {
    RequiredOSSignpostMetric(subsystem: "com.soda.kinopub.perf", category: category, name: name)
  }

  /// tvOS has no `scrollingAndDecelerationMetric`. Interval duration of our
  /// `scroll.*` / `hero.page` / `artwork.request` signposts is the hitch
  /// stand-in XCTest can record; hitch ratio still comes from Instruments.
  private func hitchMetrics(_ extra: XCTMetric...) -> [XCTMetric] {
    [XCTMemoryMetric(application: app)] + extra
  }

  /// Wait for one remote-driven scroll to settle so `scroll.*` closes between
  /// presses instead of spanning the whole walk.
  private func waitForScrollSettle() {
    Thread.sleep(forTimeInterval: 0.8)
  }

  // MARK: - tvOS

#if os(tvOS)
  func testHomeShelfScroll() {
    launchTemplates()
    XCTAssertTrue(app.collectionViews["kinopub.page.templates"].waitForExistence(timeout: 20),
                  "templates gallery did not appear")
    Thread.sleep(forTimeInterval: 1.0)

    measure(metrics: hitchMetrics(
      signpost("scroll", "scroll.home"),
      signpost("artwork", "artwork.request")
    ), options: measureOptions) {
      for _ in 0..<5 {
        XCUIRemote.shared.press(.down)
        waitForScrollSettle()
      }
      for _ in 0..<5 {
        XCUIRemote.shared.press(.up)
        waitForScrollSettle()
      }
    }
  }

  func testHeroCarouselPaging() throws {
    launchTemplates(hero: true)
    XCTAssertTrue(waitForHeroFocus(timeout: 20), "hero did not take focus")
    focusHeroNext()
    XCTAssertTrue(
      app.descendants(matching: .any)
        .matching(NSPredicate(format: "identifier == %@ AND hasFocus == true", "kinopub.hero.next"))
        .firstMatch.exists,
      "Next did not take focus — Select would open a title instead of paging"
    )

    measure(metrics: hitchMetrics(
      signpost("hero", "hero.page")
    ), options: measureOptions) {
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

    measure(metrics: hitchMetrics(
      signpost("page", "page.title"),
      signpost("hero", "hero.backdrop")
    ), options: measureOptions) {
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

  /// Cold open of the Search tab from Watch Now. `page.search` is takePrepared →
  /// field/keyboard first appear. One iteration: the stack is taken once per process.
  func testSearchTabFirstPaint() {
    app = XCUIApplication()
    app.launchArguments += ["-ui-testing", "-KINOPUBSearchFixture",
                            "-KINOPUBSearchFixtureStartOnWatchNow",
                            "-KINOPUBForceColorScheme", "dark",
                            "-ForceGridKeyboard", "YES",
                            "-UserPreferredKeyboardStyle", "2"]
    app.launch()
    XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 20), "tab bar did not appear")
    Thread.sleep(forTimeInterval: 0.6)

    let options = XCTMeasureOptions()
    options.iterationCount = 1
    // Clock is the tab-switch wait, which is the interval we want. Memory as usual.
    measure(metrics: [
      XCTClockMetric(),
      XCTMemoryMetric(application: app),
      signpost("page", "page.search")
    ], options: options) {
      XCUIRemote.shared.press(.left)
      XCTAssertTrue(
        app.collectionViews["kinopub.page.search"].waitForExistence(timeout: 5)
          || app.searchFields.firstMatch.waitForExistence(timeout: 2)
          || app.keyboards.firstMatch.waitForExistence(timeout: 2),
        "Search chrome did not appear"
      )
    }
  }

  func testSeasonRailScroll() throws {
    // `<true/>` is the UserDefaults plist boolean. `"YES"` stores a string and
    // `FeatureFlag.storedValue` (`as? Bool`) falls back to the default, which is off.
    launchDetail("seasonStrip", extra: ["-featureFlag.rivuletSeasonRail", "<true/>"])
    XCTAssertTrue(waitForHeroFocus(timeout: 20), "title hero did not take focus")

    measure(metrics: hitchMetrics(
      signpost("scroll", "scroll.season")
    ), options: measureOptions) {
      // Down is the CADisplayLink fold (`scroll.season`, 0.6 s). Right is the
      // episode rail. Up returns to the hero so the next iteration is the same
      // walk; Menu would pop the page.
      XCUIRemote.shared.press(.down)
      Thread.sleep(forTimeInterval: 0.9)
      let onRail = app.descendants(matching: .any).matching(NSPredicate(
        format: "(identifier BEGINSWITH %@ OR identifier BEGINSWITH %@) AND hasFocus == true",
        "kinopub.rivulet.still.", "kinopub.rail.item.")).firstMatch
      XCTAssertTrue(onRail.waitForExistence(timeout: 5),
                    "Down from the hero did not land on the season rail")
      for _ in 0..<4 {
        XCUIRemote.shared.press(.right)
        waitForScrollSettle()
      }
      XCUIRemote.shared.press(.up)
      Thread.sleep(forTimeInterval: 0.9)
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
    var metrics = hitchMetrics(
      signpost("scroll", "scroll.home"),
      signpost("artwork", "artwork.request")
    )
    metrics.append(XCTOSSignpostMetric.scrollingAndDecelerationMetric)

    measure(metrics: metrics, options: measureOptions) {
      scroll.swipeUp(velocity: .fast)
      waitForScrollSettle()
      scroll.swipeDown(velocity: .fast)
      waitForScrollSettle()
    }
  }

  func testHeroCarouselPaging() throws {
    launchWithSessionIfAny()
    _ = try requireHomeScroll()
    let (pager, y) = try requireHomeHeroPager()

    measure(metrics: hitchMetrics(
      signpost("hero", "hero.page"),
      signpost("artwork", "artwork.request")
    ), options: measureOptions) {
      // Horizontal drag on the hero band — not a left-swipe of the vertical
      // Home scroll (that hits a shelf at mid-screen).
      let start = pager.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: y))
      let end = pager.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: y))
      start.press(forDuration: 0.05, thenDragTo: end)
      Thread.sleep(forTimeInterval: 0.7)
      start.press(forDuration: 0.05, thenDragTo: end)
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

    measure(metrics: hitchMetrics(
      signpost("page", "page.title"),
      signpost("artwork", "artwork.request")
    ), options: measureOptions) {
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

  /// Prefer the `kinopub.hero` container; if XCTest does not expose it, swipe
  /// the top band of Home (the pager), not the mid-page shelf.
  private func requireHomeHeroPager() throws -> (XCUIElement, CGFloat) {
    let hero = app.descendants(matching: .any)["kinopub.hero"]
    if hero.waitForExistence(timeout: 8) {
      return (hero, 0.4)
    }
    let scroll = try requireHomeScroll()
    return (scroll, 0.12)
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

    measure(metrics: hitchMetrics(
      signpost("page", "page.resize")
    ), options: measureOptions) {
      start.click(forDuration: 0.05, thenDragTo: squeezed)
      Thread.sleep(forTimeInterval: 0.5)
      squeezed.click(forDuration: 0.05, thenDragTo: start)
      Thread.sleep(forTimeInterval: 0.5)
    }
  }

  func testHomeShelfScroll() throws {
    launchWithSessionIfAny()
    let scroll = try requireHomeScroll()
    measure(metrics: hitchMetrics(
      signpost("scroll", "scroll.home"),
      signpost("artwork", "artwork.request")
    ), options: measureOptions) {
      scroll.scroll(byDeltaX: 0, deltaY: -400)
      waitForScrollSettle()
      scroll.scroll(byDeltaX: 0, deltaY: 400)
      waitForScrollSettle()
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

/// XCTest silently drops an `XCTOSSignpostMetric` with zero intervals, so the
/// test stays green. Subclass (do not wrap) so XCTest still enables app-side
/// signpost collection for this metric class. Fail when there are no samples.
private final class RequiredOSSignpostMetric: XCTOSSignpostMetric {
  private let subsystemName: String
  private let categoryName: String
  private let intervalName: String

  override init(subsystem: String, category: String, name: String) {
    self.subsystemName = subsystem
    self.categoryName = category
    self.intervalName = name
    super.init(subsystem: subsystem, category: category, name: name)
  }

  override func copy(with zone: NSZone? = nil) -> Any {
    RequiredOSSignpostMetric(
      subsystem: subsystemName,
      category: categoryName,
      name: intervalName
    )
  }

  override func reportMeasurements(
    from startTime: XCTPerformanceMeasurementTimestamp,
    to endTime: XCTPerformanceMeasurementTimestamp
  ) throws -> [XCTPerformanceMeasurement] {
    let measurements = try super.reportMeasurements(from: startTime, to: endTime)
    if measurements.isEmpty {
      XCTFail("signpost \(categoryName)/\(intervalName) produced no samples; XCTest would drop an empty metric")
    }
    return measurements
  }
}
