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

  /// The season rail, walked the way Sasha described it (2026-10-11), on a series watched
  /// up to S2E3 — kino.pub has seasons 1–3, TMDB adds «4–7» (a lock) and «8» (a clock):
  /// - Down from the hero passes the tabs and lands on S2E4, the episode Play plays, with
  ///   its art on the page margin;
  /// - Up from an episode lands on the *selected* tab, and the rail does not move;
  /// - Left/Right on the tabs selects as it goes and takes the rail to that season;
  /// - Down from the tabs comes back to an episode; Up from an episode of season 3 lands on
  ///   «3» however near «4–7» and «8» are;
  /// - Up from the tabs is the hero's main button, and Down again is the episode you left —
  ///   the rail is where you left it (only reopening the page puts it back on S2E4).
  func testSeasonRailFocusWalk() throws {
    launch("seasonStrip")
    try waitForHeroFocus()
    try shoot("seasons-00-open")

    XCTAssertTrue(seasonTab("4–7").exists, "no joined tab for seasons 4–7")
    XCTAssertTrue(seasonTab("8").exists, "no tab for the announced season 8")
    XCTAssertFalse(seasonTab("5").exists, "season 5 has a tab of its own inside the run")

    let s2e4 = railItem(season: 2, number: 4)
    try move(.down, "seasons-01-down-from-hero")
    XCTAssertTrue(s2e4.hasFocus, "Down from the hero did not land on S2E4: \(focusedDescription)")
    XCTAssertTrue(seasonTab("2").isSelected, "S2E4 has focus but «2» is not the selected tab")
    XCTAssertEqual(s2e4.frame.midX - s2e4.frame.width / 2, TVHIG.sideInset, accuracy: 30,
                   "S2E4 is not on the page margin: \(s2e4.frame)")
    let s2e4MidX = s2e4.frame.midX

    try move(.up, "seasons-02-up-to-the-tab")
    XCTAssertTrue(seasonTab("2").hasFocus, "Up from S2E4 landed on: \(focusedDescription)")
    XCTAssertEqual(s2e4.frame.midX, s2e4MidX, accuracy: 2, "the rail moved when focus went up to the tabs")

    try move(.right, "seasons-03-right-to-3")
    XCTAssertTrue(seasonTab("3").hasFocus && seasonTab("3").isSelected, "Right did not select «3»: \(focusedDescription)")
    let s3e1 = railItem(season: 3, number: 1)
    XCTAssertEqual(s3e1.frame.minX, TVHIG.sideInset, accuracy: 30, "the rail did not go to S3E1: \(s3e1.frame)")

    try move(.right, "seasons-04-right-to-4-7")
    try move(.right, "seasons-05-right-to-8")
    XCTAssertTrue(seasonTab("8").hasFocus, "two Rights from «3» did not reach «8»: \(focusedDescription)")
    try move(.left, "seasons-06-left-to-4-7")
    try move(.left, "seasons-07-left-to-3")
    XCTAssertTrue(seasonTab("3").hasFocus, "back Left did not reach «3»: \(focusedDescription)")

    try move(.down, "seasons-08-down-to-s3e1")
    XCTAssertTrue(s3e1.hasFocus, "Down from «3» did not land on S3E1: \(focusedDescription)")
    try move(.right, "seasons-09-s3e2")
    try move(.right, "seasons-10-s3e3")
    try move(.up, "seasons-11-up-to-3")
    XCTAssertTrue(seasonTab("3").hasFocus, "Up from S3E3 landed on: \(focusedDescription)")

    try move(.down, "seasons-12-down-again")
    let s3e3 = railItem(season: 3, number: 3)
    XCTAssertTrue(s3e3.hasFocus, "Down from the tab did not return to S3E3: \(focusedDescription)")
    let s3e3MidX = s3e3.frame.midX
    try move(.up, "seasons-13-up")
    try move(.up, "seasons-14-up-to-the-hero")
    let main = app.descendants(matching: .any)
      .matching(NSPredicate(format: "identifier IN %@ AND hasFocus == true", ["kinopub.hero.play", "kinopub.hero.follow"]))
      .firstMatch
    XCTAssertTrue(main.exists, "Up from the tabs did not land on the hero's main button: \(focusedDescription)")

    try move(.down, "seasons-15-down-from-hero-again")
    XCTAssertTrue(s3e3.hasFocus, "Down from the hero again did not return to S3E3: \(focusedDescription)")
    XCTAssertEqual(s3e3.frame.midX, s3e3MidX, accuracy: 2, "the rail moved while focus was in the hero")
  }

  /// One season is not a choice: the line still stands above the rail and reads «Сезон 1», with
  /// no tab to press — so Down from the hero lands on an episode, never on an empty stop.
  func testSeasonLineOfAOneSeasonShowIsJustTheWord() throws {
    launch("rewatch")
    try waitForHeroFocus()
    try move(.down, "seasons-one-season")
    XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Сезон 1")).firstMatch.exists,
                  "the one-season line does not read «Сезон 1»")
    XCTAssertFalse(app.descendants(matching: .any)
                     .matching(NSPredicate(format: "identifier BEGINSWITH %@", "kinopub.season.tab.")).firstMatch.exists,
                   "a one-season show has a season tab to press")
    XCTAssertTrue(app.descendants(matching: .any)
                    .matching(NSPredicate(format: "identifier BEGINSWITH %@ AND hasFocus == true", "kinopub.rail.item.")).firstMatch.exists,
                  "Down from the hero did not land on an episode: \(focusedDescription)")
  }

  private enum TVHIG { static let sideInset: CGFloat = 80 }

  private func seasonTab(_ label: String) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: "kinopub.season.tab.\(label)").firstMatch
  }

  /// A rail cell by the fixture's episode id (`DetailFixture.episode`).
  private func railItem(season: Int, number: Int) -> XCUIElement {
    let id = 9_900_008 * 1000 + season * 100 + number
    return app.descendants(matching: .any).matching(identifier: "kinopub.rail.item.\(id)").firstMatch
  }

  private func move(_ button: XCUIRemote.Button, _ shot: String) throws {
    XCUIRemote.shared.press(button)
    Thread.sleep(forTimeInterval: 1.2)
    try shoot(shot)
    note(shot)
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

  /// The picture behind the page is the stack's, not the page's: it stays still at any depth,
  /// and opening another title crossfades it to that title's while the page changes over it.
  /// Back, it crossfades home again. Shots mid-way and settled, both ways.
  /// Under the real tab bar: the backdrop sits behind the tab view, not inside a tab.
  func testTheBackdropCrossfadesBetweenTitles() throws {
    launch("film", extra: ["-KINOPUBFixtureInTabs", "YES"])
    try waitForHeroFocus()
    XCTAssertTrue(seek(.down, until: "kinopub.poster.9902", limit: 6), focusedDescription)
    Thread.sleep(forTimeInterval: 1.2)
    try shoot("backdrop-00-deep")
    XCUIRemote.shared.press(.select)
    Thread.sleep(forTimeInterval: 0.35)
    try shoot("backdrop-01-pushing")
    Thread.sleep(forTimeInterval: 2.5)
    try shoot("backdrop-02-pushed")
    XCUIRemote.shared.press(.menu)
    Thread.sleep(forTimeInterval: 0.15)
    try shoot("backdrop-03-popping")
    Thread.sleep(forTimeInterval: 2.0)
    try shoot("backdrop-04-back")
    // Back to a page that asks for no backdrop: the fade starts with the pop, not after it.
    XCUIRemote.shared.press(.menu)
    Thread.sleep(forTimeInterval: 0.15)
    try shoot("backdrop-05-leaving")
    Thread.sleep(forTimeInterval: 0.35)
    try shoot("backdrop-06-left")
  }

  /// Down from the hero into the sections fades the picture out to the system background —
  /// light in the light appearance, dark in the dark one — and Up into the hero brings it back.
  func testTheDetailsLeaveThePictureInBothAppearances() throws {
    for scheme in ["light", "dark"] {
      launch("film", extra: ["-KINOPUBFixtureInTabs", "YES"], scheme: scheme)
      try waitForHeroFocus()
      try shoot("material-\(scheme)-0-hero")
      XCUIRemote.shared.press(.down)
      Thread.sleep(forTimeInterval: 0.3)
      try shoot("material-\(scheme)-1-fading")
      Thread.sleep(forTimeInterval: 1.0)
      try shoot("material-\(scheme)-2-details")
      step(.down, times: 3)
      try shoot("material-\(scheme)-3-deeper")
      for _ in 0..<8 where !heroHasFocus { XCUIRemote.shared.press(.up); Thread.sleep(forTimeInterval: 0.9) }
      XCTAssertTrue(heroHasFocus, focusedDescription)
      Thread.sleep(forTimeInterval: 1.0)
      try shoot("material-\(scheme)-4-hero-again")
      app.terminate()
    }
  }

  /// Light appearance, the plain way through: a title's hero, its details, and the list it
  /// was opened from — what is behind each of them.
  func testLightAppearanceBehindEveryPage() throws {
    launch("film", extra: ["-KINOPUBFixtureInTabs", "YES"], scheme: "light")
    try waitForHeroFocus()
    Thread.sleep(forTimeInterval: 1.0)
    try shoot("light-1-hero")
    XCUIRemote.shared.press(.down)
    Thread.sleep(forTimeInterval: 1.5)
    try shoot("light-2-details")
    XCUIRemote.shared.press(.menu)
    Thread.sleep(forTimeInterval: 2.0)
    try shoot("light-3-list")
  }

  /// Title → title five deep through Similar, then all the way back: at every depth the
  /// backdrop is that title's (each Similar cover is drawn in its own colour, its name on it).
  func testTheBackdropFollowsTitleAfterTitle() throws {
    launch("film", extra: ["-KINOPUBFixtureInTabs", "YES"])
    try waitForHeroFocus()
    for depth in 1...5 {
      let id = 9_901_000 + depth   // a different cover each time, never the page's own
      XCTAssertTrue(seek(.down, until: "kinopub.poster.", limit: 8), focusedDescription)
      XCTAssertTrue(seek(.right, until: "kinopub.poster.\(id)", limit: 24), focusedDescription)
      XCUIRemote.shared.press(.select)
      Thread.sleep(forTimeInterval: 3.0)
      try shoot("deep-\(depth)-\(id)")
      note("deep \(depth)")
    }
    for step in 1...5 {
      XCUIRemote.shared.press(.menu)
      Thread.sleep(forTimeInterval: 2.0)
      try shoot("deep-back-\(step)")
    }
  }

  /// Two directors open the one row of people; the cast follows them. kino.pub's first
  /// name is the lead even when TMDB billed them as a bit part.
  func testSeveralDirectorsShareTheRowAndTheCastIsRanked() throws {
    launch("filmCrew")
    try waitForHeroFocus()
    XCUIRemote.shared.press(.down)   // first row: the scores
    Thread.sleep(forTimeInterval: 1.2)
    XCUIRemote.shared.press(.down)   // the people: the first director
    Thread.sleep(forTimeInterval: 1.4)
    XCTAssertTrue(focusedDescription.contains("kinopub.card.person.director"), focusedDescription)
    try shoot("crew-directors")
    XCTAssertTrue(seek(.right, until: "kinopub.card.person.actor", limit: 4), focusedDescription)
    Thread.sleep(forTimeInterval: 1.2)
    XCTAssertTrue(focusedDescription.contains("Эпизод Первый")
                    || focusedDescription.contains("Крис Эванс")
                    || focusedDescription.contains("Роберт Дауни"),
                  "an actor follows the directors: \(focusedDescription)")
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
    XCUIRemote.shared.press(.select)
    // While the popup is up (or coming up) the page is out of the accessibility tree, and
    // asking what has focus then fails the test on a slow runner, not the page. Wait it out.
    Thread.sleep(forTimeInterval: 2.0)
    try shoot("table-audio-popup")
    XCUIRemote.shared.press(.menu)
    let back = audioHasFocus.waitForExistence(timeout: 10)
    try shoot("table-audio-closed")
    XCTAssertTrue(back, "focus comes back to the card: \(focusedDescription)")
  }

  private var audioHasFocus: XCUIElement {
    app.descendants(matching: .any)
      .matching(NSPredicate(format: "identifier BEGINSWITH %@ AND hasFocus == true", "kinopub.spec.audio"))
      .firstMatch
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

  private func launch(_ fixture: String, extra: [String] = [], scheme: String = "dark") {
    app = XCUIApplication()
    app.launchArguments += extra
    app.launchArguments += ["-ui-testing",
                            "-KINOPUBDetailFixture", fixture,
                            "-KINOPUBForceColorScheme", scheme,
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
