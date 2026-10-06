#if os(tvOS)
//
//  TVDetailLayoutUITests.swift
//  KinoPubAppleClientUITests
//
//  The sections under the detail hero, walked with the remote on the DEBUG `film`
//  fixture (`-KINOPUBDetailFixture film`, see `DetailFixture`): no session, local
//  artwork, every row populated. Down from Play lands on the first row and the walk
//  goes row by row, then sideways through the two-column rows — a screenshot and the
//  focused element at every stop, so the order and the composition can be read off the
//  result and so a focus dead end shows up as a stop that never moves.
//
//  Screenshots go to the result and to /tmp/kinopub-detail-shots/layout-*.png; the
//  focus log to /tmp/kinopub-detail-shots/layout-focus.txt.
//

import XCTest

final class TVDetailLayoutUITests: XCTestCase {
  private var app: XCUIApplication!
  private var log: [String] = []

  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  override func tearDownWithError() throws {
    let dir = URL(fileURLWithPath: "/tmp/kinopub-detail-shots", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try log.joined(separator: "\n").write(to: dir.appendingPathComponent("layout-focus.txt"),
                                          atomically: true, encoding: .utf8)
  }

  /// Down through every row, then Right through each two-column row.
  func testFilmRowsInOrder() throws {
    launch("film")
    try waitForHeroFocus()
    try shoot("00-open")

    // Down: one press per row, the page scrolls with focus.
    for step in 1...10 {
      XCUIRemote.shared.press(.down)
      Thread.sleep(forTimeInterval: 1.1)
      try shoot(String(format: "down-%02d", step))
      note("down \(step)")
    }
  }

  /// Right along the first rows: the strip moves as one and focus crosses the group gap.
  func testFilmStripsMoveSideways() throws {
    launch("film")
    try waitForHeroFocus()
    XCUIRemote.shared.press(.down)
    Thread.sleep(forTimeInterval: 1.2)
    try shoot("strip-00")
    note("strip start")
    for step in 1...9 {
      XCUIRemote.shared.press(.right)
      Thread.sleep(forTimeInterval: 0.9)
      try shoot(String(format: "strip-right-%02d", step))
      note("right \(step)")
    }
  }

  /// Up from the deepest row, all the way back: every row on the way, then the hero — one of
  /// its controls, whichever the engine picks: it goes by where the card above was, and the
  /// bookmark button sits over the second score as often as Play sits over the first.
  func testFilmUpwardsReturnsToTheHero() throws {
    launch("film")
    try waitForHeroFocus()
    for _ in 1...9 { XCUIRemote.shared.press(.down); Thread.sleep(forTimeInterval: 0.9) }
    note("bottom")
    XCTAssertTrue(detailPageHasFocus, "the walk down never reached the sections: \(focusedDescription)")
    for step in 1...10 {
      XCUIRemote.shared.press(.up)
      Thread.sleep(forTimeInterval: 0.9)
      note("up \(step)")
      if !detailPageHasFocus { break }
    }
    try shoot("up-end")
    XCTAssertFalse(detailPageHasFocus, "Up never got out of the sections: \(focusedDescription)")
    XCTAssertFalse(focusedDescription == "nothing", "focus was lost on the way up")
  }

  /// What Select does on each kind of card, one after another. The remote moves until the
  /// card it wants has focus, so the walk does not depend on how many cards fit a screen.
  func testFilmSelectingCards() throws {
    launch("film")
    try waitForHeroFocus()
    XCUIRemote.shared.press(.down); Thread.sleep(forTimeInterval: 1.2)

    // kino.pub's own score: Select offers a vote.
    XCTAssertTrue(seek(.right, until: "kinopub.rating.KinoPub", limit: 6), focusedDescription)
    XCUIRemote.shared.press(.select); Thread.sleep(forTimeInterval: 1.0)
    try shoot("select-vote")
    XCUIRemote.shared.press(.menu); Thread.sleep(forTimeInterval: 1.5)

    // A review: Select reads it in full.
    XCTAssertTrue(seek(.right, until: "kinopub.review.1", limit: 8), focusedDescription)
    XCUIRemote.shared.press(.select); Thread.sleep(forTimeInterval: 1.0)
    try shoot("select-review")
    XCUIRemote.shared.press(.menu); Thread.sleep(forTimeInterval: 1.5)

    // The stills: Select opens the gallery, Right pages, Menu closes it. Down lands on
    // whatever is under the review, so go to the row and then left along it.
    XCTAssertTrue(seek(.down, until: "kinopub.fact", limit: 5), focusedDescription)
    XCTAssertTrue(seek(.left, until: "kinopub.gallery", limit: 6), focusedDescription)
    XCUIRemote.shared.press(.select); Thread.sleep(forTimeInterval: 1.5)
    try shoot("select-gallery-0")
    XCUIRemote.shared.press(.right); Thread.sleep(forTimeInterval: 1.2)
    try shoot("select-gallery-1")
    XCUIRemote.shared.press(.menu); Thread.sleep(forTimeInterval: 1.5)
    note("after gallery")

    // A spoiler shows itself in place; a plain fact opens its text.
    XCTAssertTrue(seek(.right, until: "kinopub.fact.fact.2", limit: 6), focusedDescription)
    try shoot("select-spoiler-hidden")
    XCUIRemote.shared.press(.select); Thread.sleep(forTimeInterval: 1.0)
    try shoot("select-spoiler-shown")
    XCUIRemote.shared.press(.select); Thread.sleep(forTimeInterval: 1.0)
    try shoot("select-fact-popup")
    XCUIRemote.shared.press(.menu); Thread.sleep(forTimeInterval: 1.5)
  }

  /// Where focus is after a popup closes: it must come back to the card that opened it.
  func testFocusReturnsAfterPopup() throws {
    launch("film")
    try waitForHeroFocus()
    XCUIRemote.shared.press(.down); Thread.sleep(forTimeInterval: 1.2)
    step(.right, times: 4)
    note("review focused")
    XCUIRemote.shared.press(.select); Thread.sleep(forTimeInterval: 1.2)
    note("popup open")
    XCUIRemote.shared.press(.menu)
    for seconds in [0.4, 1.0, 2.0] {
      Thread.sleep(forTimeInterval: seconds)
      note("popup closed +\(seconds)")
    }
    try shoot("popup-closed")
    XCTAssertTrue(focusedDescription.contains("kinopub.review"), "focus did not come back: \(focusedDescription)")
  }

  /// A series under the same page: the seasons rail stays where it was, the new sections follow it.
  func testSeriesKeepsItsRailAboveTheNewSections() throws {
    launch("awaiting")
    try waitForHeroFocus()
    try shoot("series-00-open")
    for step in 1...6 {
      XCUIRemote.shared.press(.down)
      Thread.sleep(forTimeInterval: 1.1)
      try shoot(String(format: "series-down-%02d", step))
      note("series down \(step)")
    }
  }

  /// The section templates page carries the strips the detail page is made of — scores and
  /// reviews, stills and facts, the specification columns — drawn without a session.
  /// Down from the banner reaches each family of card; a shot at each first arrival.
  func testTemplatesGalleryStripsAreReachable() throws {
    app = XCUIApplication()
    app.launchArguments += ["-ui-testing", "-KINOPUBTemplatesGallery", "-KINOPUBForceColorScheme", "dark",
                            "-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"]
    app.launch()
    XCTAssertTrue(app.collectionViews["kinopub.page.templates"].waitForExistence(timeout: 30))

    var wanted: Set<String> = ["kinopub.rating.", "kinopub.gallery.", "kinopub.spec."]
    for step in 1...30 where !wanted.isEmpty {
      XCUIRemote.shared.press(.down)
      Thread.sleep(forTimeInterval: 0.9)
      let focus = focusedDescription
      if let family = wanted.first(where: { focus.contains($0) }) {
        wanted.remove(family)
        try shoot("templates-\(family.dropFirst("kinopub.".count).dropLast())")
        note("gallery \(step) \(family)")
      }
    }
    XCTAssertTrue(wanted.isEmpty, "never reached \(wanted.sorted()) going down the templates page")
  }

  /// A group's title stays on the page's side inset while any of the group is on screen —
  /// "Ratings" does not slide off to the left with its first card.
  func testAGroupTitleStaysOnScreenWhileItsGroupScrolls() throws {
    launch("film")
    try waitForHeroFocus()
    XCUIRemote.shared.press(.down)
    Thread.sleep(forTimeInterval: 1.4)
    let title = app.staticTexts["Оценки"]
    XCTAssertTrue(title.waitForExistence(timeout: 5), "the Ratings title is not on screen")
    XCTAssertEqual(title.frame.minX, 80, accuracy: 6, "at rest it is on the first card's edge")
    let imdb = app.descendants(matching: .any).matching(identifier: "kinopub.rating.IMDb").firstMatch
    XCTAssertTrue(imdb.exists)

    // Right, past the scores and into the reviews: the row scrolls, the first card goes.
    XCTAssertTrue(seek(.right, until: "kinopub.review.2", limit: 10), focusedDescription)
    Thread.sleep(forTimeInterval: 1.2)
    try shoot("sticky-title")
    XCTAssertTrue(!imdb.exists || imdb.frame.maxX < 80, "the first score is still on screen: \(imdb.frame)")
    XCTAssertTrue(title.exists, "the title went off with its first card")
    XCTAssertEqual(title.frame.minX, 80, accuracy: 6, "it is held on the page's side inset")
  }

  /// Two directors are a row of their own, the cast the row under it, and the cast comes
  /// in the order of who matters, not the order kino.pub listed them.
  func testSeveralDirectorsAreARowAndTheCastIsRanked() throws {
    launch("filmCrew")
    try waitForHeroFocus()
    XCUIRemote.shared.press(.down)   // first row: the scores
    Thread.sleep(forTimeInterval: 1.2)
    XCUIRemote.shared.press(.down)   // the directors
    Thread.sleep(forTimeInterval: 1.4)
    XCTAssertTrue(focusedDescription.contains("kinopub.card.person.director:"), focusedDescription)
    try shoot("crew-directors")
    XCUIRemote.shared.press(.down)   // the cast, under them
    Thread.sleep(forTimeInterval: 1.4)
    XCTAssertTrue(focusedDescription.contains("kinopub.card.person.actor:"), focusedDescription)
    XCTAssertTrue(focusedDescription.contains("Крис Эванс") || focusedDescription.contains("Роберт Дауни"),
                  "a star first, not the bit part kino.pub lists first: \(focusedDescription)")
    try shoot("crew-cast")
  }




  // MARK: - Grids

  /// A grid of captioned covers, scrolled forty rows down (the gallery's catalog has twenty, so
  /// to its end) and eight back up: every cover is one size and sits on its row, wherever it is
  /// by then. (A system footer collapsed in a third of
  /// them: no year, art 37 pt taller than its neighbours.) The templates gallery's catalog
  /// has 120 covers, a year for four in five and "episodes left" for one in seven.
  func testAGridScrolledFarKeepsEveryCoverTheSame() throws {
    app = XCUIApplication()
    app.launchArguments += ["-ui-testing", "-KINOPUBTemplatesGallery", "-KINOPUBForceColorScheme", "dark",
                            "-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"]
    app.launch()
    XCTAssertTrue(app.collectionViews["kinopub.page.templates"].waitForExistence(timeout: 30))
    Thread.sleep(forTimeInterval: 3.0)
    XCTAssertTrue(seek(.down, until: "kinopub.poster.30", limit: 60), focusedDescription)
    try shoot("grid-start")
    step(.down, times: 40)
    step(.up, times: 8)
    Thread.sleep(forTimeInterval: 2.0)
    try shoot("grid-scrolled")

    // A cover is two elements with one id — the cell and the lockup inside it — each of its own height.
    let covers = app.descendants(matching: .any)
      .matching(NSPredicate(format: "identifier BEGINSWITH %@", "kinopub.poster.3"))
      .allElementsBoundByIndex
      .map { (type: $0.elementType.rawValue, frame: $0.frame) }
      .filter { $0.frame.height > 0 && $0.frame.maxY > 0 && $0.frame.minY < 1080 }
    XCTAssertGreaterThan(covers.count, 12, "a screenful of covers")
    for (type, kind) in Dictionary(grouping: covers, by: { $0.type }) {
      let heights = Set(kind.map { Int($0.frame.height.rounded()) })
      XCTAssertEqual(heights.count, 1, "element type \(type): covers of different heights \(heights.sorted())")
      // Same row, same top.
      for row in Dictionary(grouping: kind, by: { Int(($0.frame.minY / 100).rounded()) }).values {
        XCTAssertEqual(Set(row.map { Int($0.frame.minY.rounded()) }).count, 1,
                       "element type \(type): a row whose covers do not line up: \(row.map { $0.frame })")
      }
    }
  }

  /// The Library's Subscriptions — the real Library page on a stand-in API: under a series'
  /// title, how many of its episodes are left.
  func testLibraryFollowingSaysHowManyEpisodesAreLeft() throws {
    app = XCUIApplication()
    app.launchArguments += ["-ui-testing", "-KINOPUBLibraryFixture", "YES", "-KINOPUBForceColorScheme", "dark",
                            "-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"]
    app.launch()
    XCTAssertTrue(app.collectionViews["kinopub.page.library"].waitForExistence(timeout: 30))
    // 18 episodes, 16 watched.
    let left = app.staticTexts["Ещё 2 серии"]
    XCTAssertTrue(left.waitForExistence(timeout: 30), "no line saying two episodes are left")
    // 28 of 28 watched: nothing to say, and no other line in its place.
    XCTAssertFalse(app.staticTexts["Ещё 0 серий"].exists)
    Thread.sleep(forTimeInterval: 2.0)
    try shoot("library-following")
    XCUIRemote.shared.press(.right)
    Thread.sleep(forTimeInterval: 1.5)
    try shoot("library-following-focused")
  }


  // MARK: - Helpers

  /// Focus is on a card, a pill or a poster of the sections under the hero.
  private var detailPageHasFocus: Bool {
    app.collectionViews["kinopub.page.detail"].descendants(matching: .any)
      .matching(NSPredicate(format: "hasFocus == true"))
      .firstMatch.exists
  }

  private var heroHasFocus: Bool {
    app.descendants(matching: .any)
      .matching(NSPredicate(format: "identifier BEGINSWITH %@ AND hasFocus == true", "kinopub.hero."))
      .firstMatch.exists
  }

  /// Presses `button` until the focused element's identifier contains `fragment`.
  private func seek(_ button: XCUIRemote.Button, until fragment: String, limit: Int) -> Bool {
    for _ in 0..<limit {
      if focusedDescription.contains(fragment) { return true }
      XCUIRemote.shared.press(button)
      Thread.sleep(forTimeInterval: 0.9)
    }
    return focusedDescription.contains(fragment)
  }

  private func step(_ button: XCUIRemote.Button, times: Int) {
    for _ in 0..<times {
      XCUIRemote.shared.press(button)
      Thread.sleep(forTimeInterval: 0.9)
    }
  }

  private func launch(_ fixture: String, extra: [String] = []) {
    app = XCUIApplication()
    app.launchArguments += extra
    app.launchArguments += ["-ui-testing",
                            "-KINOPUBDetailFixture", fixture,
                            "-KINOPUBForceColorScheme", "dark",
                            "-AppleLanguages", "(ru)",
                            "-AppleLocale", "ru_RU",
                            "-UIFocusLoggingEnabled", "YES"]
    app.launch()
  }

  private struct NoFocus: Error {}

  private func waitForHeroFocus() throws {
    let play = app.descendants(matching: .any)
      .matching(NSPredicate(format: "identifier BEGINSWITH %@ AND hasFocus == true", "kinopub.hero."))
      .firstMatch
    guard play.waitForExistence(timeout: 30) else {
      try shoot("no-focus")
      XCTFail("the hero never took focus — focused: \(focusedDescription)")
      throw NoFocus()
    }
    Thread.sleep(forTimeInterval: 0.8)
  }

  private var focusedDescription: String {
    let focused = app.descendants(matching: .any)
      .matching(NSPredicate(format: "hasFocus == true"))
      .allElementsBoundByIndex
    guard !focused.isEmpty else { return "nothing" }
    return focused.map { "\($0.elementType.rawValue) '\($0.identifier)' '\($0.label)' \($0.frame)" }
      .joined(separator: " | ")
  }

  private func note(_ moment: String) {
    log.append("\(moment): \(focusedDescription)")
  }

  private func shoot(_ name: String) throws {
    let screenshot = app.screenshot()
    let attachment = XCTAttachment(screenshot: screenshot)
    attachment.name = "layout-\(name)"
    attachment.lifetime = .keepAlways
    add(attachment)
    let dir = URL(fileURLWithPath: "/tmp/kinopub-detail-shots", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try screenshot.pngRepresentation.write(to: dir.appendingPathComponent("layout-\(name).png"))
  }
}
#endif
