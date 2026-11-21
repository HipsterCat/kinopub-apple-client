#if os(tvOS)
//
//  TVSearchLayoutUITests.swift
//  KinoPubAppleClientUITests
//
//  Search results against both system keyboards, on the search fixture (no session).
//  The linear keyboard is a row on top and the results are full width; the grid keyboard
//  (Settings → General → Keyboard) stands on the left and the
//  system gives the results only the width beside it. With «Grid keyboard always visible»
//  on (the default) it stays there and the tab bar and field stay put while the results
//  scroll; off, it hides while focus is in the results and the bar leaves with the scroll,
//  as in Apple's apps. Results reaching the screen's left edge in grid mode lay over the
//  keyboard (2026-10-18).
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

  /// Opening Search from Watch Now must paint the field / keyboard / filters without
  /// a multi-second empty tab. Production selects Home first; Search's SwiftUI `Tab`
  /// is lazy. `-KINOPUBSearchFixtureStartOnWatchNow` is that path.
  func testSearchTabChromeAppearsWhenOpenedFromWatchNow() throws {
    let app = launch(gridKeyboard: true, startOnWatchNow: true)
    XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 20), "tab bar never appeared")
    let opened = Date()
    press(.left, wait: 0.2)
    // The collection id is assigned when the tab takes the pre-warmed stack —
    // not on a parking window. `searchFields` / `keyboards` would match that
    // window if it were visible to XCTest.
    XCTAssertTrue(
      app.collectionViews["kinopub.page.search"].waitForExistence(timeout: 3),
      "Search chrome did not appear after opening the tab"
    )
    let elapsed = Date().timeIntervalSince(opened)
    try shoot(app, name: "from-watch-now")
    XCTAssertLessThan(elapsed, 3, "Search tab first chrome took \(elapsed)s")
  }

  /// «Grid keyboard always visible» off. Focus below the keyboard: the grid keyboard slides
  /// away and the page takes the screen's width, as in Apple's apps. Down from the suggestions lands on the filter row
  /// (Genre), not a poster; the keyboard is already gone there. Left from the first column
  /// brings it back and the results move over.
  func testGridKeyboardHidesWhileResultsHaveFocus() throws {
    let app = launch(gridKeyboard: true, alwaysVisible: false)
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

  /// «Grid keyboard always visible» on (Sasha, 2026-11-20). Focus walks down into the
  /// results and four rows on: the keyboard stays on the left with the results beside it,
  /// and the tab bar, the field and the keyboard do not move. Left from the first column
  /// goes back to the keyboard, and Up from there reaches the tab bar.
  func testGridKeyboardStaysBesideTheResultsAndTheChromeStays() throws {
    let app = launch(gridKeyboard: true)
    let width = app.frame.width
    let focusedTab = app.tabBars.buttons.matching(NSPredicate(format: "hasFocus == true")).firstMatch
    XCTAssertTrue(focusedTab.exists, "launch did not start on the Search tab")
    let tab = app.tabBars.buttons[focusedTab.label]
    let field = app.searchFields.firstMatch
    let keyboard = app.keyboards.firstMatch
    XCTAssertTrue(keyboard.exists, "no grid keyboard on screen")
    let (tabFrame, fieldFrame, keyboardFrame) = (tab.frame, field.frame, keyboard.frame)

    for _ in 0..<8 where focusedPoster(in: app) == nil {
      press(.down, wait: 1)
    }
    let first = try XCTUnwrap(focusedPoster(in: app), "never reached the posters\n\(focusDescription(app))")
    try shoot(app, name: "grid-always-0-first-poster")
    press(.down, 4, wait: 1.2)
    try shoot(app, name: "grid-always-1-four-rows-down")
    let deep = try XCTUnwrap(focusedPoster(in: app), "focus left the posters\n\(focusDescription(app))")
    XCTAssertNotEqual(deep, first, "Down did not move through the grid")
    XCTAssertTrue(keyboard.exists, "the keyboard went away with focus in the results")
    XCTAssertEqual(keyboard.frame.minX, keyboardFrame.minX, accuracy: 2, "keyboard moved \(keyboard.frame)")
    XCTAssertEqual(keyboard.frame.minY, keyboardFrame.minY, accuracy: 2, "keyboard moved \(keyboard.frame)")
    assertBesideGridKeyboard(try resultsFrame(in: app), width: width)
    XCTAssertTrue(tab.exists, "the tab bar left with the scroll")
    XCTAssertEqual(tab.frame.minY, tabFrame.minY, accuracy: 2, "tab bar moved \(tab.frame)")
    XCTAssertEqual(field.frame.minY, fieldFrame.minY, accuracy: 2, "field moved \(field.frame)")

    // Left along the row to its first column, then once more into the keyboard.
    for _ in 0..<8 where !keyboardFocused(in: app) {
      press(.left, wait: 0.8)
    }
    try shoot(app, name: "grid-always-2-left-to-keyboard")
    XCTAssertTrue(keyboardFocused(in: app), "Left from the first column did not reach the keyboard\n\(focusDescription(app))")
    XCTAssertEqual(tab.frame.minY, tabFrame.minY, accuracy: 2, "tab bar moved \(tab.frame)")
    XCTAssertEqual(field.frame.minY, fieldFrame.minY, accuracy: 2, "field moved \(field.frame)")
    for _ in 0..<8 where !tabBarFocused(in: app) {
      press(.up, wait: 0.8)
    }
    XCTAssertTrue(tabBarFocused(in: app), "Up from the keyboard never reached the tab bar\n\(focusDescription(app))")
  }

  /// «Grid keyboard always visible» on: Up from the first row of posters climbs the filter
  /// and suggestion rows to the tab bar.
  func testGridKeyboardUpFromTheResultsReachesTheTab() throws {
    let app = launch(gridKeyboard: true)
    for _ in 0..<8 where focusedPoster(in: app) == nil {
      press(.down, wait: 1)
    }
    XCTAssertNotNil(focusedPoster(in: app), "never reached the posters\n\(focusDescription(app))")
    for _ in 0..<6 where !tabBarFocused(in: app) {
      press(.up, wait: 1)
    }
    try shoot(app, name: "grid-always-3-up-to-tab")
    XCTAssertTrue(tabBarFocused(in: app), "Up from the results never reached the tab bar\n\(focusDescription(app))")
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
    // The bar leaving with the scrolled results is the OFF variant's; ON keeps it
    // (`testGridKeyboardStaysBesideTheResultsAndTheChromeStays`).
    let app = launch(gridKeyboard: true, alwaysVisible: !afterScrolledResults)
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

  /// Menu six rows deep in the results grid goes back to their top row in one press — the
  /// filter row's first chip, Sort — and the next Menu leaves the results (the tab bar under
  /// the linear keyboard, the keyboard beside the grid one). It went up one row per press: the
  /// request landed on the controller, which Search keeps from claiming focus, and the chip
  /// cell off screen offered no button, so the engine took the nearest visible card (2026-10-25).
  func testMenuFromDeepInTheGridReturnsToTheTopRow() throws {
    for grid in [false, true] {
      let app = launch(gridKeyboard: grid)
      let prefix = grid ? "menu-grid" : "menu-linear"
      // Tab → keyboard → … → the first poster.
      for _ in 0..<8 where focusedPoster(in: app) == nil {
        press(.down, wait: 1)
      }
      let first = try XCTUnwrap(focusedPoster(in: app), "never reached the posters\n\(focusDescription(app))")
      press(.down, 5, wait: 1)
      try shoot(app, name: "\(prefix)-0-deep")
      let deep = try XCTUnwrap(focusedPoster(in: app), "focus left the posters\n\(focusDescription(app))")
      XCTAssertNotEqual(deep, first, "Down did not move through the grid")

      press(.menu, wait: 1.6)
      try shoot(app, name: "\(prefix)-1-menu")
      XCTAssertTrue(sortChipFocused(in: app),
                    "\(prefix): Menu from \(deep) did not reach the filter row\n\(focusDescription(app))")

      press(.menu, wait: 1.6)
      try shoot(app, name: "\(prefix)-2-menu-again")
      XCTAssertFalse(sortChipFocused(in: app), "\(prefix): second Menu stayed on the filter row")
      XCTAssertNil(focusedPoster(in: app), "\(prefix): second Menu went back into the posters")
      app.terminate()
    }
  }

  // MARK: - Helpers

  /// The first chip of the filter row, the page's top row. Queried, not read off the element:
  /// scrolled away it is not in the tree at all.
  private func sortChipFocused(in app: XCUIApplication) -> Bool {
    app.buttons.matching(NSPredicate(format: "identifier == %@ AND hasFocus == true", "kinopub.chip.sort"))
      .firstMatch.exists
  }

  private func focusedPoster(in app: XCUIApplication) -> String? {
    let poster = app.collectionViews["kinopub.page.search"].cells.matching(
      NSPredicate(format: "identifier BEGINSWITH %@ AND hasFocus == true", "kinopub.poster.")
    ).firstMatch
    return poster.exists ? poster.identifier : nil
  }

  private func focusDescription(_ app: XCUIApplication) -> String {
    let focused = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true"))
    return (0..<min(focused.count, 6)).map {
      focused.element(boundBy: $0).debugDescription.prefix(220).description
    }.joined(separator: "\n")
  }

  /// The keyboard's keys report no focus to XCUITest (the focused «a» is drawn lifted, yet
  /// `hasFocus` is false everywhere). Focus that left the results and is not on the tab bar
  /// is the keyboard on this screen; the screenshots are the record.
  private func keyboardFocused(in app: XCUIApplication) -> Bool {
    let inResults = app.collectionViews["kinopub.page.search"].descendants(matching: .any)
      .matching(NSPredicate(format: "hasFocus == true")).count > 0
    return !inResults && !tabBarFocused(in: app)
  }

  private func tabBarFocused(in app: XCUIApplication) -> Bool {
    app.tabBars.buttons.matching(NSPredicate(format: "hasFocus == true")).count > 0
  }

  private func press(_ button: XCUIRemote.Button, _ times: Int = 1, wait: TimeInterval = 0.7) {
    for _ in 0..<times { XCUIRemote.shared.press(button); Thread.sleep(forTimeInterval: wait) }
  }

  /// `alwaysVisible`: «Grid keyboard always visible», passed every time so a switch left in
  /// the simulator's Settings cannot decide the run.
  private func launch(gridKeyboard: Bool, topCards: Bool = false, alwaysVisible: Bool = true,
                      startOnWatchNow: Bool = false) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments += ["-ui-testing", "-KINOPUBSearchFixture", "-KINOPUBForceColorScheme", "dark",
                            "-ForceGridKeyboard", gridKeyboard ? "YES" : "NO",
                            // The simulator's own Settings › Keyboard choice (com.apple.UIKit):
                            // 1 linear, 2 grid. On tvOS 26.5 `-ForceGridKeyboard NO` does not
                            // override a simulator set to grid, and the linear test met the
                            // grid keyboard (2026-11-20).
                            "-UserPreferredKeyboardStyle", gridKeyboard ? "2" : "1",
                            "-featureFlag.gridKeyboardAlwaysVisible", alwaysVisible ? "<true/>" : "<false/>"]
    if topCards { app.launchArguments.append("-KINOPUBSearchFixtureTopCards") }
    if startOnWatchNow { app.launchArguments.append("-KINOPUBSearchFixtureStartOnWatchNow") }
    app.launch()
    if startOnWatchNow {
      XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 20), "tab bar never appeared")
      Thread.sleep(forTimeInterval: 0.6)
      return app
    }
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
