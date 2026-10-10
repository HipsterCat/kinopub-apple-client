//
//  AppChangelog.swift
//  KinoPubAppleClient
//
//  User-facing What's New. One entry per marketing version, ru + en bullets.
//  Source of truth: `Resources/whats-new.json`. CHANGELOG.md stays the
//  implementation log. TestFlight "What to Test" reads the same JSON.
//

import Foundation

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

  /// First launch records the current version and does not prompt.
  /// An update to a version that has bullets returns that entry until it is marked seen.
  func pendingSheetEntry(currentVersion: String, defaults: UserDefaults = .standard) -> Entry? {
    let trimmed = currentVersion.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    let last = defaults.string(forKey: Self.lastSeenVersionKey)
    if last == nil {
      defaults.set(trimmed, forKey: Self.lastSeenVersionKey)
      return nil
    }
    if last == trimmed { return nil }

    guard let entry = entry(for: trimmed), !entry.ru.isEmpty || !entry.en.isEmpty else {
      defaults.set(trimmed, forKey: Self.lastSeenVersionKey)
      return nil
    }
    return entry
  }

  static func markSeen(_ version: String, defaults: UserDefaults = .standard) {
    let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    defaults.set(trimmed, forKey: lastSeenVersionKey)
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
