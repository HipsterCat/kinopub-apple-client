#if os(tvOS)
//
//  TVHomeBannerUITests.swift
//  KinoPubAppleClientUITests
//
//  The Home banner as centred `TVCardView` platters (the pre-full-screen layout),
//  walked with the remote in the templates gallery (no session needed; the banner is
//  its first row, six titles): focus starts on the middle title, centred; Right and
//  Left move it one title and the row centres the new one; the row ends after six
//  titles each way; Down leaves the banner and Up returns to a banner title (the
//  stills under it are left-aligned, so spatial Up may land on a neighbour of the
//  title we left — the nested full-screen carousel made Up always hit one cell).
//  Select reports the title — it does not open the card edge to edge.
//
//  Screenshots are attached to the result and written to /tmp/kinopub-banner-shots/.
//

import XCTest

final class TVHomeBannerUITests: XCTestCase {
  private var app: XCUIApplication!
  /// The screen's centre line. A centred platter sits on it.
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
    try assertCentred(start, "start")
    XCTAssertTrue(hasCard(leftOf: start) && hasCard(rightOf: start),
                  "the start title should have a neighbour on either side")

    let right = try press(.right, "1-right")
    XCTAssertNotEqual(right.identifier, start.identifier, "Right did not move focus")
    try assertCentred(right, "after Right")

    let back = try press(.left, "2-left")
    XCTAssertEqual(back.identifier, start.identifier, "Left did not come back to the start title")
    try assertCentred(back, "after Left")

    // The start is the middle of six: two titles to its left, three to its right.
    var seen = [back.identifier]
    for step in 1...3 { seen.append(try press(.left, "3-left-\(step)").identifier) }
    XCTAssertEqual(Set(seen).count, 3, "expected two titles left of the start: \(seen)")
    XCTAssertEqual(seen[2], seen[3], "Left past the first title moved focus: \(seen)")
    try assertCentred(try focusedTitle(), "first title")

    for step in 1...2 { _ = try press(.right, "4-right-\(step)") }
    let resting = try focusedTitle()
    XCTAssertEqual(resting.identifier, start.identifier)

    XCUIRemote.shared.press(.down)
    Thread.sleep(forTimeInterval: 1.2)
    try shoot("5-down")
    XCTAssertFalse(focusedTitleQuery.firstMatch.exists, "Down did not leave the banner")
    XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch.exists,
                  "Down left nothing focused")

    let up = try press(.up, "6-up")
    XCTAssertTrue(up.identifier.hasPrefix("kinopub.banner."),
                  "Up did not return to a banner title: \(up.identifier)")
    try assertCentred(up, "after Up")

    XCUIRemote.shared.press(.select)
    Thread.sleep(forTimeInterval: 0.8)
    try shoot("7-select")
    let afterSelect = try press(.right, "8-right-after-select")
    XCTAssertNotEqual(afterSelect.identifier, up.identifier, "Right after Select did not move")
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

  private func assertCentred(_ title: Title, _ moment: String) throws {
    let frame = title.frame
    // The focused platter lifts, so the cell is a little wider than the resting card.
    XCTAssertEqual(frame.midX, screenMidX, accuracy: 80, "\(moment): focused title not centred — \(frame)")
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
