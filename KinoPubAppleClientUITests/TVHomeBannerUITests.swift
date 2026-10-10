#if os(tvOS)
//
//  TVHomeBannerUITests.swift
//  KinoPubAppleClientUITests
//
//  The Home banner as `TVCardView` platters aligned with the other rails (the
//  pre-full-screen layout, no longer centred), walked with the remote in the
//  templates gallery (no session needed; the banner is its first row, six titles):
//  focus starts on the first title, at the leading inset; Right and Left move one
//  title; the row ends after six; Down leaves the banner and Up returns to a banner
//  title (the stills under it are left-aligned, so spatial Up may land on a
//  neighbour of the title we left). Select reports the title — it does not open
//  the card edge to edge.
//
//  Screenshots are attached to the result and written to /tmp/kinopub-banner-shots/.
//

import XCTest

final class TVHomeBannerUITests: XCTestCase {
  private var app: XCUIApplication!
  /// The screen's centre line. A leading platter sits well to the left of it.
  private var screenMidX: CGFloat { app.windows.firstMatch.frame.midX }

  override func setUpWithError() throws {
    continueAfterFailure = false
    app = XCUIApplication()
    app.launchArguments += ["-ui-testing", "-KINOPUBTemplatesGallery", "-KINOPUBForceColorScheme", "dark"]
    app.launch()
  }

  func testBannerFocusWalk() throws {
    let start = try waitForFocusedTitle("launch")
    try shoot("0-start")
    try assertLeading(start, "start")
    XCTAssertFalse(hasCard(leftOf: start), "the first title should sit at the leading edge")
    XCTAssertTrue(hasCard(rightOf: start), "the next title should peek")

    let right = try press(.right, "1-right")
    XCTAssertNotEqual(right.identifier, start.identifier, "Right did not move focus")

    let back = try press(.left, "2-left")
    XCTAssertEqual(back.identifier, start.identifier, "Left did not come back to the first title")

    let stayed = try press(.left, "3-left-past-start")
    XCTAssertEqual(stayed.identifier, start.identifier, "Left past the first title moved focus")

    var seen = [start.identifier]
    for step in 1...5 { seen.append(try press(.right, "4-right-\(step)").identifier) }
    XCTAssertEqual(Set(seen).count, 6, "expected six titles: \(seen)")
    let end = try press(.right, "4-right-past-end")
    XCTAssertEqual(end.identifier, seen.last, "Right past the last title moved focus")
    _ = try press(.left, "4-back-one")

    XCUIRemote.shared.press(.down)
    Thread.sleep(forTimeInterval: 1.2)
    try shoot("5-down")
    XCTAssertFalse(focusedTitleQuery.firstMatch.exists, "Down did not leave the banner")
    XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch.exists,
                  "Down left nothing focused")

    let up = try press(.up, "6-up")
    XCTAssertTrue(up.identifier.hasPrefix("kinopub.banner."),
                  "Up did not return to a banner title: \(up.identifier)")

    XCUIRemote.shared.press(.select)
    Thread.sleep(forTimeInterval: 0.8)
    try shoot("7-select")
    let afterSelect = try focusedTitle()
    let movedRight = try press(.right, "8-right-after-select")
    if movedRight.identifier == afterSelect.identifier {
      let movedLeft = try press(.left, "8-left-after-select")
      XCTAssertNotEqual(movedLeft.identifier, afterSelect.identifier, "Select trapped focus")
    }
  }

  // MARK: - Helpers

  private struct Title {
    let identifier: String
    let frame: CGRect
  }

  private var focusedTitleQuery: XCUIElementQuery {
    app.descendants(matching: .any).matching(
      NSPredicate(format: "identifier BEGINSWITH %@ AND hasFocus == true", "kinopub.banner.")
    )
  }

  private var cards: [XCUIElement] {
    let query = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "kinopub.banner."))
    return query.allElementsBoundByIndex
  }

  private struct NoFocusedTitle: Error {}

  private func waitForFocusedTitle(_ moment: String) throws -> Title {
    let title = focusedTitleQuery.firstMatch
    guard title.waitForExistence(timeout: 20) else {
      try shoot("no-focus-\(moment)")
      XCTFail("no banner title has focus at \(moment)")
      throw NoFocusedTitle()
    }
    Thread.sleep(forTimeInterval: 1.2)
    return try focusedTitle()
  }

  private func focusedTitle() throws -> Title {
    let title = focusedTitleQuery.firstMatch
    guard title.waitForExistence(timeout: 5) else {
      XCTFail("no banner title has focus")
      throw NoFocusedTitle()
    }
    return Title(identifier: title.identifier, frame: title.frame)
  }

  private func press(_ button: XCUIRemote.Button, _ name: String) throws -> Title {
    XCUIRemote.shared.press(button)
    Thread.sleep(forTimeInterval: 1.4)
    try shoot(name)
    return try focusedTitle()
  }

  private func assertLeading(_ title: Title, _ moment: String) throws {
    let frame = title.frame
    // The focused platter lifts, so the cell is a little wider than the resting card.
    // A leading rail sits on the side inset; a centred one would land on screenMidX.
    XCTAssertLessThan(frame.midX, screenMidX - 120, "\(moment): title is still centred — \(frame)")
  }

  private func hasCard(leftOf title: Title) -> Bool {
    cards.contains { $0.identifier != title.identifier && $0.frame.maxX <= title.frame.minX && $0.frame.maxX > 0 }
  }

  private func hasCard(rightOf title: Title) -> Bool {
    let width = app.windows.firstMatch.frame.width
    return cards.contains { $0.identifier != title.identifier && $0.frame.minX >= title.frame.maxX && $0.frame.minX < width }
  }

  private func shoot(_ name: String) throws {
    let screenshot = app.screenshot()
    let attachment = XCTAttachment(screenshot: screenshot)
    attachment.name = "banner-\(name)"
    attachment.lifetime = .keepAlways
    add(attachment)
    let dir = URL(fileURLWithPath: "/tmp/kinopub-banner-shots", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try screenshot.pngRepresentation.write(to: dir.appendingPathComponent("banner-\(name).png"))
  }
}
#endif
