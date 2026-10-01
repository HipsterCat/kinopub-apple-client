#if os(tvOS)
//
//  WatchNowHigShotsUITests.swift
//  KinoPubAppleClientUITests
//
//  Local-only hig capture for PR #21. CI has no kino.pub session, so the
//  caption-shot tests skip unless `~/.kinopub-dev-session.json` exists.
//
//  `testPlayPauseOpensMenuOnVerticalPoster` is CI-safe: templates gallery
//  (no auth), waits for `kinopub.poster.*` before Downs, never screenshots a
//  dead app, and tries Play/Pause then long-Select.
//
//  Run on sasha.local (tvOS Simulator, signed-in DEBUG):
//
//    xcodebuild test \
//      -project KinoPubAppleClient.xcodeproj \
//      -scheme KinoPubAppleClient \
//      -destination 'platform=tvOS Simulator,name=Apple TV' \
//      -only-testing:KinoPubAppleClientUITests/WatchNowHigShotsUITests
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
  /// Templates gallery only (no auth). Hardened for GitHub runners where the app can
  /// die mid-walk if we Down-spam before the page exists, then call `app.screenshot()`.
  func testPlayPauseOpensMenuOnVerticalPoster() throws {
    let app = XCUIApplication()
    app.launchArguments += [
      "-ui-testing",
      "-KINOPUBTemplatesGallery",
      "-KINOPUBForceColorScheme", "dark"
    ]
    app.launch()
    XCTAssertTrue(
      app.wait(for: .runningForeground, timeout: 20),
      "app never reached runningForeground (state=\(app.state.rawValue))"
    )

    // Gallery shell first — poster cells often stay out of the AX tree until their
    // orthogonal row is near the viewport (CI run 36902062516 Down-spammed a blank
    // launch, then `app.screenshot()` crashed on a dead process).
    let galleryMarker = app.descendants(matching: .any).matching(
      NSPredicate(
        format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@",
        "Recently Added",
        "Watch Next"
      )
    ).firstMatch
    XCTAssertTrue(
      galleryMarker.waitForExistence(timeout: 30),
      "templates gallery never showed a section header (state=\(app.state.rawValue))"
    )

    // Banner → chips → stills → "Recently Added" posters. Short focus polls so a
    // miss does not burn XCTest's default exists-retry (~3s) twelve times.
    var focusedID: String?
    for _ in 0..<16 {
      guard appIsAlive(app) else {
        XCTFail("app died while moving focus onto a vertical poster (state=\(app.state.rawValue))")
        return
      }
      if let id = focusedPosterID(in: app) {
        focusedID = id
        break
      }
      XCUIRemote.shared.press(.down)
      Thread.sleep(forTimeInterval: 0.7)
    }

    guard let focusedID else {
      softScreenshot(app, colorScheme: "dark", suffix: "pcm-no-focus")
      XCTFail("never focused a kinopub.poster.* after Downs (state=\(app.state.rawValue))")
      return
    }

    softScreenshot(app, colorScheme: "dark", suffix: "pcm-focused")

    XCUIRemote.shared.press(.playPause)
    Thread.sleep(forTimeInterval: 1.2)
    if !menuVisible(in: app) {
      guard appIsAlive(app) else {
        XCTFail("app died after Play/Pause (focused=\(focusedID), state=\(app.state.rawValue))")
        return
      }
      // Secondary activation path on tvOS (and the one that worked locally on sim).
      XCUIRemote.shared.press(.select, forDuration: 2.0)
      Thread.sleep(forTimeInterval: 1.5)
    }

    softScreenshot(app, colorScheme: "dark", suffix: "pcm-after-menu")

    guard appIsAlive(app) else {
      XCTFail("app died before menu assert (focused=\(focusedID), state=\(app.state.rawValue))")
      return
    }
    XCTAssertTrue(
      menuVisible(in: app),
      "Play/Pause (or long-Select) did not open a context menu (focusedPoster=\(focusedID))"
    )
  }

  private func menuVisible(in app: XCUIApplication) -> Bool {
    guard appIsAlive(app) else { return false }
    if app.menus.firstMatch.waitForExistence(timeout: 0.4) { return true }
    if app.menuItems.firstMatch.waitForExistence(timeout: 0.4) { return true }
    let play = app.descendants(matching: .any).matching(
      NSPredicate(
        format: "label ==[c] %@ OR label ==[c] %@ OR label ==[c] %@ OR label ==[c] %@",
        "Play", "Смотреть", "Go to Movie", "К фильму"
      )
    ).firstMatch
    return play.waitForExistence(timeout: 0.4)
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

    XCTAssertTrue(
      app.wait(for: .runningForeground, timeout: 20),
      "app never reached runningForeground"
    )

    // Default tab is Watch Now. `XCUIElement.tap()` is unavailable on tvOS —
    // do not select the pill; `.down` leaves it for the content graph.
    let posters = app.descendants(matching: .any).matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "kinopub.poster.")
    )
    XCTAssertTrue(
      posters.firstMatch.waitForExistence(timeout: 90),
      "no kinopub.poster.* cells after catalog wait — session missing or Watch Now empty"
    )

    var focused: String?
    for _ in 0..<20 {
      if let id = focusedPosterID(in: app) {
        focused = id
        break
      }
      XCUIRemote.shared.press(.down)
      Thread.sleep(forTimeInterval: 0.45)
    }

    guard focused != nil else {
      softScreenshot(app, colorScheme: colorScheme, suffix: "FAILED")
      XCTFail("never focused a kinopub.poster.* cell (still on tab pill or CW)")
      return
    }

    // Artwork + caption clearance paint after the focus animation.
    Thread.sleep(forTimeInterval: 3.0)
    softScreenshot(app, colorScheme: colorScheme, suffix: nil)
  }

  // MARK: - Session

  private static var devSessionPath: String { UITestDevSession.filePath }

  private func skipUnlessDevSession() throws {
    guard FileManager.default.fileExists(atPath: Self.devSessionPath) else {
      throw XCTSkip("no ~/.kinopub-dev-session.json — local hig shots only")
    }
  }

  // MARK: - Focus / app liveness

  private func appIsAlive(_ app: XCUIApplication) -> Bool {
    switch app.state {
    case .runningForeground, .runningBackground:
      return true
    default:
      return false
    }
  }

  /// Short poll — do not use bare `.exists` (XCTest retries ~3s per miss).
  private func focusedPosterID(in app: XCUIApplication) -> String? {
    let posters = app.descendants(matching: .any).matching(
      NSPredicate(format: "identifier BEGINSWITH %@ AND hasFocus == true", "kinopub.poster.")
    )
    let hit = posters.firstMatch
    guard hit.waitForExistence(timeout: 0.35) else { return nil }
    return hit.identifier
  }

  // MARK: - Output

  /// Prefer `app.screenshot()` while alive; fall back to `XCUIScreen` so a dead
  /// process never throws "cannot request screenshot data because it does not exist".
  private func softScreenshot(_ app: XCUIApplication, colorScheme: String, suffix: String?) {
    let stem = suffix.map { "watch-now-\(colorScheme)-hot-movies-\($0)" }
      ?? "watch-now-\(colorScheme)-hot-movies"

    let screenshot: XCUIScreenshot
    if appIsAlive(app) {
      screenshot = app.screenshot()
    } else {
      screenshot = XCUIScreen.main.screenshot()
    }

    let attachment = XCTAttachment(screenshot: screenshot)
    attachment.name = stem
    attachment.lifetime = .keepAlways
    add(attachment)

#if canImport(UIKit)
    guard let data = screenshot.image.pngData() else { return }
#else
    let data = screenshot.pngRepresentation
#endif

    let tmpDir = URL(fileURLWithPath: "/tmp/kinopub-pr21-shots", isDirectory: true)
    try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    try? data.write(to: tmpDir.appendingPathComponent("\(stem).png"))

    // Local hig archive only — do not fail CI if the docs path is missing/RO.
    let docsDir = Self.repoRoot.appendingPathComponent("docs/pr21-shots", isDirectory: true)
    if (try? FileManager.default.createDirectory(at: docsDir, withIntermediateDirectories: true)) != nil {
      try? data.write(to: docsDir.appendingPathComponent("\(stem).png"))
    }
  }

  /// Compile-time path of this file → repo root on the machine that built the tests.
  private static var repoRoot: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
  }
}
#endif
