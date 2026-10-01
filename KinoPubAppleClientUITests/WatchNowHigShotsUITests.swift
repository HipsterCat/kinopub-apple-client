#if os(tvOS)
//
//  WatchNowHigShotsUITests.swift
//  KinoPubAppleClientUITests
//
//  Local hig capture for PR #21. Caption shots skip without a Mac-host session.
//
//  `testPlayPauseOpensMenuOnVerticalPoster` uses the same Home launch path as the
//  green Watch Now / TVPageGeometry UITests: `-ui-testing`,
//  `-KINOPUBForceColorScheme dark`, and `KINOPUB_DEV_SESSION` when present. It waits
//  for `kinopub.page.home` / `kinopub.poster.*`, Downs onto a portrait poster, then
//  opens PCM. CI runners with no session XCTSkip (same as geometry / caption shots).
//
//  Optional local templates harness: set env `KINOPUB_PCM_TEMPLATES=1` on the *test*
//  process to drive `-KINOPUBTemplatesGallery` instead. If that page never paints,
//  the test skips — it is not the CI path.
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
  /// Home Watch Now path (matches green CI UITests). Soft screenshots; Play/Pause then
  /// long-Select. Templates gallery is opt-in via `KINOPUB_PCM_TEMPLATES=1` only.
  func testPlayPauseOpensMenuOnVerticalPoster() throws {
    if ProcessInfo.processInfo.environment["KINOPUB_PCM_TEMPLATES"] == "1" {
      try openMenuOnTemplatesGalleryVerticalPoster()
      return
    }
    try openMenuOnHomeVerticalPoster()
  }

  // MARK: - Home path (CI + signed-in local)

  /// Same launchArguments as `TVPageGeometryUITests` / caption shots that go green on CI
  /// by skipping when there is no session: `-ui-testing`, `-KINOPUBForceColorScheme dark`,
  /// plus `KINOPUB_DEV_SESSION` when `~/.kinopub-dev-session.json` exists.
  private func openMenuOnHomeVerticalPoster() throws {
    try skipUnlessDevSession()

    let app = XCUIApplication()
    app.launchArguments += [
      "-ui-testing",
      "-KINOPUBForceColorScheme", "dark"
    ]
    if let session = UITestDevSession.json {
      app.launchEnvironment["KINOPUB_DEV_SESSION"] = session
    }
    app.launch()
    XCTAssertTrue(
      app.wait(for: .runningForeground, timeout: 20),
      "app never reached runningForeground (state=\(app.state.rawValue))"
    )

    // Match TVPageGeometryUITests: page id first, then a poster under that page.
    // The empty collection can exist before the catalog paints cells; poster ids
    // often stay out of the AX tree until their row is near the viewport, so Down
    // while waiting (same lesson as the failed templates-gallery CI waits).
    let home = app.collectionViews["kinopub.page.home"]
    XCTAssertTrue(
      home.waitForExistence(timeout: 90),
      "Watch Now page never appeared (state=\(app.state.rawValue))"
    )

    let posters = home.descendants(matching: .any).matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "kinopub.poster.")
    )
    var sawPoster = posters.firstMatch.waitForExistence(timeout: 5)
    if !sawPoster {
      for _ in 0..<12 where appIsAlive(app) {
        XCUIRemote.shared.press(.down)
        Thread.sleep(forTimeInterval: 0.55)
        if posters.firstMatch.waitForExistence(timeout: 0.4) {
          sawPoster = true
          break
        }
      }
    }
    if !sawPoster {
      // Catalog still loading — one long poll without remote spam.
      sawPoster = posters.firstMatch.waitForExistence(timeout: 60)
    }
    XCTAssertTrue(
      sawPoster,
      "no kinopub.poster.* cells on Watch Now — session missing or catalog empty"
    )

    try focusVerticalPosterAndOpenMenu(in: app)
  }

  // MARK: - Templates harness (local opt-in only)

  /// Not used on CI. Pass `KINOPUB_PCM_TEMPLATES=1` to the test runner to exercise the
  /// DEBUG gallery without auth. Skips if the gallery page never paints.
  private func openMenuOnTemplatesGalleryVerticalPoster() throws {
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

    let page = app.collectionViews["kinopub.page.templates"]
    let paintedCell = app.descendants(matching: .any).matching(
      NSPredicate(
        format: "identifier BEGINSWITH %@ OR identifier BEGINSWITH %@ OR identifier BEGINSWITH %@",
        "kinopub.banner.",
        "kinopub.poster.",
        "kinopub.chip."
      )
    ).firstMatch
    var galleryReady = false
    let deadline = Date().addingTimeInterval(30)
    while Date() < deadline {
      guard appIsAlive(app) else { break }
      if page.waitForExistence(timeout: 0.4) || paintedCell.waitForExistence(timeout: 0.4) {
        galleryReady = true
        break
      }
    }
    guard galleryReady else {
      throw XCTSkip("templates gallery absent — use Home path (unset KINOPUB_PCM_TEMPLATES)")
    }

    try focusVerticalPosterAndOpenMenu(in: app)
  }

  // MARK: - Shared focus + menu

  private func focusVerticalPosterAndOpenMenu(in app: XCUIApplication) throws {
    // Banner / CW / stills first; keep Downing until a portrait kinopub.poster.*.
    var focusedID: String?
    for _ in 0..<24 {
      guard appIsAlive(app) else {
        XCTFail("app died while moving focus onto a vertical poster (state=\(app.state.rawValue))")
        return
      }
      if let id = focusedVerticalPosterID(in: app) {
        focusedID = id
        break
      }
      XCUIRemote.shared.press(.down)
      Thread.sleep(forTimeInterval: 0.7)
    }

    guard let focusedID else {
      softScreenshot(app, colorScheme: "dark", suffix: "pcm-no-focus")
      XCTFail("never focused a vertical kinopub.poster.* after Downs (state=\(app.state.rawValue))")
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
        format: "label ==[c] %@ OR label ==[c] %@ OR label ==[c] %@ OR label ==[c] %@ OR label ==[c] %@ OR label ==[c] %@",
        "Play", "Смотреть", "Go to Movie", "К фильму", "Go to Show", "К сериалу"
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
      throw XCTSkip("no ~/.kinopub-dev-session.json — local hig / Home PCM only")
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

  /// Vertical 2:3 lockups only — CW / stills also use `kinopub.poster.*` but are landscape.
  private func focusedVerticalPosterID(in app: XCUIApplication) -> String? {
    guard let id = focusedPosterID(in: app) else { return nil }
    let hit = app.descendants(matching: .any).matching(
      NSPredicate(format: "identifier == %@ AND hasFocus == true", id)
    ).firstMatch
    guard hit.waitForExistence(timeout: 0.2) else { return nil }
    let frame = hit.frame
    // Portrait art: taller than wide. Landscape stills / CW tiles are the opposite.
    guard frame.height > frame.width else { return nil }
    return id
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
