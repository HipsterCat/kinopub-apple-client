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

    // The count of reviews: Select opens the page where they are read, and one of them reads whole.
    XCTAssertTrue(seek(.right, until: "kinopub.reviews", limit: 8), focusedDescription)
    XCUIRemote.shared.press(.select); Thread.sleep(forTimeInterval: 2.0)
    XCTAssertTrue(app.collectionViews["kinopub.page.reviews"].waitForExistence(timeout: 10), "no page of reviews")
    try shoot("select-reviews-page")
    XCUIRemote.shared.press(.select); Thread.sleep(forTimeInterval: 1.0)
    try shoot("select-review")
    XCUIRemote.shared.press(.menu); Thread.sleep(forTimeInterval: 1.5)   // closes the review
    XCUIRemote.shared.press(.menu); Thread.sleep(forTimeInterval: 1.5)   // back to the title

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
    XCTAssertTrue(seek(.down, until: "kinopub.gallery", limit: 6) || focusedDescription.contains("kinopub.fact"),
                  "never reached the stills and facts: \(focusedDescription)")
    XCTAssertTrue(seek(.right, until: "kinopub.fact.fact.0", limit: 8), focusedDescription)
    XCUIRemote.shared.press(.select)
    // While the popup is up (or coming up) the page is out of the accessibility tree, and
    // asking what has focus then fails the test on a slow runner, not the page. Wait it out.
    Thread.sleep(forTimeInterval: 2.0)
    XCUIRemote.shared.press(.menu)
    let back = factHasFocus.waitForExistence(timeout: 10)
    try shoot("popup-closed")
    XCTAssertTrue(back, "focus did not come back: \(focusedDescription)")
  }

  private var factHasFocus: XCUIElement {
    app.descendants(matching: .any)
      .matching(NSPredicate(format: "identifier BEGINSWITH %@ AND hasFocus == true", "kinopub.fact"))
      .firstMatch
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

  /// The season line of a series kino.pub has three seasons of: «Сезон», pills 1 2 3, then «4–7»
  /// with a lock (TMDB has them, kino.pub does not) and «8» with a clock (announced). Focus
  /// always comes to the *selected* pill — Down from the hero, Up from an episode — never the
  /// one nearest in x. Right across every pill selects each and moves the rail.
  func testSeasonLineWalksEveryKindOfPill() throws {
    launch("seasonStrip")
    try waitForHeroFocus()
    // Opens on season 3 (the first unwatched episode); Down from the hero must land there, not on 1.
    XCUIRemote.shared.press(.down)
    Thread.sleep(forTimeInterval: 1.4)
    try shoot("seasons-00-down-from-hero")
    note("seasons down from hero")
    XCTAssertTrue(focusedLabel.hasPrefix("Сезон 3"), "Down from the hero landed on «\(focusedLabel)», not the selected season 3")

    XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Сезоны 4–7")).firstMatch.exists,
                  "no joined pill for seasons 4–7")
    XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Сезон 8")).firstMatch.exists,
                  "no pill for the announced season 8")
    XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Сезон 5")).firstMatch.exists,
                   "season 5 has a pill of its own inside the run")

    for step in 1...2 {
      XCUIRemote.shared.press(.right)
      Thread.sleep(forTimeInterval: 1.3)
      try shoot(String(format: "seasons-%02d-right", step))
      note("seasons right \(step)")
    }
    XCTAssertTrue(focusedLabel.hasPrefix("Сезон 8"), "two Rights from 3 did not reach 8: «\(focusedLabel)»")

    // Into the rail and sideways, then back up: the selected pill, whichever is nearest.
    XCUIRemote.shared.press(.down)
    Thread.sleep(forTimeInterval: 1.3)
    try shoot("seasons-03-into-the-rail")
    note("seasons into the rail")
    for _ in 1...2 {
      XCUIRemote.shared.press(.right)
      Thread.sleep(forTimeInterval: 1.0)
    }
    try shoot("seasons-04-rail-right")
    note("seasons in the rail, right")
    XCUIRemote.shared.press(.up)
    Thread.sleep(forTimeInterval: 1.3)
    try shoot("seasons-05-back-up")
    note("seasons back up")
    XCTAssertTrue(focusedLabel.hasPrefix("Сезон"), "Up from the rail left the strip: «\(focusedLabel)»")
    XCTAssertTrue(focusedIsSelected, "Up landed on «\(focusedLabel)», which is not the selected pill")

    // The case geometry gets wrong: standing on S3E3 (x ≈ 880) the nearest pills are «4–7» and
    // «8», but season 3 is the selected one, far to the left.
    XCUIRemote.shared.press(.down)
    Thread.sleep(forTimeInterval: 1.2)
    XCUIRemote.shared.press(.right)
    Thread.sleep(forTimeInterval: 1.0)
    note("seasons on an episode of season 3")
    XCUIRemote.shared.press(.up)
    Thread.sleep(forTimeInterval: 1.3)
    try shoot("seasons-06-up-to-the-selected-far-left")
    note("seasons up to the selected pill")
    XCTAssertTrue(focusedLabel.hasPrefix("Сезон 3"), "Up from an episode of season 3 landed on «\(focusedLabel)»")
  }

  /// One season is not a choice: the line still stands above the rail and reads «Сезон 1», with
  /// no pill to press — so Down from the hero lands on an episode, never on an empty stop.
  func testSeasonLineOfAOneSeasonShowIsJustTheWord() throws {
    launch("rewatch")
    try waitForHeroFocus()
    XCUIRemote.shared.press(.down)
    Thread.sleep(forTimeInterval: 1.4)
    try shoot("seasons-one-season")
    note("one season, down from hero")
    XCTAssertTrue(app.staticTexts["Сезон 1"].exists, "the one-season line does not read «Сезон 1»")
    XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Сезон")).firstMatch.exists,
                   "a one-season show has a season pill to press")
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

  /// Posters in a strip, the way "Similar" is drawn: genre | lead | director under one heading.
  /// Right from a group's last cover is the next group's first, the row scrolls as one, and a
  /// group still in flight is skeleton covers that focus passes over.
  func testAStripOfPostersMovesFromOneGroupToTheNext() throws {
    app = XCUIApplication()
    app.launchArguments += ["-ui-testing", "-KINOPUBTemplatesGallery", "-KINOPUBForceColorScheme", "dark",
                            "-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"]
    app.launch()
    XCTAssertTrue(app.collectionViews["kinopub.page.templates"].waitForExistence(timeout: 30))
    Thread.sleep(forTimeInterval: 3.0)
    XCTAssertTrue(seek(.down, until: "kinopub.poster.2101", limit: 40), focusedDescription)
    Thread.sleep(forTimeInterval: 1.2)
    try shoot("posters-strip-first-group")

    // Three covers in the first group, then the second group's first.
    XCTAssertTrue(seek(.right, until: "kinopub.poster.2201", limit: 5), focusedDescription)
    Thread.sleep(forTimeInterval: 1.2)
    try shoot("posters-strip-second-group")
    XCTAssertTrue(seek(.left, until: "kinopub.poster.2103", limit: 3), "Left comes back: \(focusedDescription)")
  }

  /// The detail page's own Similar: one row, three groups — the same actors, this director,
  /// then alike by genre — and Right past a group's last cover is the next group's first.
  func testFilmSimilarIsOneRowOfGroupsOfCovers() throws {
    launch("film")
    try waitForHeroFocus()
    XCTAssertTrue(seek(.down, until: "kinopub.poster.9902", limit: 6), focusedDescription)
    Thread.sleep(forTimeInterval: 1.2)
    try shoot("film-similar-first")
    XCTAssertTrue(app.staticTexts["Похожие"].exists, "the heading of the row")
    XCTAssertTrue(app.staticTexts["Эти же актёры"].exists, "the first group's subheading")
    XCTAssertTrue(seek(.right, until: "kinopub.poster.9903", limit: 12),
                  "Right never left the actors' group for the director's: \(focusedDescription)")
    Thread.sleep(forTimeInterval: 1.2)
    try shoot("film-similar-director")
    XCTAssertTrue(app.staticTexts["От этого режиссёра"].exists, "the director group's subheading")
    XCTAssertTrue(seek(.right, until: "kinopub.poster.9901", limit: 12),
                  "Right never left the director's group for the genre one: \(focusedDescription)")
    Thread.sleep(forTimeInterval: 1.2)
    try shoot("film-similar-genres")
    XCTAssertTrue(app.staticTexts["Фантастика, боевик, приключения"].exists, "the genre group's subheading")
  }

  /// Two directors open the one row of people, the cast follows them, and the cast comes in the
  /// order of who matters, not the order kino.pub listed them.
  func testSeveralDirectorsShareTheRowAndTheCastIsRanked() throws {
    launch("filmCrew")
    try waitForHeroFocus()
    XCUIRemote.shared.press(.down)   // first row: the scores
    Thread.sleep(forTimeInterval: 1.2)
    XCUIRemote.shared.press(.down)   // the people: the first director
    Thread.sleep(forTimeInterval: 1.4)
    XCTAssertTrue(focusedDescription.contains("kinopub.card.person.director:"), focusedDescription)
    try shoot("crew-directors")
    XCTAssertTrue(seek(.right, until: "kinopub.card.person.actor:", limit: 4), focusedDescription)
    Thread.sleep(forTimeInterval: 1.2)
    XCTAssertTrue(focusedDescription.contains("Крис Эванс") || focusedDescription.contains("Роберт Дауни"),
                  "a star first, not the bit part kino.pub lists first: \(focusedDescription)")
    try shoot("crew-cast")
  }

  /// The table at the bottom takes focus only where Select does something — Audio and Subtitles —
  /// and never as a whole column: Down from Audio is Subtitles; a resolution or a type is text, and
  /// Select on Audio reads every language.
  func testTheTableTakesFocusOnlyWhereSelectDoesSomething() throws {
    launch("film")
    try waitForHeroFocus()
    XCTAssertTrue(seek(.down, until: "kinopub.spec.audio", limit: 12), focusedDescription)
    Thread.sleep(forTimeInterval: 1.2)
    try shoot("table-audio")
    XCUIRemote.shared.press(.down); Thread.sleep(forTimeInterval: 1.0)
    XCTAssertTrue(focusedDescription.contains("kinopub.spec.subtitles"), focusedDescription)
    XCUIRemote.shared.press(.right); Thread.sleep(forTimeInterval: 1.0)
    XCTAssertFalse(focusedDescription.contains("kinopub.spec.resolution")
                   || focusedDescription.contains("kinopub.spec.type"), "text took focus: \(focusedDescription)")
    XCTAssertTrue(seek(.up, until: "kinopub.spec.audio", limit: 3), focusedDescription)
    XCUIRemote.shared.press(.select); Thread.sleep(forTimeInterval: 1.5)
    try shoot("table-audio-popup")
    XCUIRemote.shared.press(.menu); Thread.sleep(forTimeInterval: 1.5)
    XCTAssertTrue(focusedDescription.contains("kinopub.spec.audio"), "focus comes back to the card: \(focusedDescription)")
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
    let left = app.staticTexts["2 серии"]
    XCTAssertTrue(left.waitForExistence(timeout: 30), "no line saying two episodes are left")
    // 28 of 28 watched: nothing to say, and no other line in its place.
    XCTAssertFalse(app.staticTexts["0 серий"].exists)
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

  private var focusedElement: XCUIElement {
    app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
  }

  private var focusedLabel: String { focusedElement.label }

  private var focusedIsSelected: Bool { focusedElement.isSelected }

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
