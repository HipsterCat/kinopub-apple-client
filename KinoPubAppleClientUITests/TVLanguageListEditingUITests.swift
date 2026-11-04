#if os(tvOS)
//
//  TVLanguageListEditingUITests.swift
//  KinoPubAppleClientUITests
//
//  Settings › Video & audio › Prefer subtitles in, edited with the remote the way
//  Settings › Apple TV Languages is: Edit, then the row's ≡ to carry it, the trash to
//  remove it, Done or Cancel. Needs a signed-in session (Settings is behind it); skips
//  without one.
//

import XCTest

final class TVLanguageListEditingUITests: XCTestCase {

  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  private func launch() -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments += ["-KINOPUBInitialTab", "settings",
                            "-KINOPUBSettingsPage", "videoAudio",
                            "-KINOPUBSettingsLanguages", "subtitles",
                            "-KINOPUBSettingsLanguagesSeed", "en,ru,uk",
                            "-KINOPUBForceColorScheme", "dark",
                            "-AppleLanguages", "(en)"]
    app.launch()
    return app
  }

  /// Edit, the English row's ≡, Down, Select, Done: English is second, and the list
  /// is the page again (Add Language… back under it).
  func testReorderWithTheHandleAndDone() throws {
    let app = try openList()
    press(.down)                    // English
    press(.up)                      // Edit
    try expectFocus(app, "Edit")
    press(.select)
    try expectFocus(app, "Done")
    XCTAssertFalse(app.staticTexts["Add Language…"].exists, "editing shows the list alone")
    press(.down)                    // English's trash
    press(.right)                   // English's ≡
    try expectFocus(app, "Reorder English")
    // The simulator's remote carries a lifted row one row per *two* Down presses — the
    // first leaves it halfway, its neighbour hidden, and a drop there puts it back. Apple's
    // own Settings › Apple TV Languages does exactly the same on the 27.2 simulator (probed
    // 2026-11-01), so this is the remote, not the page. On a device: one press, one row.
    press(.select, wait: 3)         // lift
    press(.down, wait: 3)
    press(.down, wait: 3)           // carried one row down
    press(.select, wait: 3)         // drop
    try shoot(app, name: "reordered")
    try expectFocus(app, "Reorder English")
    XCTAssertEqual(languages(in: app), ["Russian", "English", "Ukrainian"])

    press(.up)
    press(.up)                      // the bar: Cancel or Done
    for _ in 0..<2 where !isFocused(app, "Done") { press(.right) }
    try expectFocus(app, "Done")
    press(.select, wait: 2)
    XCTAssertTrue(app.staticTexts["Add Language…"].waitForExistence(timeout: 5))
    XCTAssertEqual(languages(in: app), ["Russian", "English", "Ukrainian"])
  }

  /// The trash removes a row at once; Cancel puts the list back as it was.
  func testDeleteThenCancelRestoresTheList() throws {
    let app = try openList()
    press(.down)
    press(.up)
    press(.select)                  // Edit
    press(.down)                    // English's trash
    try expectFocus(app, "Remove English")
    press(.select, wait: 2)
    try shoot(app, name: "deleted")
    XCTAssertEqual(languages(in: app), ["Russian", "Ukrainian"])

    press(.up)
    for _ in 0..<2 where !isFocused(app, "Cancel") { press(.left) }
    try expectFocus(app, "Cancel")
    press(.select, wait: 2)
    XCTAssertTrue(app.staticTexts["Add Language…"].waitForExistence(timeout: 5))
    XCTAssertEqual(languages(in: app), ["English", "Russian", "Ukrainian"])
  }

  private func openList() throws -> XCUIApplication {
    let app = launch()
    guard app.staticTexts["Ukrainian"].waitForExistence(timeout: 25) else {
      throw XCTSkip("Settings did not open — no session on this simulator?")
    }
    Thread.sleep(forTimeInterval: 2)
    return app
  }

  private func press(_ button: XCUIRemote.Button, wait: TimeInterval = 1.2) {
    XCUIRemote.shared.press(button)
    Thread.sleep(forTimeInterval: wait)
  }

  /// The list's rows, top to bottom.
  private func languages(in app: XCUIApplication) -> [String] {
    let names: Set = ["English", "Russian", "Ukrainian"]
    return app.cells.allElementsBoundByIndex
      .filter { names.contains($0.label) }
      .sorted { $0.frame.minY < $1.frame.minY }
      .map { $0.label }
  }

  private func isFocused(_ app: XCUIApplication, _ label: String) -> Bool {
    app.descendants(matching: .any)
      .matching(NSPredicate(format: "hasFocus == true AND label == %@", label)).count > 0
  }

  private func expectFocus(_ app: XCUIApplication, _ label: String,
                           file: StaticString = #filePath, line: UInt = #line) throws {
    XCTAssertTrue(isFocused(app, label), "focus is not on \(label)\n\(focusDescription(app))",
                  file: file, line: line)
  }

  private func focusDescription(_ app: XCUIApplication) -> String {
    let focused = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true"))
    return (0..<min(focused.count, 4)).map {
      focused.element(boundBy: $0).debugDescription.prefix(300).description
    }.joined(separator: "\n")
  }

  private func shoot(_ app: XCUIApplication, name: String) throws {
    let screenshot = app.screenshot()
    let dir = URL(fileURLWithPath: "/tmp/kinopub-page-shots", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try screenshot.pngRepresentation.write(to: dir.appendingPathComponent("lang-edit-\(name).png"))
  }
}
#endif
