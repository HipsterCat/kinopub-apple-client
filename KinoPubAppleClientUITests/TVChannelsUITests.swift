#if os(tvOS)
//
//  TVChannelsUITests.swift
//  KinoPubAppleClientUITests
//
//  The TV tab walked with the remote on the DEBUG channels fixture
//  (`-KINOPUBTVChannelsFixture YES`, see `TVChannelsFixture`): the real page under a tab
//  bar, 45 channels on a stand-in API, a stand-in player. No session, no stream.
//
//  Screenshots go to the result and to /tmp/kinopub-detail-shots/tv-*.png (the folder CI
//  publishes); the focus log to /tmp/kinopub-detail-shots/tv-focus.txt.
//

import XCTest

final class TVChannelsUITests: XCTestCase {
  private var app: XCUIApplication!
  private var log: [String] = []

  /// The fixture's channels, in the order the grid shows them — five to a row.
  private let firstChannel = "МАТЧ! ТВ"
  private let lastChannel = "Viju Sport"
  private let columns = 5
  private let rows = 9

  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  override func tearDownWithError() throws {
    let dir = URL(fileURLWithPath: "/tmp/kinopub-detail-shots", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try log.joined(separator: "\n").write(to: dir.appendingPathComponent("tv-focus.txt"),
                                          atomically: true, encoding: .utf8)
    app?.terminate()
  }

  /// Down from the tab bar lands on the first channel; Right walks the row, Down walks
  /// every row to the last one while the page scrolls under focus; Up all the way back
  /// reaches the tab bar again. Every press moves focus — a dead end shows up as a stop
  /// that did not.
  func testGridFocusAndScroll() throws {
    launch()
    try enterGrid()
    try shoot("1-first")
    XCTAssertEqual(focusedLabel, firstChannel, "Down from the tab bar: \(focusedDescription)")
    // The fixture's guide has every other channel on air: a second line under those only.
    // The system draws a media item's secondary text over the art of the focused tile.
    XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@",
                                                       "Программа на \(firstChannel)")).firstMatch.exists,
                  "no programme on the first channel")

    for step in 1..<columns {
      try press(.right, expectingMove: true, note: "right \(step)")
    }
    try shoot("2-row-end")

    let page = app.collectionViews["kinopub.page.tv"]
    let topBefore = cell(firstChannel).frame.minY
    for step in 1..<rows {
      try press(.down, expectingMove: true, note: "down \(step)")
    }
    try shoot("3-bottom")
    XCTAssertTrue(page.exists)
    XCTAssertLessThan(cell(firstChannel).exists ? cell(firstChannel).frame.minY : -.greatestFiniteMagnitude,
                      topBefore, "the grid never scrolled under focus")
    let last = cell(lastChannel)
    XCTAssertTrue(last.exists && last.isHittable, "the last channel is not on screen at the bottom")

    // Down from the last row has nowhere to go and must not throw focus out of the page.
    XCUIRemote.shared.press(.down)
    Thread.sleep(forTimeInterval: 0.8)
    XCTAssertTrue(isFocusInGrid, "Down past the last row left the grid: \(focusedDescription)")

    for step in 1..<rows {
      try press(.up, expectingMove: true, note: "up \(step)")
    }
    XCUIRemote.shared.press(.up)
    Thread.sleep(forTimeInterval: 1)
    note("up to bar")
    try shoot("4-tab-bar")
    XCTAssertFalse(isFocusInGrid, "Up from the first row did not reach the tab bar: \(focusedDescription)")
    XCTAssertEqual(app.state, .runningForeground)
  }

  /// Select on a channel opens the player for that channel (the fixture's stand-in, which
  /// names the item it was handed); Menu comes back to the grid, on the same channel.
  func testSelectPlaysChannelAndMenuReturns() throws {
    launch()
    try enterGrid()
    try press(.right, expectingMove: true, note: "right")
    let picked = focusedLabel
    XCTAssertEqual(picked, "МАТЧ! Арена")

    XCUIRemote.shared.press(.select)
    let player = app.buttons["kinopub.fixture.player"]
    XCTAssertTrue(player.waitForExistence(timeout: 10), "Select did not open the player")
    XCTAssertTrue(player.label.contains("item 2 "), "the player got another item: \(player.label)")
    try shoot("5-player")

    XCUIRemote.shared.press(.menu)
    XCTAssertTrue(cell(firstChannel).waitForExistence(timeout: 10), "Menu did not return to the grid")
    Thread.sleep(forTimeInterval: 1)
    try shoot("6-back")
    XCTAssertEqual(focusedLabel, picked, "focus after Menu: \(focusedDescription)")
  }

  /// The logos from kino.pub's CDN, letterboxed onto the 16:9 tiles: a look, for the eye.
  func testRealLogosShots() throws {
    launch(realArt: true)
    try enterGrid()
    Thread.sleep(forTimeInterval: 4)
    try shoot("7-logos")
    for step in 1...3 {
      XCUIRemote.shared.press(.down)
      Thread.sleep(forTimeInterval: 1.5)
      try shoot("8-logos-down-\(step)")
    }
  }

  /// The real player, on Apple's sample stream (`-KINOPUBFixtureRealPlayer`): Select opens
  /// it, it plays with the channel's name as its title (see the shot), the remote's Up / Down
  /// over it crash nothing, and Menu comes back to the grid. AVKit's own controls are not in
  /// the accessibility tree, so that it carries no Episodes or Up Next tab is pinned by
  /// `PlayerLiveModeTests` on the player's side.
  func testRealPlayerPlaysAndMenuReturns() throws {
    launch(extra: ["-KINOPUBFixtureRealPlayer", "YES"])
    try enterGrid()
    XCUIRemote.shared.press(.select)
    Thread.sleep(forTimeInterval: 8)
    try shoot("9-real-player")
    XCTAssertFalse(isFocusInGrid, "Select did not leave the grid")
    XCUIRemote.shared.press(.up)
    Thread.sleep(forTimeInterval: 1.5)
    XCUIRemote.shared.press(.down)
    Thread.sleep(forTimeInterval: 2)
    try shoot("10-real-player-chrome")
    XCTAssertEqual(app.state, .runningForeground)
    for _ in 0..<3 where !cell(firstChannel).isHittable {
      XCUIRemote.shared.press(.menu)
      Thread.sleep(forTimeInterval: 2)
    }
    XCTAssertTrue(cell(firstChannel).isHittable, "Menu did not return to the grid")
    Thread.sleep(forTimeInterval: 1)
    XCTAssertEqual(focusedLabel, firstChannel, "focus after the player: \(focusedDescription)")
  }

  // MARK: - Helpers

  private func launch(realArt: Bool = false, extra: [String] = []) {
    app = XCUIApplication()
    app.launchArguments += ["-ui-testing", "-KINOPUBForceColorScheme", "dark",
                            "-KINOPUBTVChannelsFixture", "YES", "-KINOPUBInitialTab", "tv"]
    if realArt { app.launchArguments += ["-KINOPUBFixtureRealArt", "YES"] }
    app.launchArguments += extra
    app.launch()
  }

  /// Waits for the grid, then moves focus into it from wherever the launch left it.
  private func enterGrid() throws {
    XCTAssertTrue(cell(firstChannel).waitForExistence(timeout: 30), "the channels never appeared")
    Thread.sleep(forTimeInterval: 1.5)
    note("launch")
    try shoot("0-launch")
    for _ in 0..<3 where !isFocusInGrid {
      XCUIRemote.shared.press(.down)
      Thread.sleep(forTimeInterval: 1)
    }
    note("entered")
    XCTAssertTrue(isFocusInGrid, "focus never reached the grid: \(focusedDescription)")
  }

  private func press(_ button: XCUIRemote.Button, expectingMove: Bool, note moment: String) throws {
    let before = focusedLabel
    XCUIRemote.shared.press(button)
    Thread.sleep(forTimeInterval: 0.8)
    note(moment)
    if expectingMove {
      XCTAssertNotEqual(focusedLabel, before, "\(moment) did not move focus: \(focusedDescription)")
      XCTAssertTrue(isFocusInGrid, "\(moment) left the grid: \(focusedDescription)")
    }
  }

  /// A tile by its channel's name — the system's text line under the still, a child of
  /// the cell (the cell itself carries no label).
  private func cell(_ title: String) -> XCUIElement {
    app.collectionViews["kinopub.page.tv"].cells.containing(
      NSPredicate(format: "label == %@", title)).firstMatch
  }

  private var focusedCell: XCUIElement {
    app.collectionViews["kinopub.page.tv"].cells.matching(
      NSPredicate(format: "hasFocus == true")).firstMatch
  }

  private var isFocusInGrid: Bool { focusedCell.exists }

  private var focusedLabel: String? {
    let focused = focusedCell
    return focused.exists ? focused.staticTexts.firstMatch.label : nil
  }

  private var focusedDescription: String {
    let focused = app.descendants(matching: .any)
      .matching(NSPredicate(format: "hasFocus == true"))
      .allElementsBoundByIndex
    guard !focused.isEmpty else { return "nothing" }
    return focused.map { "\($0.elementType.rawValue) '\($0.identifier)' '\($0.label)' \($0.frame)" }
      .joined(separator: " | ")
  }

  private func note(_ moment: String) {
    log.append("\(moment): \(focusedDescription)")
  }

  private func shoot(_ name: String) throws {
    let screenshot = app.screenshot()
    let attachment = XCTAttachment(screenshot: screenshot)
    attachment.name = "tv-\(name)"
    attachment.lifetime = .keepAlways
    add(attachment)
    let dir = URL(fileURLWithPath: "/tmp/kinopub-detail-shots", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try screenshot.pngRepresentation.write(to: dir.appendingPathComponent("tv-\(name).png"))
  }
}
#endif
