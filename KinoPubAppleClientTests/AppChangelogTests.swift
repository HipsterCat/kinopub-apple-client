//
//  AppChangelogTests.swift
//  KinoPubAppleClientTests
//

import XCTest
@testable import KinoPub

final class AppChangelogTests: XCTestCase {
  func testBundledCatalogHasCurrentMarketingVersionWithBothLanguages() throws {
    let catalog = AppChangelog.load()
    XCTAssertFalse(catalog.entries.isEmpty, "whats-new.json must ship at least one version")
    let current = Bundle.main.appVersionLong
    let entry = try XCTUnwrap(
      catalog.entry(for: current),
      "whats-new.json needs an entry for marketing version \(current)"
    )
    XCTAssertFalse(entry.ru.isEmpty, "ru bullets are required")
    XCTAssertFalse(entry.en.isEmpty, "en bullets are required")
    XCTAssertEqual(entry.bullets(languageCode: "ru"), entry.ru)
    XCTAssertEqual(entry.bullets(languageCode: "en"), entry.en)
  }

  func testFreshInstallMarksEverythingSeenAndDoesNotPrompt() throws {
    let defaults = try makeDefaults()
    let catalog = try AppChangelog.decode(Self.sampleJSON)
    XCTAssertNil(catalog.pendingWhatsNew(currentVersion: "1.1", languageCode: "ru", defaults: defaults))
    XCTAssertEqual(defaults.string(forKey: AppChangelog.lastSeenVersionKey), "1.1")
    XCTAssertNil(catalog.pendingWhatsNew(currentVersion: "1.1", languageCode: "ru", defaults: defaults))
  }

  /// Installs from before the seen list recorded only the version, and were never shown
  /// anything: every bullet is new to them.
  func testInstallWithOnlyALastSeenVersionSeesEverything() throws {
    let defaults = try makeDefaults()
    defaults.set("1.0", forKey: AppChangelog.lastSeenVersionKey)
    let catalog = try AppChangelog.decode(Self.sampleJSON)
    let pending = catalog.pendingWhatsNew(currentVersion: "1.0", languageCode: "ru", defaults: defaults)
    XCTAssertEqual(pending?.bullets, ["Новое в 1.1", "Старое"])
  }

  /// The marketing version does not move between TestFlight builds; a bullet added to
  /// the same version is what makes the next build show the popup — and only that bullet.
  func testABulletAddedToTheSameVersionPromptsOnce() throws {
    let defaults = try makeDefaults()
    let before = try AppChangelog.decode(Self.sampleJSON)
    before.markSeen(currentVersion: "1.1", defaults: defaults)
    XCTAssertNil(before.pendingWhatsNew(currentVersion: "1.1", languageCode: "en", defaults: defaults))

    let after = try AppChangelog.decode(Data("""
    {
      "entries": [
        {"version": "1.0", "ru": ["Старое"], "en": ["Old"]},
        {"version": "1.1", "ru": ["Свежее", "Новое в 1.1"], "en": ["Fresh", "New in 1.1"]}
      ]
    }
    """.utf8))
    XCTAssertEqual(after.pendingWhatsNew(currentVersion: "1.1", languageCode: "en", defaults: defaults)?.bullets,
                   ["Fresh"])
    XCTAssertEqual(after.pendingWhatsNew(currentVersion: "1.1", languageCode: "ru", defaults: defaults)?.bullets,
                   ["Свежее"])

    after.markSeen(currentVersion: "1.1", defaults: defaults)
    XCTAssertNil(after.pendingWhatsNew(currentVersion: "1.1", languageCode: "en", defaults: defaults))
    XCTAssertNil(after.pendingWhatsNew(currentVersion: "1.1", languageCode: "ru", defaults: defaults))
  }

  func testNewestFirstOrdersByVersion() throws {
    let catalog = try AppChangelog.decode(Self.sampleJSON)
    XCTAssertEqual(catalog.newestFirst.map(\.version), ["1.1", "1.0"])
  }

  private func makeDefaults() throws -> UserDefaults {
    let suite = "AppChangelogTests-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defaults.removePersistentDomain(forName: suite)
    addTeardownBlock {
      UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
    }
    return defaults
  }

  private static let sampleJSON = Data("""
  {
    "entries": [
      {"version": "1.0", "ru": ["Старое"], "en": ["Old"]},
      {"version": "1.1", "ru": ["Новое в 1.1"], "en": ["New in 1.1"]}
    ]
  }
  """.utf8)
}
