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

  /// Settings left from deep inside without Menu — a Top Shelf link selects Home over the
  /// Experiments page — and then chosen again from the tab bar: it opens at its first
  /// level with the tab bar showing, not on Experiments with the bar gone (Sasha,
  /// 2026-10-25). Needs the simulator's kino.pub session; the shots are the record.
  func testSettingsLeftWithoutMenuReopensAtItsFirstLevel() throws {
    try XCTSkipUnless(FileManager.default.fileExists(atPath: UITestDevSession.filePath),
                      "no ~/.kinopub-dev-session.json — local Settings walk only")
    let app = XCUIApplication()
    app.launchArguments += ["-KINOPUBInitialTab", "settings", "-KINOPUBSettingsPage", "experiments",
                            "-KINOPUBForceColorScheme", "dark"]
    if let session = UITestDevSession.json {
      app.launchEnvironment["KINOPUB_DEV_SESSION"] = session
    }
    app.launch()
    Thread.sleep(forTimeInterval: 4)
    try shoot(app, name: "settings-0-experiments")
    XCTAssertFalse(app.tabBars.firstMatch.isHittable, "Experiments should hide the tab bar")
    app.open(URL(string: "kinopub://title/1")!)
    Thread.sleep(forTimeInterval: 3)
    try shoot(app, name: "settings-1-top-shelf-link")
    for _ in 0..<4 where !tabBarFocused(in: app) {
      XCUIRemote.shared.press(.menu)
      Thread.sleep(forTimeInterval: 1.5)
    }
    XCTAssertTrue(tabBarFocused(in: app), focusDescription(app))
    // Settings is the last tab; moving focus onto a tab selects it.
    for _ in 0..<10 {
      XCUIRemote.shared.press(.right)
      Thread.sleep(forTimeInterval: 0.6)
    }
    Thread.sleep(forTimeInterval: 2)
    try shoot(app, name: "settings-2-back-in-settings")
    XCTAssertTrue(tabBarFocused(in: app), "the tab bar went away\n\(focusDescription(app))")
  }

  /// The tab bar leaves with a pushed page every time, not only the first (Sasha,
  /// 2026-11-16): Home hero → «Подробнее» → Menu back to the hero → «Подробнее» again →
  /// Play showed the bar over the title page and over the black player at 00:00.
  /// Two rounds, the bar checked on the hero, the title page and the player. Needs the
  /// simulator's kino.pub session (the real Home hero).
  func testTabBarStaysHiddenOnTitleAndPlayerOpenedTwiceFromTheHero() throws {
    try XCTSkipUnless(FileManager.default.fileExists(atPath: UITestDevSession.filePath),
                      "no ~/.kinopub-dev-session.json — live Home hero only")
    let app = XCUIApplication()
    app.launchArguments += ["-KINOPUBInitialTab", "home", "-KINOPUBForceColorScheme", "dark"]
    if let session = UITestDevSession.json {
      app.launchEnvironment["KINOPUB_DEV_SESSION"] = session
    }
    app.launch()
    let details = app.buttons["kinopub.hero.details"]
    XCTAssertTrue(details.waitForExistence(timeout: 30), "no Home hero")
    Thread.sleep(forTimeInterval: 2)

    for round in 1...2 {
      try focusHeroDetails(in: app)
      try shoot(app, name: "hero-reentry-\(round)-0-hero")
      XCTAssertTrue(tabBarOnScreen(in: app), "round \(round): the hero should show the tab bar")

      XCUIRemote.shared.press(.select)
      Thread.sleep(forTimeInterval: 0.25)
      try shoot(app, name: "hero-reentry-\(round)-1-opening")
      Thread.sleep(forTimeInterval: 2.5)
      try shoot(app, name: "hero-reentry-\(round)-2-title")
      XCTAssertFalse(details.exists && details.isHittable, "round \(round): the title never opened")
      XCTAssertFalse(tabBarOnScreen(in: app),
                     "round \(round): tab bar over the title page\n\(tabBarDescription(app))")

      if round == 2 {
        // Play is the title page's entry focus.
        XCUIRemote.shared.press(.select)
        Thread.sleep(forTimeInterval: 4)
        try shoot(app, name: "hero-reentry-\(round)-3-player")
        XCTAssertFalse(tabBarOnScreen(in: app),
                       "round \(round): tab bar over the player\n\(tabBarDescription(app))")
        XCUIRemote.shared.press(.menu)
        Thread.sleep(forTimeInterval: 2.5)
        try shoot(app, name: "hero-reentry-\(round)-4-back-on-title")
        XCTAssertFalse(tabBarOnScreen(in: app),
                       "round \(round): tab bar over the title after the player\n\(tabBarDescription(app))")
      }

      XCUIRemote.shared.press(.menu)
      Thread.sleep(forTimeInterval: 0.2)
      try shoot(app, name: "hero-reentry-\(round)-5-closing")
      XCTAssertTrue(details.waitForExistence(timeout: 6), "round \(round): Menu did not return to the hero")
      Thread.sleep(forTimeInterval: 2)
      try shoot(app, name: "hero-reentry-\(round)-6-back")
      XCTAssertTrue(tabBarOnScreen(in: app), "round \(round): the tab bar did not come back on Home")
    }
  }

  private func focusHeroDetails(in app: XCUIApplication) throws {
    let details = app.buttons["kinopub.hero.details"]
    for _ in 0..<8 where !details.hasFocus {
      let heroFocused = app.buttons.matching(
        NSPredicate(format: "identifier BEGINSWITH %@ AND hasFocus == true", "kinopub.hero.")
      ).firstMatch.exists
      XCUIRemote.shared.press(heroFocused ? .left : .down)
      Thread.sleep(forTimeInterval: 0.8)
    }
    XCTAssertTrue(details.hasFocus, "never reached «Подробнее»\n\(focusDescription(app))")
  }

  /// The real bar (not a leftover snapshot): present, hittable, and inside the screen.
  private func tabBarOnScreen(in app: XCUIApplication) -> Bool {
    let bar = app.tabBars.firstMatch
    guard bar.exists, bar.isHittable else { return false }
    return bar.frame.maxY > 0 && bar.frame.intersects(app.windows.firstMatch.frame)
  }

  private func tabBarDescription(_ app: XCUIApplication) -> String {
    let bar = app.tabBars.firstMatch
    return bar.exists ? "tab bar \(bar.frame) hittable \(bar.isHittable)" : "no tab bar"
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
