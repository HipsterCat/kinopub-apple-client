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

  /// Play → the strip shows on Info → Up onto the strip → Right onto Up Next, Right onto the season playing,
  /// each shot as it is selected and again with a tile focused. AVKit's tab cells carry no
  /// labels in the accessibility tree (tvOS 27.2), so the walk is by key and the shots say
  /// which tab is which. Every tab's content is the same height, so the strip — the panel is
  /// bottom-anchored — never moves.
  func testTabsOfASeriesEpisode() throws {
    try openPlayer()
    let strip = app.collectionViews["AVInfoMenuCollection"]
    try shoot("player-tabs-0-info")
    let stripY = strip.frame.minY
    for (index, name) in ["upnext", "season"].enumerated() {
      XCUIRemote.shared.press(.right)
      Thread.sleep(forTimeInterval: 2.5)
      try shoot("player-tabs-\(index + 1)-\(name)")
      XCTAssertTrue(strip.exists, "\(name): the strip is gone")
      XCTAssertEqual(strip.frame.minY, stripY, accuracy: 1,
                     "\(name) moved the strip from \(stripY) to \(strip.frame.minY)")
      XCUIRemote.shared.press(.down)
      Thread.sleep(forTimeInterval: 1.5)
      try shoot("player-tabs-\(index + 1)-\(name)-focused")
      XCUIRemote.shared.press(.up)
      Thread.sleep(forTimeInterval: 1.5)
    }
    // Up from the strip: the transport bar, its title view and its buttons — Picture in
    // Picture among them.
    XCUIRemote.shared.press(.up)
    Thread.sleep(forTimeInterval: 2)
    try shoot("player-tabs-3-transport")
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
    // The first Down may show only the transport bar, the strip folded under it near the
    // bottom (tvOS 26.5); the next opens Info and lifts the strip, focus on its «Info» pill.
    for _ in 0..<4 where strip.frame.minY > app.frame.height * 0.75 {
      XCUIRemote.shared.press(.down)
      Thread.sleep(forTimeInterval: 2)
    }
    XCTAssertLessThan(strip.frame.minY, app.frame.height * 0.75, "Info never opened")
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
