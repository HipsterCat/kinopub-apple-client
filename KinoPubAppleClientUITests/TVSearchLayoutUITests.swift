#if os(tvOS)
//
//  TVSearchLayoutUITests.swift
//  KinoPubAppleClientUITests
//
//  Search results against both system keyboards, on the search fixture (no session).
//  The linear keyboard is a row on top and the results are full width; the grid keyboard
//  (Settings → General → Keyboard) stands on the left and the
//  system gives the results only the width beside it, and hides the keyboard while focus
//  is in them. Results reaching the screen's left edge in grid mode lay over the keyboard
//  (2026-10-18).
//

import XCTest

final class TVSearchLayoutUITests: XCTestCase {

  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  /// Up from the keyboard returns to the Search tab. A focus guide left on in the
  /// band above the keys used to redirect that press onto a filter chip (2026-10-25).
  func testUpFromTheKeyboardReturnsToTheTab() throws {
    let app = launch(gridKeyboard: false)
    if tabBarFocused(in: app) {
      press(.down, wait: 1.2)
    }
    XCTAssertFalse(tabBarFocused(in: app), "Down from the Search tab never entered the page")
    press(.up, wait: 1)
    try shoot(app, name: "up-from-keyboard")
    XCTAssertTrue(tabBarFocused(in: app), "Up from the keyboard did not return to the Search tab")
    XCTAssertFalse(app.buttons["kinopub.chip.sort"].hasFocus)
    XCTAssertFalse(app.buttons["kinopub.chip.genre"].hasFocus)
  }

  func testLinearKeyboardResultsSpanTheScreen() throws {
    let app = launch(gridKeyboard: false)
    let frame = try resultsFrame(in: app)
    try shoot(app, name: "linear")
    let width = app.frame.width
    // The HIG side inset from the screen edge, not doubled by the container's safe area.
    XCTAssertEqual(frame.minX, width * 80 / 1920, accuracy: width * 30 / 1920, "results \(frame)")
    XCTAssertLessThan(frame.maxX, width, "results \(frame)")
  }

  func testGridKeyboardResultsStayBesideIt() throws {
    let app = launch(gridKeyboard: true)
    let frame = try resultsFrame(in: app)
    try shoot(app, name: "grid")
    assertBesideGridKeyboard(frame, width: app.frame.width)
  }

  /// Focus in the results: the grid keyboard slides away and the results take the
  /// screen's width. Left from the first column brings it back and the results move over.
  func testGridKeyboardHidesWhileResultsHaveFocus() throws {
    let app = launch(gridKeyboard: true)
    let width = app.frame.width
    // Tab pill → keyboard → along its top row to the suggestions → down into the results.
    press(.down)
    press(.right, 7)
    press(.down, wait: 1.5)
    try shoot(app, name: "grid-results-focused")
    XCTAssertLessThan(try resultsFrame(in: app).minX, width * 0.2, "keyboard still beside the results")
    press(.left, 3, wait: 1)
    Thread.sleep(forTimeInterval: 1)
    try shoot(app, name: "grid-keyboard-back")
    assertBesideGridKeyboard(try resultsFrame(in: app), width: width)
  }

  // MARK: - Helpers

  private func tabBarFocused(in app: XCUIApplication) -> Bool {
    app.tabBars.buttons.matching(NSPredicate(format: "hasFocus == true")).count > 0
  }

  private func press(_ button: XCUIRemote.Button, _ times: Int = 1, wait: TimeInterval = 0.7) {
    for _ in 0..<times { XCUIRemote.shared.press(button); Thread.sleep(forTimeInterval: wait) }
  }

  private func launch(gridKeyboard: Bool) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments += ["-ui-testing", "-KINOPUBSearchFixture", "-KINOPUBForceColorScheme", "dark",
                            "-ForceGridKeyboard", gridKeyboard ? "YES" : "NO"]
    app.launch()
    XCTAssertTrue(app.collectionViews["kinopub.page.search"].cells.firstMatch.waitForExistence(timeout: 20),
                  "search results never appeared")
    Thread.sleep(forTimeInterval: 1.5)
    return app
  }

  /// The box the on-screen result cells fill.
  private func resultsFrame(in app: XCUIApplication) throws -> CGRect {
    let screen = app.frame
    let frames = app.collectionViews["kinopub.page.search"].cells.allElementsBoundByIndex
      .map { $0.frame }
      .filter { !$0.isEmpty && $0.intersects(screen) }
    let union = frames.dropFirst().reduce(frames.first ?? .null) { $0.union($1) }
    return try XCTUnwrap(union.isNull ? nil : union.intersection(screen), "no result cell on screen")
  }

  /// Under the tab bar the grid keyboard ends at x = 512 of 1920 and the system starts the
  /// results at 590 (tvOS 27.2, measured). The row is the full-screen grid, shifted right,
  /// so the last card is clipped and its frame can reach the screen edge.
  private func assertBesideGridKeyboard(_ frame: CGRect, width: CGFloat) {
    XCTAssertGreaterThan(frame.minX, width * 540 / 1920, "results over the keyboard: \(frame)")
    XCTAssertGreaterThan(frame.maxX, width * 0.85, "results stopped short of the right edge: \(frame)")
    XCTAssertLessThanOrEqual(frame.maxX, width + 1, "results \(frame)")
  }

  private func shoot(_ app: XCUIApplication, name: String) throws {
    let screenshot = app.screenshot()
    let attachment = XCTAttachment(screenshot: screenshot)
    attachment.name = "search-\(name)"
    attachment.lifetime = .keepAlways
    add(attachment)
    let dir = URL(fileURLWithPath: "/tmp/kinopub-page-shots", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try screenshot.pngRepresentation.write(to: dir.appendingPathComponent("search-\(name).png"))
  }
}
#endif
