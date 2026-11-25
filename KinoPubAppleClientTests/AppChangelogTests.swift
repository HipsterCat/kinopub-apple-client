//
//  AppChangelogTests.swift
//  KinoPubAppleClientTests
//

import XCTest
@testable import KinoPub

final class AppChangelogTests: XCTestCase {
  func testBundledCatalogHasCurrentMarketingVersionWithBothLanguages() throws {
    let catalog = AppChangelog.load()
    XCTAssertFalse(catalog.entries.isEmpty, "legacy whats-new.json must ship at least one version")
    let current = Bundle.main.appVersionLong
    let entry = try XCTUnwrap(
      catalog.entry(for: current),
      "catalog needs an entry for marketing version \(current)"
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

  /// New contributions live as isolated files; they prepend onto the legacy version
  /// group and sort by date (newest first) without editing the mega-file.
  func testFragmentsMergeAheadOfLegacyAndSortByDate() throws {
    let legacy = try AppChangelog.decode(Self.sampleJSON)
    let older = try AppChangelog.decodeFragment(Data("""
    {
      "version": "1.1",
      "date": "2026-11-01",
      "ru": ["Старый фрагмент"],
      "en": ["Older fragment"]
    }
    """.utf8), fallbackID: "2026-11-01-older")
    let newer = try AppChangelog.decodeFragment(Data("""
    {
      "version": "1.1",
      "date": "2026-11-26",
      "ru": ["Новый фрагмент"],
      "en": ["Newer fragment"]
    }
    """.utf8), fallbackID: "2026-11-26-newer")

    let catalog = AppChangelog.merge(legacy: legacy, fragments: [older, newer])
    let entry = try XCTUnwrap(catalog.entry(for: "1.1"))
    XCTAssertEqual(entry.ru, ["Новый фрагмент", "Старый фрагмент", "Новое в 1.1"])
    XCTAssertEqual(entry.en, ["Newer fragment", "Older fragment", "New in 1.1"])
    XCTAssertEqual(entry.date, "2026-11-26")
  }

  func testFragmentCreatesVersionMissingFromLegacy() throws {
    let legacy = try AppChangelog.decode(Data("""
    {"entries":[{"version":"1.0","ru":["Старое"],"en":["Old"]}]}
    """.utf8))
    let fragment = try AppChangelog.decodeFragment(Data("""
    {
      "version": "1.2",
      "date": "2026-12-01",
      "ru": ["Два"],
      "en": ["Two"]
    }
    """.utf8), fallbackID: "2026-12-01-two")

    let catalog = AppChangelog.merge(legacy: legacy, fragments: [fragment])
    XCTAssertEqual(catalog.newestFirst.map(\.version), ["1.2", "1.0"])
    XCTAssertEqual(catalog.entry(for: "1.2")?.en, ["Two"])
  }

  func testLoadFragmentsFromDirectoryUsesFilenameAsID() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("WhatsNewEntries-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let url = directory.appendingPathComponent("2026-11-20-sample.json")
    try Data("""
    {"version":"1.0","date":"2026-11-20","ru":["Раз"],"en":["One"]}
    """.utf8).write(to: url)

    let fragments = AppChangelog.loadFragments(from: [url])
    XCTAssertEqual(fragments.count, 1)
    XCTAssertEqual(fragments[0].id, "2026-11-20-sample")
    XCTAssertEqual(fragments[0].en, ["One"])
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
