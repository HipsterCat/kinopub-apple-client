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
    // The link goes to the running app, as the Top Shelf sends it. Not `app.open(_:)`: under
    // Xcode 27.2 that relaunches the app with the URL, so Settings is never left — the app
    // comes back up on it. On tvOS 27.2 that launch, switching from Settings to Home, also
    // left focus on the hidden tab bar and the first Menu closed the app (2026-11-20).
    XCUIDevice.shared.system.open(URL(string: "piratic://title/1")!)
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
        // The first Menu only hides AVKit's transport bar; the next one leaves the player.
        let titlePlay = app.buttons["kinopub.hero.play"]
        for _ in 0..<3 where !titlePlay.exists {
          XCUIRemote.shared.press(.menu)
          Thread.sleep(forTimeInterval: 2.5)
        }
        XCTAssertTrue(titlePlay.exists, "round \(round): Menu never left the player")
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

  /// Library under the real tab bar (fixture, no session): scroll a long section down,
  /// walk the sidebar through sections of other heights and back, then Up to the bar.
  /// The bar must come back whole — frame.minY >= 0 — and Up must reach it
  /// (Sasha, 2026-11-17: bar cut off at the top after folder switches).
  func testLibraryTabBarWholeAfterSectionSwitches() throws {
    continueAfterFailure = true
    let app = XCUIApplication()
    app.launchArguments += ["-ui-testing", "-KINOPUBForceColorScheme", "dark",
                            "-KINOPUBLibraryFixture", "YES", "-KINOPUBFixtureInTabs", "YES"]
    app.launch()
    let page = app.collectionViews["kinopub.page.library"]
    XCTAssertTrue(page.waitForExistence(timeout: 30), "no Library page")
    Thread.sleep(forTimeInterval: 2)
    var step = 0
    func snap(_ name: String) {
      step += 1
      let bar = app.tabBars.firstMatch
      let frame = bar.exists ? bar.frame : .null
      let focused = libFocus(app)
      print("LIBRARY-BAR \(step) \(name) bar \(frame) barFocused \(tabBarFocused(in: app)) focus \(focused)")
      try? shoot(app, name: String(format: "lib-%02d-%@", step, name))
      if bar.exists, tabBarFocused(in: app) {
        XCTAssertGreaterThanOrEqual(frame.minY, -0.5, "step \(step) \(name): focused tab bar cut off \(frame)")
      }
    }
    func row(_ id: String) -> XCUIElement { app.descendants(matching: .any)["kinopub.library.section.\(id)"] }
    func press(_ b: XCUIRemote.Button, _ n: Int = 1, wait: TimeInterval = 0.9) {
      for _ in 0..<n { XCUIRemote.shared.press(b); Thread.sleep(forTimeInterval: wait) }
    }
    func goTo(_ id: String) {
      let target = row(id)
      func on(_ e: XCUIElement) -> Bool { e.exists && e.hasFocus }
      for _ in 0..<10 where !on(target) {
        let ids = ["watchlist", "unwatched", "allBookmarks", "folder:9906001", "folder:9906002", "downloads", "history"]
        let current = ids.firstIndex { on(row($0)) }
        guard let current, let goal = ids.firstIndex(of: id) else { press(.left); continue }
        press(goal > current ? .down : .up, wait: 1.2)
      }
      XCTAssertTrue(on(target), "never reached sidebar row \(id): \(libFocus(app))")
    }
    snap("launch")
    if tabBarFocused(in: app) { press(.down, wait: 1.5); snap("into-page") }
    press(.left); goTo("history"); snap("history-row")
    press(.right, wait: 1.5); press(.down, 4, wait: 1.0); snap("history-scrolled")
    press(.left); snap("back-in-sidebar")
    goTo("folder:9906001"); snap("short-folder")
    goTo("folder:9906002"); snap("long-folder")
    goTo("watchlist"); snap("watchlist")
    goTo("history"); snap("history-again")
    press(.right, wait: 1.5); snap("history-grid")
    press(.down, 3, wait: 1.0); snap("history-down")
    press(.left); goTo("folder:9906001"); goTo("history"); snap("history-third")
    press(.right, wait: 1.5); snap("grid-third")
    var reached = false
    for i in 0..<10 {
      press(.up, wait: 1.2)
      snap("up-\(i)")
      if tabBarFocused(in: app) { reached = true; break }
    }
    XCTAssertTrue(reached, "Up from the grid never reached the tab bar: \(libFocus(app))")
    Thread.sleep(forTimeInterval: 1.5); snap("bar-settled")
    let bar = app.tabBars.firstMatch
    XCTAssertTrue(bar.exists && bar.frame.minY >= -0.5, "tab bar not whole: \(bar.exists ? "\(bar.frame)" : "none")")
    app.terminate()
  }

  /// Same, with a sidebar taller than the screen (a dozen more folders): the sidebar's
  /// own table scrolls. Walk to History at the bottom, scroll its grid, come back up
  /// the whole list to Subscriptions and Up into the tab bar.
  func testLibraryTabBarWholeWithScrollingSidebar() throws {
    continueAfterFailure = true
    let app = XCUIApplication()
    app.launchArguments += ["-ui-testing", "-KINOPUBForceColorScheme", "dark",
                            "-KINOPUBLibraryFixture", "YES", "-KINOPUBFixtureInTabs", "YES",
                            "-KINOPUBLibraryFixtureExtraFolders", "12"]
    app.launch()
    XCTAssertTrue(app.collectionViews["kinopub.page.library"].waitForExistence(timeout: 30), "no Library page")
    Thread.sleep(forTimeInterval: 2)
    var step = 0
    func snap(_ name: String) {
      step += 1
      let bar = app.tabBars.firstMatch
      let frame = bar.exists ? bar.frame : .null
      print("LIBRARY-BAR \(step) \(name) bar \(frame) barFocused \(tabBarFocused(in: app)) focus \(libFocus(app))")
      try? shoot(app, name: String(format: "lib2-%02d-%@", step, name))
      if bar.exists, tabBarFocused(in: app) {
        XCTAssertGreaterThanOrEqual(frame.minY, -0.5, "step \(step) \(name): focused tab bar cut off \(frame)")
      }
    }
    func press(_ b: XCUIRemote.Button, _ n: Int = 1, wait: TimeInterval = 0.9) {
      for _ in 0..<n { XCUIRemote.shared.press(b); Thread.sleep(forTimeInterval: wait) }
    }
    func focusedRowID() -> String? {
      let hit = app.descendants(matching: .any).matching(
        NSPredicate(format: "identifier BEGINSWITH %@ AND hasFocus == true", "kinopub.library.section.")).firstMatch
      return hit.exists ? String(hit.identifier.dropFirst("kinopub.library.section.".count)) : nil
    }
    snap("launch")
    if tabBarFocused(in: app) { press(.down, wait: 1.5) }
    press(.left, wait: 1.2); snap("sidebar")
    for _ in 0..<25 where focusedRowID() != "history" { press(.down, wait: 0.7) }
    Thread.sleep(forTimeInterval: 1.5); snap("history-row")
    XCTAssertEqual(focusedRowID(), "history")
    press(.right, wait: 1.5); press(.down, 4, wait: 1.0); snap("history-scrolled")
    press(.left, wait: 1.2); snap("back-in-sidebar")
    for i in 0..<25 where focusedRowID() != "watchlist" {
      press(.up, wait: 0.6)
      if i % 4 == 0 { snap("sidebar-up-\(i)") }
    }
    Thread.sleep(forTimeInterval: 1.5); snap("watchlist-row")
    var reached = false
    for i in 0..<4 {
      press(.up, wait: 1.2); snap("bar-up-\(i)")
      if tabBarFocused(in: app) { reached = true; break }
    }
    XCTAssertTrue(reached, "Up from Subscriptions never reached the tab bar: \(libFocus(app))")
    Thread.sleep(forTimeInterval: 1.5); snap("bar-settled")
    // Down into the page again, then folders up and down at speed, back to the bar from the grid.
    press(.down, wait: 1.5); snap("from-bar")
    press(.left, wait: 1.0)
    for _ in 0..<10 { press(.down, wait: 0.35) }
    for _ in 0..<6 { press(.up, wait: 0.35) }
    Thread.sleep(forTimeInterval: 1.5); snap("fast-walk")
    press(.right, wait: 1.5); press(.down, 3, wait: 0.9); snap("grid-down")
    for i in 0..<10 {
      press(.up, wait: 1.1); snap("grid-up-\(i)")
      if tabBarFocused(in: app) { break }
    }
    Thread.sleep(forTimeInterval: 1.5); snap("bar-settled-2")
    let bar = app.tabBars.firstMatch
    XCTAssertTrue(tabBarFocused(in: app), "grid Up never reached the bar")
    XCTAssertTrue(bar.exists && bar.frame.minY >= -0.5, "tab bar not whole: \(bar.exists ? "\(bar.frame)" : "none")")
    app.terminate()
  }

  /// Down from the tab bar into a Library section the sidebar just switched to must land
  /// on a card, not on the collection view itself (which keeps focus and eats every press).
  func testLibraryDownFromBarAfterSectionSwitch() throws {
    continueAfterFailure = true
    let app = XCUIApplication()
    app.launchArguments += ["-ui-testing", "-KINOPUBForceColorScheme", "dark",
                            "-KINOPUBLibraryFixture", "YES", "-KINOPUBFixtureInTabs", "YES"]
    app.launch()
    let page = app.collectionViews["kinopub.page.library"]
    XCTAssertTrue(page.waitForExistence(timeout: 30), "no Library page")
    Thread.sleep(forTimeInterval: 2)
    func press(_ b: XCUIRemote.Button, _ n: Int = 1, wait: TimeInterval = 1.2) {
      for _ in 0..<n { XCUIRemote.shared.press(b); Thread.sleep(forTimeInterval: wait) }
    }
    func collectionFocused() -> Bool { page.exists && page.hasFocus }
    var step = 0
    func snap(_ name: String) {
      step += 1
      print("LIBRARY-BAR \(step) \(name) barFocused \(tabBarFocused(in: app)) collectionFocused \(collectionFocused()) focus \(libFocus(app))")
      try? shoot(app, name: String(format: "lib4-%02d-%@", step, name))
    }
    if tabBarFocused(in: app) { press(.down, wait: 1.5) }
    snap("start")
    func focusedRowID() -> String? {
      let hit = app.descendants(matching: .any).matching(
        NSPredicate(format: "identifier BEGINSWITH %@ AND hasFocus == true", "kinopub.library.section.")).firstMatch
      return hit.exists ? String(hit.identifier.dropFirst("kinopub.library.section.".count)) : nil
    }
    for round in 1...2 {
      press(.left)
      for _ in 0..<8 where focusedRowID() != "watchlist" { press(.up, wait: 0.8) }
      press(.down, wait: 2.5); press(.up, wait: 2.5); snap("r\(round)-switched")
      XCTAssertEqual(focusedRowID(), "watchlist")
      press(.up, wait: 1.5); snap("r\(round)-bar")
      XCTAssertTrue(tabBarFocused(in: app), "round \(round): Up from Subscriptions did not reach the bar")
      press(.down, wait: 1.5); snap("r\(round)-down")
      XCTAssertFalse(collectionFocused(), "round \(round): Down from the bar focused the collection view itself")
      XCTAssertTrue(page.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch.exists,
                    "round \(round): no card focused after Down: \(libFocus(app))")
      press(.up, wait: 1.5); snap("r\(round)-up-again")
      XCTAssertTrue(tabBarFocused(in: app), "round \(round): Up did not go back to the bar: \(libFocus(app))")
      press(.down, wait: 1.5)
    }
    app.terminate()
  }

  private func libFocus(_ app: XCUIApplication) -> String {
    let f = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
    return f.exists ? "\(f.elementType.rawValue) id=\(f.identifier) label=\(f.label.prefix(40)) \(f.frame)" : "none"
  }

  private func focusHeroDetails(in app: XCUIApplication) throws {
    let details = app.buttons["kinopub.hero.details"]
    for _ in 0..<10 where !details.hasFocus {
      // A signed-in launch can open on What's New; its Done takes focus.
      let done = app.buttons.matching(NSPredicate(format: "hasFocus == true AND label IN %@", ["Done", "Готово"])).firstMatch
      if done.exists {
        XCUIRemote.shared.press(.select)
        Thread.sleep(forTimeInterval: 1.5)
        continue
      }
      let heroFocused = app.buttons.matching(
        NSPredicate(format: "identifier BEGINSWITH %@ AND hasFocus == true", "kinopub.hero.")
      ).firstMatch
      if heroFocused.exists {
        // Play · «Подробнее» · Bookmark · Next.
        XCUIRemote.shared.press(heroFocused.identifier == "kinopub.hero.play" ? .right : .left)
      } else {
        XCUIRemote.shared.press(.down)
      }
      Thread.sleep(forTimeInterval: 0.8)
    }
    XCTAssertTrue(details.hasFocus, "never reached «Подробнее»\n\(focusDescription(app))")
  }

  /// The real bar (not a leftover snapshot) in the accessibility tree and inside the
  /// screen. Not `isHittable`: over a pushed page the stray bar is drawn yet reports
  /// not hittable, while a hidden bar leaves the tree.
  private func tabBarOnScreen(in app: XCUIApplication) -> Bool {
    let bar = app.tabBars.firstMatch
    guard bar.exists else { return false }
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
