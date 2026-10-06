#if os(tvOS)
//
//  TVMenuBackUITests.swift
//  KinoPubAppleClientUITests
//
//  Staged Menu-back under the system `TabView(.tabBarOnly)`, using the templates
//  gallery so CI needs no kino.pub session. First Menu from a deep shelf must
//  return to the top row; the next Menu must pass through to the tab bar.
//
//  If the first Menu lands on the tab bar instead, the page never saw the press
//  — the same measurement Rivulet recorded for `.sidebarAdaptable`. That is a
//  stop, not a prompt to add a window interceptor (`AGENTS.md`).
//

import XCTest

final class TVMenuBackUITests: XCTestCase {

  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  func testMenuFromDeepShelfReturnsToTopThenTabBar() throws {
    let app = XCUIApplication()
    app.launchArguments += ["-ui-testing", "-KINOPUBMenuBackProbe", "-KINOPUBForceColorScheme", "dark"]
    app.launch()
    XCTAssertEqual(app.state, .runningForeground)
    XCTAssertTrue(app.collectionViews["kinopub.page.templates"].waitForExistence(timeout: 20),
                  "probe page never appeared")

    // Launch focus is the tab pill, same as production. Down enters the banner.
    for _ in 0..<8 where !bannerFocused(in: app) {
      XCUIRemote.shared.press(.down)
      Thread.sleep(forTimeInterval: 0.8)
    }
    try shoot(app, name: "0-entered-page")
    XCTAssertTrue(bannerFocused(in: app),
                  "never entered the page from the tab bar\n\(focusDescription(app))")

    for _ in 0..<4 {
      XCUIRemote.shared.press(.down)
      Thread.sleep(forTimeInterval: 0.8)
    }
    try shoot(app, name: "1-below-top")
    XCTAssertFalse(bannerFocused(in: app), "still on the top row after Down")
    XCTAssertFalse(tabBarFocused(in: app),
                   "focus left the page before Menu\n\(focusDescription(app))")

    XCUIRemote.shared.press(.menu)
    Thread.sleep(forTimeInterval: 1.6)
    try shoot(app, name: "2-menu-from-deep")

    if tabBarFocused(in: app) {
      XCTFail("""
        Menu under TabView(.tabBarOnly) did not reach the page — it went straight \
        to the tab bar. Rivulet saw the same with .sidebarAdaptable and intercepted \
        at UIWindow.sendEvent; AGENTS.md bans that layer. Stop here rather than hack.
        \(focusDescription(app))
        """)
      return
    }
    XCTAssertTrue(bannerFocused(in: app),
                  "Menu did not return focus to the top row\n\(focusDescription(app))")

    XCUIRemote.shared.press(.menu)
    Thread.sleep(forTimeInterval: 1.6)
    try shoot(app, name: "3-menu-from-top")
    XCTAssertTrue(tabBarFocused(in: app),
                  "second Menu did not pass through to the tab bar\n\(focusDescription(app))")
  }

  private func bannerFocused(in app: XCUIApplication) -> Bool {
    app.descendants(matching: .any).matching(
      NSPredicate(format: "identifier BEGINSWITH %@ AND hasFocus == true", "kinopub.banner.")
    ).firstMatch.exists
  }

  private func tabBarFocused(in app: XCUIApplication) -> Bool {
    app.tabBars.buttons.matching(NSPredicate(format: "hasFocus == true")).count > 0
  }

  private func focusDescription(_ app: XCUIApplication) -> String {
    let focused = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true"))
    return (0..<min(focused.count, 6)).map {
      focused.element(boundBy: $0).debugDescription.prefix(220).description
    }.joined(separator: "\n")
  }

  private func shoot(_ app: XCUIApplication, name: String) throws {
    let screenshot = app.screenshot()
    let attachment = XCTAttachment(screenshot: screenshot)
    attachment.name = "menu-back-\(name)"
    attachment.lifetime = .keepAlways
    add(attachment)
    let dir = URL(fileURLWithPath: "/tmp/kinopub-page-shots", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try screenshot.pngRepresentation.write(to: dir.appendingPathComponent("menu-back-\(name).png"))
  }
}
#endif
