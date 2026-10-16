//
//  AppChangelog.swift
//  KinoPubAppleClient
//
//  User-facing What's New. One entry per marketing version, ru + en bullets.
//  Source of truth: `Resources/whats-new.json`. CHANGELOG.md stays the
//  implementation log. TestFlight "What to Test" reads the same JSON.
//  Bullets are newest first within an entry; a new one goes at the top.
//

import Foundation

/// The launch popup's content: the bullets this device has not shown yet.
struct WhatsNew: Equatable, Sendable {
  var version: String
  var bullets: [String]
}

struct AppChangelog: Equatable, Sendable {
  struct Entry: Equatable, Sendable, Identifiable, Hashable {
    var version: String
    var date: String?
    var ru: [String]
    var en: [String]

    var id: String { version }

    func bullets(languageCode: String) -> [String] {
      if languageCode.lowercased().hasPrefix("ru") {
        return ru.isEmpty ? en : ru
      }
      return en.isEmpty ? ru : en
    }
  }

  var entries: [Entry]

  static let lastSeenVersionKey = "whatsNew.lastSeenVersion"
  static let seenBulletsKey = "whatsNew.seenBullets"
  static let resourceName = "whats-new"

  static let empty = AppChangelog(entries: [])

  func entry(for version: String) -> Entry? {
    entries.first { $0.version == version }
  }

  /// Newest first. File order is kept if versions do not parse.
  var newestFirst: [Entry] {
    entries.sorted { lhs, rhs in
      let compared = AppChangelog.compareVersions(lhs.version, rhs.version)
      return compared == .orderedDescending
    }
  }

  /// What the viewer has not been shown yet, in their language, newest first.
  ///
  /// The marketing version stays "1.0" across TestFlight builds, and a build's number is
  /// not known when its notes are written, so "new" is per bullet: any bullet this
  /// device has not shown is new. A reworded bullet counts as new. A fresh install
  /// records everything as seen and stays quiet; an install from before this rule — it
  /// has `lastSeenVersionKey` but no seen list — was never shown anything.
  func pendingWhatsNew(
    currentVersion: String,
    languageCode: String,
    defaults: UserDefaults = .standard
  ) -> WhatsNew? {
    let version = currentVersion.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !version.isEmpty else { return nil }

    let seen: Set<String>
    if let stored = defaults.stringArray(forKey: Self.seenBulletsKey) {
      seen = Set(stored)
    } else if defaults.string(forKey: Self.lastSeenVersionKey) != nil {
      seen = []
    } else {
      markSeen(currentVersion: version, defaults: defaults)
      return nil
    }

    var listed = Set<String>()
    let bullets = newestFirst
      .flatMap { $0.bullets(languageCode: languageCode) }
      .filter { !seen.contains($0) && listed.insert($0).inserted }
    guard !bullets.isEmpty else { return nil }
    return WhatsNew(version: version, bullets: bullets)
  }

  /// Every bullet in both languages, so switching the app's language does not bring
  /// the same notes back.
  func markSeen(currentVersion: String, defaults: UserDefaults = .standard) {
    defaults.set(entries.flatMap { $0.ru + $0.en }, forKey: Self.seenBulletsKey)
    let version = currentVersion.trimmingCharacters(in: .whitespacesAndNewlines)
    if !version.isEmpty {
      defaults.set(version, forKey: Self.lastSeenVersionKey)
    }
  }

  static func load(from bundle: Bundle = .main) -> AppChangelog {
    guard let url = bundle.url(forResource: resourceName, withExtension: "json") else {
      return .empty
    }
    return (try? load(from: url)) ?? .empty
  }

  static func load(from url: URL) throws -> AppChangelog {
    try decode(Data(contentsOf: url))
  }

  static func decode(_ data: Data) throws -> AppChangelog {
    let payload = try JSONDecoder().decode(Payload.self, from: data)
    let entries = payload.entries.map {
      Entry(version: $0.version, date: $0.date, ru: $0.ru ?? [], en: $0.en ?? [])
    }
    return AppChangelog(entries: entries.filter { !$0.version.isEmpty })
  }

  static func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
    let left = lhs.split(separator: ".").compactMap { Int($0) }
    let right = rhs.split(separator: ".").compactMap { Int($0) }
    guard !left.isEmpty, !right.isEmpty else {
      return lhs.compare(rhs, options: [.numeric])
    }
    let count = max(left.count, right.count)
    for index in 0..<count {
      let a = index < left.count ? left[index] : 0
      let b = index < right.count ? right[index] : 0
      if a != b { return a < b ? .orderedAscending : .orderedDescending }
    }
    return .orderedSame
  }
}

private extension AppChangelog {
  struct Payload: Decodable {
    var entries: [PayloadEntry]
  }

  struct PayloadEntry: Decodable {
    var version: String
    var date: String?
    var ru: [String]?
    var en: [String]?
  }
}
