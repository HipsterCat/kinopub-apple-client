//
//  PlayerUpNextTabUITests.swift
//  KinoPubAppleClientUITests
//
//  The player's Info panel has an **Up Next** tab (`customInfoViewControllers`) whose content is
//  ours. It once grew taller every time it was re-entered — the tab strip crept up the screen
//  while the tiles stayed put, leaving an ever larger gap (seen 2026-09-30).
//
//  The panel is bottom-anchored, so its height shows as the strip's vertical position: a taller
//  tab pushes the «Up Next» button up. This test drives the remote the way the bug was found
//  and asserts the strip never moves.
//
//  Needs a real session and a Continue Watching *episode* with episodes after it, so it skips
//  without ~/.kinopub-dev-session.json — a local check, like `WatchNowHigShotsUITests`.
//

#if os(tvOS)
import XCTest

final class PlayerUpNextTabUITests: XCTestCase {

  override func setUpWithError() throws {
    continueAfterFailure = false
    try XCTSkipUnless(FileManager.default.fileExists(atPath: UITestDevSession.filePath),
                      "no ~/.kinopub-dev-session.json — local player check only")
  }

  /// Open the player → Down (details) → Right (Up Next) → Up (back out) → Down (in again):
  /// the tab's height must not change, however many times that is repeated.
  func testUpNextTabDoesNotGrowWhenReentered() throws {
    let app = XCUIApplication()
    app.launchArguments += ["-ui-testing", "-KINOPUBForceColorScheme", "dark"]
    if let session = UITestDevSession.json {
      app.launchEnvironment["KINOPUB_DEV_SESSION"] = session
    }
    app.launch()

    let remote = XCUIRemote.shared

    // Watch Now opens on its tab pill; one Down lands on the first Continue Watching tile.
    let anyCell = app.descendants(matching: .any).matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "kinopub.poster.")).firstMatch
    XCTAssertTrue(anyCell.waitForExistence(timeout: 90), "Watch Now never painted — no session?")
    // Continue Watching paints after the posters below it; one Down from the tab pill must land
    // on its first tile (a cell with no `kinopub.poster.*` id), not on a poster further down.
    Thread.sleep(forTimeInterval: 10)
    remote.press(.down)
    Thread.sleep(forTimeInterval: 1.5)
    let focusedPoster = app.descendants(matching: .any).matching(
      NSPredicate(format: "identifier BEGINSWITH %@ AND hasFocus == true", "kinopub.poster.")).firstMatch
    XCTAssertFalse(focusedPoster.exists,
                   "Down landed on a poster, not Continue Watching — is the row empty for this account?")
    remote.press(.select)

    // The player: AVKit's tab strip is a collection (`AVInfoMenuCollection`) of cells — Info,
    // then our Up Next — that only exists once the stream is up and the controls are showing,
    // so keep asking for it.
    let strip = app.collectionViews["AVInfoMenuCollection"]
    let info = strip.cells.element(boundBy: 0)
    let upNext = strip.cells.element(boundBy: 1)
    var shown = false
    let deadline = Date().addingTimeInterval(120)
    while Date() < deadline, !shown {
      remote.press(.down)
      Thread.sleep(forTimeInterval: 2)
      shown = strip.exists && upNext.exists
    }
    guard shown else {
      return XCTFail("the player never showed the Info / Up Next tabs — is the first Continue Watching "
                     + "item an episode with episodes after it?\n\(app.debugDescription)")
    }

    // Walk focus to the Up Next tab by state, not by a fixed key count: Down until the strip
    // has focus on Info, then Right onto Up Next, whose content then shows.
    for _ in 0..<10 where !upNext.isSelected {
      remote.press(info.hasFocus ? .right : .down)
      Thread.sleep(forTimeInterval: 1.5)
    }
    XCTAssertTrue(upNext.isSelected, "never reached the Up Next tab\n\(app.debugDescription)")
    let stripY = strip.frame.minY
    let upNextY = upNext.frame.minY
    XCTAssertGreaterThan(stripY, 0)

    for cycle in 1...3 {
      remote.press(.up)        // back out of the tabs
      Thread.sleep(forTimeInterval: 1.5)
      remote.press(.down)      // and into them again
      Thread.sleep(forTimeInterval: 1.5)
      if !strip.exists {       // the controls may have auto-hidden
        remote.press(.down)
        Thread.sleep(forTimeInterval: 1.5)
      }
      XCTAssertTrue(strip.exists, "cycle \(cycle): the tab strip is gone")
      XCTAssertEqual(strip.frame.minY, stripY, accuracy: 1,
                     "cycle \(cycle): the tab grew — the strip moved from \(stripY) to \(strip.frame.minY)")
      XCTAssertEqual(upNext.frame.minY, upNextY, accuracy: 1,
                     "cycle \(cycle): the Up Next tab moved from \(upNextY) to \(upNext.frame.minY)")
    }
  }
}
#endif
