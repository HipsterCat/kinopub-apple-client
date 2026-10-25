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

  /// A person among the top cards is the wide card Cast & Crew draws — the same cell, the
  /// title cards' column and height — with the portrait in the avatar. It was the round
  /// lockup grown to a third of the screen, over the row below (2026-10-25).
  func testAPersonAmongTheTopCardsIsTheCastCard() throws {
    let app = launch(gridKeyboard: false, topCards: true)
    let person = app.descendants(matching: .any)["kinopub.card.person.Райан Рейнольдс"].firstMatch
    XCTAssertTrue(person.waitForExistence(timeout: 10), "no person among the top cards")
    // A title card of the same rows: the fixture's titles are 3001…
    let title = app.descendants(matching: .any)["kinopub.card.3001"].firstMatch
    XCTAssertTrue(title.waitForExistence(timeout: 5), "no title among the top cards")
    // Portraits come over the network; give them a moment before the picture.
    Thread.sleep(forTimeInterval: 3)
    try shoot(app, name: "top-cards-people")
    let (personFrame, titleFrame) = (person.frame, title.frame)
    XCTAssertEqual(personFrame.width, titleFrame.width, accuracy: 2, "person \(personFrame) title \(titleFrame)")
    XCTAssertEqual(personFrame.height, titleFrame.height, accuracy: 2, "person \(personFrame) title \(titleFrame)")
    XCTAssertLessThan(personFrame.height, app.frame.height * 0.2, "person card \(personFrame)")
  }

  /// The grid keyboard: the tab bar stays where it is, above the field, while focus walks the
  /// letters and the abc / 123 row — before the results have scrolled and after coming back
  /// from them. On tvOS 26.5 the search chrome scrolled the results back short of their top on
  /// the way in, by the 157 pt window extension: the bar stayed hidden above the screen, the
  /// field sat under the top edge, and Up focused the bar off screen (2026-10-25).
  func testGridKeyboardKeepsTheTabBarAboveTheField() throws {
    try walkTheGridKeyboard(afterScrolledResults: false)
  }

  /// The same, coming back to the keyboard from results scrolled far enough that the bar and the
  /// field went with them.
  func testGridKeyboardKeepsTheTabBarAboveTheFieldAfterTheResults() throws {
    try walkTheGridKeyboard(afterScrolledResults: true)
  }

  /// The grid keyboard: the tab bar stays where it is, above the field, while focus walks the
  /// letters and the abc / 123 row. On tvOS 26.5 the search chrome scrolled the results to
  /// their top less the 157 pt window extension whenever focus came to the field's half: the
  /// bar stayed hidden above the screen, the field sat under the top edge, and Up focused the
  /// bar off screen (2026-10-25).
  private func walkTheGridKeyboard(afterScrolledResults: Bool) throws {
    let app = launch(gridKeyboard: true)
    let focusedTab = app.tabBars.buttons.matching(NSPredicate(format: "hasFocus == true")).firstMatch
    XCTAssertTrue(focusedTab.exists, "launch did not start on the Search tab")
    let tab = app.tabBars.buttons[focusedTab.label]
    let field = app.searchFields.firstMatch
    let (tabFrame, fieldFrame) = (tab.frame, field.frame)
    XCTAssertGreaterThanOrEqual(tabFrame.minY, 0, "tab \(tabFrame)")
    XCTAssertGreaterThanOrEqual(fieldFrame.minY, tabFrame.maxY, "field \(fieldFrame) under the tab \(tabFrame)")
    let prefix = afterScrolledResults ? "grid-chrome-after-results" : "grid-chrome"

    func assertChromeStill(_ step: String, file: StaticString = #filePath, line: UInt = #line) throws {
      try shoot(app, name: "\(prefix)-\(step)")
      XCTAssertFalse(tabBarFocused(in: app), "\(step): focus left the page", file: file, line: line)
      XCTAssertEqual(tab.frame.minY, tabFrame.minY, accuracy: 2, "\(step): tab bar moved \(tab.frame)", file: file, line: line)
      XCTAssertEqual(field.frame.minY, fieldFrame.minY, accuracy: 2, "\(step): field moved \(field.frame)", file: file, line: line)
      XCTAssertGreaterThanOrEqual(field.frame.minY, tab.frame.maxY, "\(step): field under the bar", file: file, line: line)
    }

    if afterScrolledResults {
      // Tab → suggestion → filter row → posters → two rows on, then Left back to the keyboard.
      press(.down, 5, wait: 1)
      try shoot(app, name: "\(prefix)-results")
      XCTAssertLessThan(tab.frame.maxY, 0, "the results scrolled without taking the bar along: \(tab.frame)")
      press(.left, 2, wait: 1)
      Thread.sleep(forTimeInterval: 0.5)
      try assertChromeStill("back")
      for (name, button) in [("down-letter", XCUIRemote.Button.down), ("up-letter", .up), ("up-mode-row", .up), ("right-mode-row", .right),
                             ("down-letter-2", .down), ("right-letter", .right)] {
        press(button, wait: 1)
        try assertChromeStill(name)
      }
    } else {
      // Tab → suggestion → the first one → the abc / 123 row, then the letters and back up.
      let keys: [(String, XCUIRemote.Button)] = [("down", .down), ("left", .left), ("left-mode-row", .left),
                                                ("down-letter", .down), ("left-letter", .left),
                                                ("down-letter-2", .down), ("up-letter", .up),
                                                ("up-mode-row", .up), ("left-mode-row-2", .left)]
      for (name, button) in keys {
        press(button, wait: 1)
        try assertChromeStill(name)
      }
    }
  }

  // MARK: - Helpers

  private func tabBarFocused(in app: XCUIApplication) -> Bool {
    app.tabBars.buttons.matching(NSPredicate(format: "hasFocus == true")).count > 0
  }

  private func press(_ button: XCUIRemote.Button, _ times: Int = 1, wait: TimeInterval = 0.7) {
    for _ in 0..<times { XCUIRemote.shared.press(button); Thread.sleep(forTimeInterval: wait) }
  }

  private func launch(gridKeyboard: Bool, topCards: Bool = false) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments += ["-ui-testing", "-KINOPUBSearchFixture", "-KINOPUBForceColorScheme", "dark",
                            "-ForceGridKeyboard", gridKeyboard ? "YES" : "NO"]
    if topCards { app.launchArguments.append("-KINOPUBSearchFixtureTopCards") }
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
