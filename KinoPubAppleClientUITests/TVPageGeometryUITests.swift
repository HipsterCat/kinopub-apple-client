#if os(tvOS)
//
//  TVPageGeometryUITests.swift
//  KinoPubAppleClientUITests
//
//  The complaint behind `TVPage`: switching to Movies / Series painted the posters
//  once at a guessed size and again at the real one, so the row visibly grew. This
//  test switches tabs with the remote, reads the first poster's frame the moment it
//  exists and again after the page has settled, and requires the two to agree — and
//  to be the HIG 6-column width (260 at 1920). Local-only: needs the dev session.
//
//  Screenshots land in /tmp/kinopub-page-shots/.
//

import XCTest

final class TVPageGeometryUITests: XCTestCase {

  override func setUpWithError() throws {
    continueAfterFailure = false
    guard FileManager.default.fileExists(atPath: UITestDevSession.filePath) else {
      throw XCTSkip("no ~/.kinopub-dev-session.json — local page geometry only")
    }
  }

  func testMoviesTabPaintsPostersAtFinalSizeOnFirstFrame() throws {
    let app = XCUIApplication()
    app.launchArguments += ["-ui-testing", "-KINOPUBForceColorScheme", "dark"]
    if let session = UITestDevSession.json {
      app.launchEnvironment["KINOPUB_DEV_SESSION"] = session
    }
    app.launch()
    XCTAssertEqual(app.state, .runningForeground)

    // Watch Now first, so the Movies switch is a real tab switch with a warm app.
    XCTAssertTrue(app.collectionViews["kinopub.page.home"].waitForExistence(timeout: 90),
                  "Watch Now page never appeared")
    XCTAssertTrue(firstPoster(in: app, page: "home").waitForExistence(timeout: 60),
                  "Watch Now never showed a poster")

    // Focus starts on the Watch Now pill; Right lands on Movies and selects it.
    XCUIRemote.shared.press(.right)

    let moviesPage = app.collectionViews["kinopub.page.movies"]
    XCTAssertTrue(moviesPage.waitForExistence(timeout: 30), "Movies page never appeared")
    let poster = firstPoster(in: app, page: "movies")
    XCTAssertTrue(poster.waitForExistence(timeout: 60), "Movies never showed a poster")

    let first = poster.frame
    try shoot(app, name: "movies-first-frame")
    Thread.sleep(forTimeInterval: 2.5)
    let settled = poster.frame
    try shoot(app, name: "movies-settled")

    XCTAssertEqual(first.width, settled.width, accuracy: 1,
                   "poster width changed after first paint: \(first) → \(settled)")
    XCTAssertEqual(first.origin.x, settled.origin.x, accuracy: 1,
                   "poster x moved after first paint: \(first) → \(settled)")
    // The cell is the lockup's focus envelope (unfocused art inset by its own
    // `focusSizeIncrease`), so its edges are not the art's — but its centre is. HIG
    // 6-column at 1920 with the 44 pt gutter: art (1760 − 5·44)/6 = 256 wide from 80.
    XCTAssertEqual(settled.midX, 80 + 256 / 2, accuracy: 2,
                   "first poster is not centred on the HIG 6-column slot: \(settled)")
    XCTAssertGreaterThanOrEqual(settled.width, 256, "envelope narrower than the HIG art width")
    XCTAssertLessThanOrEqual(settled.width, 260 * 1.15, "envelope far wider than the art plus focus growth")
  }

  /// Select on a poster pushes the detail page; Menu pops it. Focus has to come back to
  /// the poster it left from — not to the tab bar, where the next Menu quits the app.
  func testFocusReturnsToThePosterAfterDetail() throws {
    let app = XCUIApplication()
    app.launchArguments += ["-ui-testing", "-KINOPUBForceColorScheme", "dark"]
    if let session = UITestDevSession.json {
      app.launchEnvironment["KINOPUB_DEV_SESSION"] = session
    }
    app.launch()
    XCTAssertTrue(firstPoster(in: app, page: "home").waitForExistence(timeout: 90))

    for _ in 0..<6 where focusedPoster(in: app) == nil {
      XCUIRemote.shared.press(.down)
      Thread.sleep(forTimeInterval: 0.6)
    }
    guard let poster = focusedPoster(in: app) else {
      try shoot(app, name: "pop-focus-never-focused")
      return XCTFail("never focused a poster")
    }
    let posterID = poster.identifier
    try shoot(app, name: "pop-focus-before-select")

    XCUIRemote.shared.press(.select)
    Thread.sleep(forTimeInterval: 0.8)
    try shoot(app, name: "pop-focus-detail-0.8s")
    Thread.sleep(forTimeInterval: 3.2)
    try shoot(app, name: "pop-focus-detail")

    XCUIRemote.shared.press(.menu)
    Thread.sleep(forTimeInterval: 1)
    try shoot(app, name: "pop-focus-after-menu-1s")
    Thread.sleep(forTimeInterval: 2)
    try shoot(app, name: "pop-focus-after-menu")

    let back = focusedPoster(in: app)
    XCTAssertNotNil(back, "after Menu nothing in the page is focused — focus went to the tab bar?\n\(focusDescription(app))")
    XCTAssertEqual(back?.identifier, posterID, "focus came back to a different poster")
  }

  /// Three rows down: the observed collection has scrolled past the bar's own
  /// threshold, so the bar should be hidden; Up from the first row brings it back.
  /// Screenshots only — the bar's visibility is judged by eye until a stable
  /// accessibility signal for "hidden" is found.
  func testTabBarHidesOnScrollDown() throws {
    let app = launchSignedIn()
    XCTAssertTrue(firstPoster(in: app, page: "home").waitForExistence(timeout: 90))
    for _ in 0..<3 {
      XCUIRemote.shared.press(.down)
      Thread.sleep(forTimeInterval: 0.7)
    }
    try shoot(app, name: "tabbar-three-down")
    for _ in 0..<3 {
      XCUIRemote.shared.press(.up)
      Thread.sleep(forTimeInterval: 0.7)
    }
    try shoot(app, name: "tabbar-back-up")
  }

  /// Flicking Movies ↔ Series with a focused row behind each switch used to leave every
  /// poster of that row lifted at once (the system's unfocus animation never ran).
  /// A lifted lockup reports a bigger accessibility frame, so count them.
  func testRapidTabSwitchingStrandsNoPosters() throws {
    let app = launchSignedIn()
    XCTAssertTrue(firstPoster(in: app, page: "home").waitForExistence(timeout: 90))
    XCUIRemote.shared.press(.right)
    XCTAssertTrue(firstPoster(in: app, page: "movies").waitForExistence(timeout: 60))
    // Into the page, so the row has a remembered focus, then back to the bar.
    XCUIRemote.shared.press(.down); Thread.sleep(forTimeInterval: 0.6)
    XCUIRemote.shared.press(.right); Thread.sleep(forTimeInterval: 0.6)
    XCUIRemote.shared.press(.up); Thread.sleep(forTimeInterval: 0.6)
    for _ in 0..<4 {
      XCUIRemote.shared.press(.right); Thread.sleep(forTimeInterval: 0.15)
      XCUIRemote.shared.press(.left); Thread.sleep(forTimeInterval: 0.15)
    }
    Thread.sleep(forTimeInterval: 2.5)
    try shoot(app, name: "rapid-switch-settled")

    let posters = app.descendants(matching: .any).matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "kinopub.poster.")
    )
    let widths = (0..<min(posters.count, 14)).map { posters.element(boundBy: $0).frame.width }
    let lifted = widths.filter { $0 > 260 * 1.15 }
    XCTAssertLessThanOrEqual(lifted.count, 1, "stranded lifted posters: \(widths)")
  }

  /// Every section template in one walk: Down through the gallery, a shot per step.
  /// No session needed — the gallery is the app root under `-KINOPUBTemplatesGallery`.
  func testTemplatesGalleryWalk() throws {
    let app = XCUIApplication()
    app.launchArguments += ["-ui-testing", "-KINOPUBTemplatesGallery", "-KINOPUBForceColorScheme", "dark"]
    app.launch()
    Thread.sleep(forTimeInterval: 4)
    try shoot(app, name: "gallery-0")
    for step in 1...9 {
      XCUIRemote.shared.press(.down)
      Thread.sleep(forTimeInterval: 0.9)
      try shoot(app, name: "gallery-\(step)")
    }
    XCUIRemote.shared.press(.right)
    Thread.sleep(forTimeInterval: 0.9)
    try shoot(app, name: "gallery-right")
  }

  /// Search (the tab left of Watch Now) and Library (three right): shots of each
  /// landing, then one step into the content.
  func testSearchAndLibraryShots() throws {
    let app = launchSignedIn()
    XCTAssertTrue(firstPoster(in: app, page: "home").waitForExistence(timeout: 90))

    XCUIRemote.shared.press(.left)
    Thread.sleep(forTimeInterval: 4)
    try shoot(app, name: "search-landing")
    XCUIRemote.shared.press(.down); Thread.sleep(forTimeInterval: 1)
    try shoot(app, name: "search-keyboard")
    for _ in 0..<4 { XCUIRemote.shared.press(.down); Thread.sleep(forTimeInterval: 0.8) }
    try shoot(app, name: "search-results")
    for _ in 0..<8 { XCUIRemote.shared.press(.up); Thread.sleep(forTimeInterval: 0.3) }

    for _ in 0..<4 { XCUIRemote.shared.press(.right); Thread.sleep(forTimeInterval: 0.6) }
    Thread.sleep(forTimeInterval: 4)
    try shoot(app, name: "library-landing")
    XCUIRemote.shared.press(.down); Thread.sleep(forTimeInterval: 0.8)
    XCUIRemote.shared.press(.right); Thread.sleep(forTimeInterval: 1.2)
    try shoot(app, name: "library-grid")
  }

  /// Search end to end on whatever the device holds: type a query the Home rows are
  /// likely to contain, shoot the suggestion row and the results, move to the scope
  /// bar, then scroll into the results (the keyboard should scroll away).
  func testSearchTypingScopeAndScroll() throws {
    // The inline tvOS keyboard takes no `typeText`; the field starts filled instead.
    let app = XCUIApplication()
    app.launchArguments += ["-ui-testing", "-KINOPUBForceColorScheme", "dark", "-KINOPUBSearchQuery", "ма"]
    if let session = UITestDevSession.json {
      app.launchEnvironment["KINOPUB_DEV_SESSION"] = session
    }
    app.launch()
    XCTAssertTrue(firstPoster(in: app, page: "home").waitForExistence(timeout: 90))
    XCUIRemote.shared.press(.left)
    Thread.sleep(forTimeInterval: 3.5)
    try shoot(app, name: "search2-typed")
    XCUIRemote.shared.press(.down); Thread.sleep(forTimeInterval: 1)
    try shoot(app, name: "search2-down1")
    XCUIRemote.shared.press(.down); Thread.sleep(forTimeInterval: 1)
    try shoot(app, name: "search2-down2")
    XCUIRemote.shared.press(.up); Thread.sleep(forTimeInterval: 1)
    XCUIRemote.shared.press(.up); Thread.sleep(forTimeInterval: 1)
    try shoot(app, name: "search2-up")
    XCUIRemote.shared.press(.right); Thread.sleep(forTimeInterval: 0.6)
    try shoot(app, name: "search2-right")
    XCUIRemote.shared.press(.select); Thread.sleep(forTimeInterval: 1.5)
    try shoot(app, name: "search2-scope-movies")
    for _ in 0..<2 { XCUIRemote.shared.press(.down); Thread.sleep(forTimeInterval: 0.8) }
    try shoot(app, name: "search2-scrolled")
  }

  private func launchSignedIn() -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments += ["-ui-testing", "-KINOPUBForceColorScheme", "dark"]
    if let session = UITestDevSession.json {
      app.launchEnvironment["KINOPUB_DEV_SESSION"] = session
    }
    app.launch()
    return app
  }

  private func focusedPoster(in app: XCUIApplication) -> XCUIElement? {
    let hit = app.descendants(matching: .any).matching(
      NSPredicate(format: "identifier BEGINSWITH %@ AND hasFocus == true", "kinopub.poster.")
    ).firstMatch
    return hit.exists ? hit : nil
  }

  private func focusDescription(_ app: XCUIApplication) -> String {
    let focused = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true"))
    return (0..<min(focused.count, 5)).map { focused.element(boundBy: $0).debugDescription.prefix(200).description }.joined(separator: "\n")
  }

  private func firstPoster(in app: XCUIApplication, page: String) -> XCUIElement {
    app.collectionViews["kinopub.page.\(page)"].descendants(matching: .any).matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "kinopub.poster.")
    ).firstMatch
  }

  private func shoot(_ app: XCUIApplication, name: String) throws {
    let screenshot = app.screenshot()
    let attachment = XCTAttachment(screenshot: screenshot)
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
    let dir = URL(fileURLWithPath: "/tmp/kinopub-page-shots", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try screenshot.pngRepresentation.write(to: dir.appendingPathComponent("\(name).png"))
  }
}
#endif
