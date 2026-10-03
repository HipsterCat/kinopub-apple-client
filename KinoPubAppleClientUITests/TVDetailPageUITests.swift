#if os(tvOS)
//
//  TVDetailPageUITests.swift
//  KinoPubAppleClientUITests
//
//  The detail page walked with the remote against the DEBUG fixtures
//  (`-KINOPUBDetailFixture`, see `DetailFixture` in the app): no session, a stand-in
//  player that marks what it opens as watched.
//
//  Sasha's list of 2026-10-03:
//  - after watching the last episode from the hero's Play and coming back, *something*
//    has focus — the main button, which is now labelled Follow («Отслеживать»);
//  - a series caught up on kino.pub with the next episode dated opens on Follow;
//  - Replay, when it leads, has the focus on opening and after the player too;
//  - episodes TMDB lists and kino.pub does not have: a lock, «Сегодня» … «3 дня назад»,
//    «Позже» (the screenshots are the check; the badge is drawn, not an element);
//  - a film in versions has a play button per version (two at most), named after the
//    version, else «Смотреть» / «Вторая версия».
//
//  Runs in Russian so the labels are the ones Sasha reads. Screenshots go to the result
//  and to /tmp/kinopub-detail-shots/, which CI prints into the job log.
//

import XCTest

final class TVDetailPageUITests: XCTestCase {
  private var app: XCUIApplication!

  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  // MARK: - Focus

  func testFollowHasFocusAfterWatchingTheLastEpisode() throws {
    launch("awaiting")
    try waitForFocus(on: "play", timeout: 20, "open")
    try shoot("awaiting-0-open")
    if control("follow").exists {
      XCTAssertGreaterThan(control("follow").frame.minX, control("play").frame.minX,
                           "Follow should not lead while S2E4 is still unwatched")
    }

    // Play opens S2E4; the stand-in player marks it watched to the end.
    XCUIRemote.shared.press(.select)
    let player = app.descendants(matching: .any).matching(identifier: "kinopub.fixture.player").firstMatch
    XCTAssertTrue(player.waitForExistence(timeout: 10), "Play did not open the player")
    Thread.sleep(forTimeInterval: 1.0)
    try shoot("awaiting-1-player")

    // Back: everything is watched and S2E5 has a date, so Follow is the main button —
    // and it has the focus. Before the fix nothing had focus here.
    XCUIRemote.shared.press(.menu)
    try waitForFocus(on: "follow", timeout: 10, "back from the player")
    try shoot("awaiting-2-back")
    XCTAssertTrue(control("follow").label.contains("Отслеживать"), control("follow").label)
    XCTAssertLessThan(control("follow").frame.minX, control("play").frame.minX,
                      "Follow should lead the row")

    // And it stays there: nothing takes it back a moment later.
    Thread.sleep(forTimeInterval: 2.0)
    XCTAssertTrue(focused("follow").exists, "focus left Follow: \(focusedDescription)")
    try shoot("awaiting-3-settled")
  }

  func testCaughtUpSeriesOpensOnFollow() throws {
    launch("missing")
    try waitForFocus(on: "follow", timeout: 20, "open")
    XCTAssertTrue(control("follow").label.contains("Отслеживать"), control("follow").label)
    try shoot("missing-0-open")
  }

  /// Replay leading is still the main button: focus on opening, and again after the player.
  func testReplayHasFocusOnOpeningAndAfterThePlayer() throws {
    launch("rewatch")
    try waitForFocus(on: "play", timeout: 20, "open")
    try shoot("rewatch-0-open")

    XCUIRemote.shared.press(.select)
    let player = app.descendants(matching: .any).matching(identifier: "kinopub.fixture.player").firstMatch
    XCTAssertTrue(player.waitForExistence(timeout: 10), "Replay did not open the player")
    Thread.sleep(forTimeInterval: 1.0)

    XCUIRemote.shared.press(.menu)
    try waitForFocus(on: "play", timeout: 10, "back from the player")
    Thread.sleep(forTimeInterval: 2.0)
    XCTAssertTrue(focused("play").exists, "focus left Replay: \(focusedDescription)")
    try shoot("rewatch-1-back")
  }

  // MARK: - Episodes kino.pub does not have

  func testMissingEpisodesInTheRail() throws {
    launch("missing")
    try waitForFocus(on: "follow", timeout: 20, "open")

    // Down into the episodes; the rail opens on the last one kino.pub has (E2).
    XCUIRemote.shared.press(.down)
    Thread.sleep(forTimeInterval: 1.5)
    XCTAssertFalse(anyHeroControlHasFocus, "Down did not leave the hero: \(focusedDescription)")
    try shoot("missing-1-rail")

    // E3 (aired long ago: lock only), E4–E7 (3 days ago … today), E8 (in two days),
    // E9 (in twenty), E10 (undated: «Позже»).
    for step in 1...8 {
      XCUIRemote.shared.press(.right)
      Thread.sleep(forTimeInterval: 0.9)
      try shoot("missing-2-right-\(step)")
    }

    // Select on one: a toast says why it cannot play.
    XCUIRemote.shared.press(.left)
    Thread.sleep(forTimeInterval: 0.9)
    XCUIRemote.shared.press(.select)
    Thread.sleep(forTimeInterval: 0.4)
    try shoot("missing-3-toast")
  }

  // MARK: - Versions of one film

  func testTwoVersionsAreTwoNamedPlayButtons() throws {
    launch("versions")
    try waitForFocus(on: "play", timeout: 20, "open")
    XCTAssertTrue(control("play").label.contains("24 fps"), control("play").label)
    XCTAssertTrue(control("playAlternate").label.contains("48 fps"), control("playAlternate").label)
    try shoot("versions-0-open")

    XCUIRemote.shared.press(.right)
    try waitForFocus(on: "playAlternate", timeout: 5, "Right")
    try shoot("versions-1-second")
  }

  func testUnnamedVersionsFallBackAndStopAtTwo() throws {
    launch("versionsUnnamed")
    try waitForFocus(on: "play", timeout: 20, "open")
    XCTAssertTrue(control("play").label.contains("Смотреть"), control("play").label)
    XCTAssertTrue(control("playAlternate").label.contains("Вторая версия"), control("playAlternate").label)
    let playButtons = app.descendants(matching: .any)
      .matching(NSPredicate(format: "identifier BEGINSWITH %@", "kinopub.hero.play"))
      .allElementsBoundByIndex
      .map { $0.identifier }
    XCTAssertEqual(Set(playButtons), ["kinopub.hero.play", "kinopub.hero.playAlternate"],
                   "a third version must not be a button")
    try shoot("versions-unnamed-0-open")
  }

  // MARK: - Helpers

  private func launch(_ fixture: String) {
    app = XCUIApplication()
    app.launchArguments += ["-ui-testing",
                            "-KINOPUBDetailFixture", fixture,
                            "-KINOPUBForceColorScheme", "dark",
                            "-AppleLanguages", "(ru)",
                            "-AppleLocale", "ru_RU",
                            "-UIFocusLoggingEnabled", "YES"]
    app.launch()
  }

  /// The hero control by id — the button itself, in case SwiftUI also hands the
  /// identifier to a wrapper around it.
  private func control(_ id: String) -> XCUIElement {
    let identifier = "kinopub.hero.\(id)"
    let button = app.buttons.matching(identifier: identifier).firstMatch
    return button.exists ? button : app.descendants(matching: .any).matching(identifier: identifier).firstMatch
  }

  /// That control, only while it has focus.
  private func focused(_ id: String) -> XCUIElement {
    app.descendants(matching: .any)
      .matching(NSPredicate(format: "identifier == %@ AND hasFocus == true", "kinopub.hero.\(id)"))
      .firstMatch
  }

  private var anyHeroControlHasFocus: Bool {
    app.descendants(matching: .any)
      .matching(NSPredicate(format: "identifier BEGINSWITH %@ AND hasFocus == true", "kinopub.hero."))
      .firstMatch.exists
  }

  /// What has focus right now, for failure messages.
  private var focusedDescription: String {
    let focused = app.descendants(matching: .any)
      .matching(NSPredicate(format: "hasFocus == true"))
      .allElementsBoundByIndex
    guard !focused.isEmpty else { return "nothing" }
    return focused.map { "\($0.elementType.rawValue) '\($0.identifier)' '\($0.label)'" }
      .joined(separator: ", ")
  }

  private struct NoFocus: Error {}

  private func waitForFocus(on id: String, timeout: TimeInterval, _ moment: String) throws {
    let landed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true"),
                                           object: focused(id))
    guard XCTWaiter().wait(for: [landed], timeout: timeout) == .completed else {
      try shoot("no-focus-\(moment.replacingOccurrences(of: " ", with: "-"))")
      XCTFail("\(moment): \(id) does not have focus — focused: \(focusedDescription)")
      throw NoFocus()
    }
    // Let the focus animation settle before a screenshot.
    Thread.sleep(forTimeInterval: 0.6)
  }

  private func shoot(_ name: String) throws {
    let screenshot = app.screenshot()
    let attachment = XCTAttachment(screenshot: screenshot)
    attachment.name = "detail-\(name)"
    attachment.lifetime = .keepAlways
    add(attachment)
    let dir = URL(fileURLWithPath: "/tmp/kinopub-detail-shots", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try screenshot.pngRepresentation.write(to: dir.appendingPathComponent("detail-\(name).png"))
  }
}
#endif
