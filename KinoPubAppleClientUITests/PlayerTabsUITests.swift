//
//  PlayerTabsUITests.swift
//  KinoPubAppleClientUITests
//
//  The tvOS player's Info strip on a fixture series, no session needed:
//  `-KINOPUBDetailFixture seasonStrip` with `-KINOPUBFixtureRealPlayer`, so Play on the
//  hero opens the real `AVPlayerViewController` on Apple's sample stream with the series'
//  episodes behind it. Shots of every tab land in /tmp/kinopub-detail-shots.
//

#if os(tvOS)
import XCTest

final class PlayerTabsUITests: XCTestCase {
  private var app: XCUIApplication!

  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  /// Play → Info opens → Right onto the season playing, Right onto Up Next, each shot as it
  /// is selected and again after Down. Then back to the season after moving one tile on: Down
  /// returns to that tile, not the opening one. AVKit's tab cells carry no labels in the
  /// accessibility tree (tvOS 27.2), so the walk is by key and the shots say which tab is
  /// which; the shots are what to look at. Every tab's content is the same height, so the
  /// strip never moves.
  func testTabsOfASeriesEpisode() throws {
    try openPlayer()
    let strip = app.collectionViews["AVInfoMenuCollection"]
    try shoot("player-tabs-0-info")
    let stripY = strip.frame.minY
    for (index, name) in ["season", "upnext"].enumerated() {
      press(.right)
      try shoot("player-tabs-\(index + 1)-\(name)")
      XCTAssertTrue(strip.exists, "\(name): the strip is gone")
      XCTAssertEqual(strip.frame.minY, stripY, accuracy: 1,
                     "\(name) moved the strip from \(stripY) to \(strip.frame.minY)")
      press(.down)
      try shoot("player-tabs-\(index + 1)-\(name)-focused")
      if name == "season" {
        // One tile on, so coming back has somewhere else to return to.
        press(.right)
      }
      press(.up)
    }
    // Back to the season: Down lands where the remote left it.
    press(.left)
    press(.down)
    try shoot("player-tabs-4-season-again")
    press(.up)
    // Up from the strip: the transport bar, its title view and its buttons — Picture in
    // Picture among them.
    press(.up)
    try shoot("player-tabs-3-transport")
  }

  private func press(_ button: XCUIRemote.Button) {
    XCUIRemote.shared.press(button)
    Thread.sleep(forTimeInterval: 2)
  }

  // MARK: - Helpers

  private func openPlayer() throws {
    app = XCUIApplication()
    app.launchArguments += ["-ui-testing",
                            "-KINOPUBDetailFixture", "seasonStrip",
                            "-KINOPUBFixtureRealPlayer", "YES",
                            "-KINOPUBForceColorScheme", "dark",
                            "-AppleLanguages", "(ru)",
                            "-AppleLocale", "ru_RU"]
    app.launch()
    let play = app.buttons.matching(identifier: "kinopub.hero.play").firstMatch
    XCTAssertTrue(play.waitForExistence(timeout: 30), "the fixture page never painted")
    Thread.sleep(forTimeInterval: 2)
    XCUIRemote.shared.press(.select)
    // The sample stream takes a while to start, slower on tvOS 26.5; until it does AVKit
    // has no Info tab and the walk below would be off by one.
    Thread.sleep(forTimeInterval: 10)

    // AVKit's strip exists only once the stream is up and the controls show.
    let strip = app.collectionViews["AVInfoMenuCollection"]
    let deadline = Date().addingTimeInterval(60)
    while Date() < deadline, !strip.exists {
      XCUIRemote.shared.press(.down)
      Thread.sleep(forTimeInterval: 2)
    }
    XCTAssertTrue(strip.exists, "the player never showed its tabs\n\(app.debugDescription)")
    // The first Down may show only the transport bar, the strip folded under it (tvOS 26.5);
    // Info is open once its own button is there — focus is then on the «Info» pill.
    let goToShow = app.buttons["Перейти к сериалу"]
    for _ in 0..<4 where !goToShow.exists {
      XCUIRemote.shared.press(.down)
      Thread.sleep(forTimeInterval: 2)
    }
    XCTAssertTrue(goToShow.exists, "Info never opened\n\(app.debugDescription)")
    Thread.sleep(forTimeInterval: 1)
  }

  private func shoot(_ name: String) throws {
    let screenshot = app.screenshot()
    let attachment = XCTAttachment(screenshot: screenshot)
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
    let dir = URL(fileURLWithPath: "/tmp/kinopub-detail-shots", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try screenshot.pngRepresentation.write(to: dir.appendingPathComponent("\(name).png"))
  }
}
#endif
