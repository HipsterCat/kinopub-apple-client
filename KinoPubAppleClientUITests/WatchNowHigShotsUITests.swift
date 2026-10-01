#if os(tvOS)
//
//  WatchNowHigShotsUITests.swift
//  KinoPubAppleClientUITests
//
//  Local-only hig capture for PR #21. CI has no kino.pub session, so these
//  tests skip unless `~/.kinopub-dev-session.json` exists.
//
//  `UIFocusSystem.requestFocusUpdate` does not move focus off the SwiftUI
//  Watch Now tab pill in this embed — do not use `-KINOPUBFocusFirstPoster`
//  as the evidence path. This test launches Watch Now, waits for
//  `kinopub.poster.{id}` cells, then `XCUIRemote.shared.press(.down)` until
//  a 2:3 poster has focus (scale + caption).
//
//  Run on sasha.local (tvOS Simulator, signed-in DEBUG):
//
//    xcodebuild test \
//      -project KinoPubAppleClient.xcodeproj \
//      -scheme KinoPubAppleClient \
//      -destination 'platform=tvOS Simulator,name=Apple TV' \
//      -only-testing:KinoPubAppleClientUITests/WatchNowHigShotsUITests
//
//  Light only:  .../WatchNowHigShotsUITests/testLightHotMoviesCaptionShot
//  Dark only:   .../WatchNowHigShotsUITests/testDarkHotMoviesCaptionShot
//
//  PNGs land in:
//    docs/pr21-shots/watch-now-{light|dark}-hot-movies.png
//    /tmp/kinopub-pr21-shots/  (same names)
//  plus XCTAttachments on the test result.
//

import XCTest
#if canImport(UIKit)
import UIKit
#endif

final class WatchNowHigShotsUITests: XCTestCase {

  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  func testLightHotMoviesCaptionShot() throws {
    try skipUnlessDevSession()
    try captureHotMoviesCaptionShot(colorScheme: "light")
  }

  func testDarkHotMoviesCaptionShot() throws {
    try skipUnlessDevSession()
    try captureHotMoviesCaptionShot(colorScheme: "dark")
  }

  /// Play/Pause or long-Select on a focused 2:3 poster must open the card context menu.
  /// Uses the templates gallery (no auth). Drives by remote Downs like
  /// `testTemplatesGalleryWalk` — waiting on `kinopub.poster.*` alone is flaky
  /// because poster cells may not enter the AX tree until their orthogonal row
  /// is near the viewport.
  func testPlayPauseOpensMenuOnVerticalPoster() throws {
    let app = XCUIApplication()
    app.launchArguments += [
      "-ui-testing",
      "-KINOPUBTemplatesGallery",
      "-KINOPUBForceColorScheme", "dark"
    ]
    app.launch()
    XCTAssertEqual(app.state, .runningForeground)
    Thread.sleep(forTimeInterval: 4)

    // Banner → chips → stills → "Recently Added" posters (caption always).
    for _ in 0..<12 {
      if Self.focusedPoster(in: app) != nil { break }
      XCUIRemote.shared.press(.down)
      Thread.sleep(forTimeInterval: 0.55)
    }

    try writeScreenshots(app.screenshot(), colorScheme: "dark", suffix: "pcm-focused")

    XCUIRemote.shared.press(.playPause)
    Thread.sleep(forTimeInterval: 1.5)
    if !menuVisible(in: app) {
      // Secondary activation path on tvOS: long-press Select.
      XCUIRemote.shared.press(.select, forDuration: 2.0)
      Thread.sleep(forTimeInterval: 1.5)
    }
    try writeScreenshots(app.screenshot(), colorScheme: "dark", suffix: "pcm-after-menu")

    let poster = Self.focusedPoster(in: app)
    XCTAssertTrue(
      menuVisible(in: app),
      "Play/Pause (or long-Select) did not open a context menu (focusedPoster=\(poster?.identifier ?? "nil"))\n\(app.debugDescription)"
    )
  }

  private func menuVisible(in app: XCUIApplication) -> Bool {
    if app.menus.firstMatch.exists || app.menuItems.firstMatch.exists { return true }
    let play = app.descendants(matching: .any).matching(
      NSPredicate(
        format: "label ==[c] %@ OR label ==[c] %@ OR label ==[c] %@ OR label ==[c] %@",
        "Play", "Смотреть", "Go to Movie", "К фильму"
      )
    ).firstMatch
    return play.exists
  }

  // MARK: - Capture

  private func captureHotMoviesCaptionShot(colorScheme: String) throws {
    let app = XCUIApplication()
    app.launchArguments += [
      "-ui-testing",
      "-KINOPUBForceColorScheme", colorScheme
    ]
    if let session = UITestDevSession.json {
      app.launchEnvironment["KINOPUB_DEV_SESSION"] = session
    }
    app.launch()

    XCTAssertEqual(app.state, .runningForeground)

    // Default tab is Watch Now. `XCUIElement.tap()` is unavailable on tvOS —
    // do not select the pill; `.down` leaves it for the content graph.
    let posters = app.descendants(matching: .any).matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "kinopub.poster.")
    )
    XCTAssertTrue(
      posters.firstMatch.waitForExistence(timeout: 90),
      "no kinopub.poster.* cells after catalog wait — session missing or Watch Now empty"
    )

    for _ in 0..<20 {
      if Self.focusedPoster(in: app) != nil { break }
      XCUIRemote.shared.press(.down)
      Thread.sleep(forTimeInterval: 0.45)
    }

    guard Self.focusedPoster(in: app) != nil else {
      try writeScreenshots(app.screenshot(), colorScheme: colorScheme, suffix: "FAILED")
      XCTFail(
        "never focused a kinopub.poster.* cell (still on tab pill or CW)\n\(app.debugDescription)"
      )
      return
    }

    // Artwork + caption clearance paint after the focus animation.
    Thread.sleep(forTimeInterval: 3.0)
    try writeScreenshots(app.screenshot(), colorScheme: colorScheme, suffix: nil)
  }

  // MARK: - Session

  private static var devSessionPath: String { UITestDevSession.filePath }

  private func skipUnlessDevSession() throws {
    guard FileManager.default.fileExists(atPath: Self.devSessionPath) else {
      throw XCTSkip("no ~/.kinopub-dev-session.json — local hig shots only")
    }
  }

  // MARK: - Focus

  private static func focusedPoster(in app: XCUIApplication) -> XCUIElement? {
    let posters = app.descendants(matching: .any).matching(
      NSPredicate(format: "identifier BEGINSWITH %@ AND hasFocus == true", "kinopub.poster.")
    )
    let hit = posters.firstMatch
    return hit.exists ? hit : nil
  }

  // MARK: - Output

  private func writeScreenshots(
    _ screenshot: XCUIScreenshot,
    colorScheme: String,
    suffix: String?
  ) throws {
    let stem = suffix.map { "watch-now-\(colorScheme)-hot-movies-\($0)" }
      ?? "watch-now-\(colorScheme)-hot-movies"
    let filename = "\(stem).png"
#if canImport(UIKit)
    guard let data = screenshot.image.pngData() else {
      XCTFail("screenshot.image.pngData() was nil for \(stem)")
      return
    }
#else
    let data = screenshot.pngRepresentation
#endif

    let attachment = XCTAttachment(screenshot: screenshot)
    attachment.name = stem
    attachment.lifetime = .keepAlways
    add(attachment)

    let tmpDir = URL(fileURLWithPath: "/tmp/kinopub-pr21-shots", isDirectory: true)
    try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    let tmpURL = tmpDir.appendingPathComponent(filename)
    try data.write(to: tmpURL)

    let docsDir = Self.repoRoot.appendingPathComponent("docs/pr21-shots", isDirectory: true)
    try FileManager.default.createDirectory(at: docsDir, withIntermediateDirectories: true)
    try data.write(to: docsDir.appendingPathComponent(filename))
  }

  /// Compile-time path of this file → repo root on the machine that built the tests.
  private static var repoRoot: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
  }
}
#endif
