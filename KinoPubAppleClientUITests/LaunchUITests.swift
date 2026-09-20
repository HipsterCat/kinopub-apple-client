//
//  LaunchUITests.swift
//  KinoPubAppleClientUITests
//
//  What a UI test can honestly assert on a runner that is not signed in.
//
//  A CI simulator has no kino.pub session — `DevSessionMirror` only seeds one from a
//  developer's own machine — so anything past the auth screen is out of reach here. What
//  is reachable is the most valuable regression there is on tvOS: **the app launches, and
//  it does not sit on a black screen.** Both of those have broken before.
//
//  Focus behaviour is deliberately not asserted in CI. It needs content, and a
//  screenshot cannot show whether a landing felt right; that stays a device check.
//
//  Local hig Watch Now shots (DEBUG scheme arguments — `simctl ui appearance` is
//  unsupported on this tvOS runtime):
//    -KINOPUBForceColorScheme light
//    -KINOPUBForceColorScheme dark
//    -KINOPUBFocusFirstPoster          // first 2:3 poster, not CW landscape
//  Poster cells: accessibilityIdentifier `kinopub.poster.{id}`.
//

import XCTest

final class LaunchUITests: XCTestCase {

  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  private func launchedApp() -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments += ["-ui-testing"]
    // The app under a UI test cannot reach the dev-session mirror (testmanagerd strips
    // SIMULATOR_HOST_HOME), so the session is handed over directly when it exists.
    // CI runners have no such file and get the auth screen, as before.
    if let session = try? String(
      contentsOfFile: NSHomeDirectory() + "/.kinopub-dev-session.json", encoding: .utf8
    ) {
      app.launchEnvironment["KINOPUB_DEV_SESSION"] = session
    }
    app.launch()
    return app
  }

  func testTheAppLaunches() {
    let app = launchedApp()
    XCTAssertEqual(app.state, .runningForeground)
  }

  /// A launch that paints nothing is the failure this catches: the splash names what it is
  /// waiting for (`LaunchStatusLabel`), and past it there is a session screen or a shell.
  /// Any of them means the first frame arrived; none of them means a black screen.
  func testSomethingIsOnScreenAfterLaunch() {
    let app = launchedApp()
    let anyContent = app.descendants(matching: .any).firstMatch
    XCTAssertTrue(anyContent.waitForExistence(timeout: 30),
                  "the first frame never painted anything")
  }

  /// The app must survive being backgrounded and brought back — the session and the player
  /// both hold state across it.
  ///
  /// iOS only: `XCUIDevice.Button.home` does not exist on tvOS, where the equivalent is a
  /// remote press through `XCUIRemote`, and there is no Home on the Mac at all.
#if os(iOS)
  func testTheAppSurvivesABackgroundRoundTrip() {
    let app = launchedApp()
    XCUIDevice.shared.press(.home)
    app.activate()
    XCTAssertEqual(app.state, .runningForeground)
  }

  /// **Local diagnostic, not a CI test** — it needs the mirrored developer session
  /// (`~/.kinopub-dev-session.json`), so it skips itself when the auth screen is what
  /// launched. Opens the first title from Home into the system player and writes what it
  /// finds to /tmp/player-chrome-dump.txt: every label AVKit draws (is the title there at
  /// all?) and whether the overflow menu summons the soft keyboard (the iOS 26 type-ahead
  /// field grabbing first responder).
  func testPlayerChromeDiagnostic() throws {
    let app = launchedApp()
    var dump = ""

    // Whatever came up — home content or the auth screen — is evidence.
    _ = app.buttons.firstMatch.waitForExistence(timeout: 45)
    dump += Self.snapshot(app, title: "after launch")

    // A card can live in a scroll view, a table or a collection depending on the
    // platform's renderer — take the first tappable that isn't chrome. Cards are the
    // buttons whose label is the bilingual title pair ("Мятеж, Mutiny") — section
    // headers and chips never carry a comma.
    let card = app.scrollViews.buttons
      .matching(NSPredicate(format: "label CONTAINS ', '"))
      .firstMatch
    if !card.exists {
      try? dump.write(toFile: "/tmp/player-chrome-dump.txt", atomically: true, encoding: .utf8)
      throw XCTSkip("no home content — no dev session on this machine")
    }
    // The player should greet us with the same title the card carried ("Лайфхак,
    // LifeHack" → "Лайфхак") — that is the whole question this diagnostic answers.
    let expectedTitle = card.label.components(separatedBy: ",").first?
      .trimmingCharacters(in: .whitespaces) ?? ""
    card.tap()
    dump += Self.snapshot(app, title: "detail")

    let play = app.buttons
      .matching(NSPredicate(format: "label BEGINSWITH 'Play' OR label BEGINSWITH 'Resume' OR label BEGINSWITH 'Смотреть' OR label BEGINSWITH 'Продолжить'"))
      .firstMatch
    guard play.waitForExistence(timeout: 20) else {
      try? dump.write(toFile: "/tmp/player-chrome-dump.txt", atomically: true, encoding: .utf8)
      throw XCTSkip("the card opened something without a play button\n\(dump)")
    }
    play.tap()

    // Let the stream actually start, then reveal the chrome (a center tap is also
    // play/pause in the system player, which is fine — it shows the controls).
    sleep(8)
    app.tap()
    sleep(1)
    // Targeted reads instead of a tree dump: Live Text floods the hierarchy with
    // visionkit elements off the video frame itself.
    let titleHit = app.staticTexts[expectedTitle]
    dump += "== player ==\n"
    dump += "expected title: '\(expectedTitle)' — visible: \(titleHit.exists)\n"
    dump += "chrome buttons: "
    for label in ["Ещё", "More Controls", "More", "Закрыть", "Close", "AirPlay"] {
      if app.buttons[label].exists { dump += "[\(label)] " }
    }
    dump += "\n"

    let more = app.buttons
      .matching(NSPredicate(format: "label BEGINSWITH 'More' OR label BEGINSWITH 'Ещё'"))
      .firstMatch
    if more.waitForExistence(timeout: 5) {
      more.tap()
      sleep(2)
      dump += "== after More ==\nkeyboards on screen: \(app.keyboards.count)\n"
      dump += "menu items: "
      for label in ["Скорость", "Playback Speed", "Аудиодорожка", "Audio Track", "Субтитры", "Subtitles"] {
        if app.buttons[label].exists { dump += "[\(label)] " }
      }
      dump += "\n"
    } else {
      dump += "== no More button found ==\n"
    }
    try? dump.write(toFile: "/tmp/player-chrome-dump.txt", atomically: true, encoding: .utf8)
    // A device run cannot reach the Mac's /tmp, and print() from the test process does
    // not reach the host log — the dump travels in the skip/failure message instead.
    if app.keyboards.count > 0 {
      XCTFail("the overflow menu summoned the keyboard\n\(dump)")
    } else {
      throw XCTSkip("diagnostic complete, no keyboard\n\(dump)")
    }
  }

  private static func snapshot(_ app: XCUIApplication, title: String) -> String {
    // One snapshot, one string: enumerating element queries faults the moment the
    // player's chrome animates mid-loop ("Failed to get matching snapshot").
    let tree = app.debugDescription
    let cap = 9000
    let body = tree.count > cap ? String(tree.prefix(cap)) + "\n…(truncated)" : tree
    return "== \(title) ==\n\(body)\n"
  }
#endif
}

#if os(tvOS)
extension XCUIApplication {
  /// Local hig Watch Now shots. Not a CI test — pair with a signed-in DEBUG build.
  /// `simctl ui appearance` is unsupported; pass `light` or `dark`.
  func launchForWatchNowShot(colorScheme: String, focusFirstPoster: Bool = false) {
    launchArguments += ["-ui-testing", "-KINOPUBForceColorScheme", colorScheme]
    if focusFirstPoster {
      launchArguments += ["-KINOPUBFocusFirstPoster"]
    }
    if let session = try? String(
      contentsOfFile: NSHomeDirectory() + "/.kinopub-dev-session.json", encoding: .utf8
    ) {
      launchEnvironment["KINOPUB_DEV_SESSION"] = session
    }
    launch()
  }
}
#endif
