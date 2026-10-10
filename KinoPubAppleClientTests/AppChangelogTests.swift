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

  func testFirstLaunchRecordsVersionAndDoesNotPrompt() throws {
    let defaults = try makeDefaults()
    let catalog = try AppChangelog.decode(Self.sampleJSON)
    XCTAssertNil(catalog.pendingSheetEntry(currentVersion: "1.0", defaults: defaults))
    XCTAssertEqual(defaults.string(forKey: AppChangelog.lastSeenVersionKey), "1.0")
    XCTAssertNil(catalog.pendingSheetEntry(currentVersion: "1.0", defaults: defaults))
  }

  func testUpdateToAVersionWithNotesPromptsOnce() throws {
    let defaults = try makeDefaults()
    defaults.set("1.0", forKey: AppChangelog.lastSeenVersionKey)
    let catalog = try AppChangelog.decode(Self.sampleJSON)
    let pending = catalog.pendingSheetEntry(currentVersion: "1.1", defaults: defaults)
    XCTAssertEqual(pending?.version, "1.1")
    XCTAssertEqual(pending?.bullets(languageCode: "ru"), ["Новое в 1.1"])
    XCTAssertEqual(defaults.string(forKey: AppChangelog.lastSeenVersionKey), "1.0")

    AppChangelog.markSeen("1.1", defaults: defaults)
    XCTAssertNil(catalog.pendingSheetEntry(currentVersion: "1.1", defaults: defaults))
  }

  func testUpdateWithoutNotesIsSilent() throws {
    let defaults = try makeDefaults()
    defaults.set("1.0", forKey: AppChangelog.lastSeenVersionKey)
    let catalog = try AppChangelog.decode(Self.sampleJSON)
    XCTAssertNil(catalog.pendingSheetEntry(currentVersion: "1.2", defaults: defaults))
    XCTAssertEqual(defaults.string(forKey: AppChangelog.lastSeenVersionKey), "1.2")
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
      defaults.removePersistentDomain(forName: suite)
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
