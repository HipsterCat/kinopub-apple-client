#if os(tvOS)
//
//  TVHomeHeroUITests.swift
//  KinoPubAppleClientUITests
//
//  The Home hero carousel (`TVPageSection.hero`), walked with the remote in the
//  templates gallery (no session; `-KINOPUBTemplatesHero` puts the hero first, six
//  titles, no logos so each title is its name): focus starts on a hero button; the
//  title turns by itself after the dwell; Right past Next and Select on Next turn
//  forward and keep focus on Next; Left past Play turns back; Down leaves for the row
//  under it and Up comes back to a hero button.
//
//  Screenshots are attached to the result and written to /tmp/kinopub-hero-shots/.
//

import XCTest

final class TVHomeHeroUITests: XCTestCase {
  private var app: XCUIApplication!

  override func setUpWithError() throws {
    continueAfterFailure = false
    app = XCUIApplication()
    app.launchArguments += ["-ui-testing", "-KINOPUBTemplatesGallery", "-KINOPUBTemplatesHero",
                            "-KINOPUBForceColorScheme", "dark"]
    app.launch()
  }

  func testHeroFocusAndPaging() throws {
    let first = try waitForFocusedButton("launch")
    try shoot("0-start")
    let startTitle = try shownTitle()

    // Untouched, the title turns after the dwell (8 s).
    Thread.sleep(forTimeInterval: 10)
    try shoot("1-after-dwell")
    let afterDwell = try shownTitle()
    XCTAssertNotEqual(afterDwell, startTitle, "the hero did not advance by itself")
    XCTAssertEqual(try focusedButton(), first, "auto-advance moved focus")

    // To Next, the last button.
    var focused = first
    for step in 0..<4 where focused != "kinopub.hero.next" {
      focused = try press(.right, "2-right-\(step)")
    }
    XCTAssertEqual(focused, "kinopub.hero.next", "Right never reached Next")

    let beforeRight = try shownTitle()
    XCTAssertEqual(try press(.right, "3-right-past-next"), "kinopub.hero.next", "Right past Next moved focus")
    let afterRight = try shownTitle()
    XCTAssertNotEqual(afterRight, beforeRight, "Right past Next did not turn the page")

    XCTAssertEqual(try press(.select, "4-select-next"), "kinopub.hero.next", "Select on Next moved focus")
    let afterSelect = try shownTitle()
    XCTAssertNotEqual(afterSelect, afterRight, "Select on Next did not turn the page")

    // Back to Play, then past it.
    for step in 0..<4 where focused != "kinopub.hero.play" {
      focused = try press(.left, "5-left-\(step)")
    }
    XCTAssertEqual(focused, "kinopub.hero.play", "Left never reached Play")
    XCTAssertEqual(try press(.left, "6-left-past-play"), "kinopub.hero.play", "Left past Play moved focus")
    XCTAssertEqual(try shownTitle(), afterRight, "Left past Play did not turn back one title")

    // Down to the row under the hero, and back.
    XCUIRemote.shared.press(.down)
    Thread.sleep(forTimeInterval: 1.6)
    try shoot("7-down")
    XCTAssertFalse(focusedHeroQuery.firstMatch.exists, "Down did not leave the hero")
    XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch.exists,
                  "Down left nothing focused")

    XCUIRemote.shared.press(.up)
    Thread.sleep(forTimeInterval: 1.6)
    try shoot("8-up")
    XCTAssertTrue(focusedHeroQuery.firstMatch.exists, "Up did not come back to the hero")
  }

  /// Up from the row under the hero, scrolled sideways first, comes back to the button
  /// focus left (Next at launch), and the page is back at the top: the hero's buttons
  /// sit where they sat before Down (Sasha, 2026-10-23: it landed on the nearest button
  /// and the page stayed half receded).
  func testUpFromScrolledRowReturnsToTheButtonFocusLeft() throws {
    let first = try waitForFocusedButton("launch")
    XCTAssertEqual(first, "kinopub.hero.next", "the hero is not entered on Next")
    let restY = app.buttons[first].frame.minY

    XCUIRemote.shared.press(.down)
    Thread.sleep(forTimeInterval: 1.6)
    try shoot("up-0-down")
    XCTAssertFalse(focusedHeroQuery.firstMatch.exists, "Down did not leave the hero")
    for step in 0..<3 {
      XCUIRemote.shared.press(.right)
      Thread.sleep(forTimeInterval: 0.8)
      if step == 2 { try shoot("up-1-row-scrolled") }
    }

    XCUIRemote.shared.press(.up)
    Thread.sleep(forTimeInterval: 1.8)
    try shoot("up-2-back")
    XCTAssertEqual(try focusedButton(), first, "Up from the scrolled row did not come back to Next")
    XCTAssertEqual(app.buttons[first].frame.minY, restY, accuracy: 2,
                   "the page did not scroll back to the top")
  }

  // MARK: - Helpers

  private var focusedHeroQuery: XCUIElementQuery {
    app.descendants(matching: .any).matching(
      NSPredicate(format: "identifier BEGINSWITH %@ AND hasFocus == true", "kinopub.hero.")
    )
  }

  private struct Missing: Error {}

  private func waitForFocusedButton(_ moment: String) throws -> String {
    guard focusedHeroQuery.firstMatch.waitForExistence(timeout: 20) else {
      try shoot("no-focus-\(moment)")
      XCTFail("no hero button has focus at \(moment)")
      throw Missing()
    }
    Thread.sleep(forTimeInterval: 1.2)
    return try focusedButton()
  }

  private func focusedButton() throws -> String {
    let button = focusedHeroQuery.firstMatch
    guard button.waitForExistence(timeout: 5) else {
      XCTFail("no hero button has focus")
      throw Missing()
    }
    return button.identifier
  }

  /// The fronted title: the gallery's titles have no logo, so the name is on screen.
  private func shownTitle() throws -> String {
    let name = app.staticTexts["kinopub.heroTitle"]
    guard name.waitForExistence(timeout: 5), !name.label.isEmpty else {
      try shoot("no-title")
      XCTFail("no hero title on screen")
      throw Missing()
    }
    return name.label
  }

  private func press(_ button: XCUIRemote.Button, _ name: String) throws -> String {
    XCUIRemote.shared.press(button)
    Thread.sleep(forTimeInterval: 1.4)
    try shoot(name)
    return try focusedButton()
  }

  private func shoot(_ name: String) throws {
    let screenshot = app.screenshot()
    let attachment = XCTAttachment(screenshot: screenshot)
    attachment.name = "hero-\(name)"
    attachment.lifetime = .keepAlways
    add(attachment)
    let dir = URL(fileURLWithPath: "/tmp/kinopub-hero-shots", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try screenshot.pngRepresentation.write(to: dir.appendingPathComponent("hero-\(name).png"))
  }
}
#endif
