//
//  AppChangelog.swift
//  Piratic
//
//  User-facing What's New. One marketing-version group, ru + en bullets.
//
//  Hybrid source of truth:
//  - `Resources/whats-new.json` — frozen legacy archive (do not add new bullets here).
//  - `Resources/WhatsNew/entries/<id>.json` — one new contribution per file; PRs only
//    add a file under entries/. The directory listing is the index.
//  Loader merges both; fragments sort by date (then id) and prepend onto their version.
//  There is no CHANGELOG.md — this catalog is the only release-notes surface.
//  TestFlight "What to Test" reads the same sources (Fastlane).
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

  /// One PR-sized contribution under `WhatsNew/entries/`. Arrays allow several
  /// related bullets in the same file without touching a shared mega-file.
  struct Fragment: Equatable, Sendable, Identifiable, Hashable {
    var id: String
    var version: String
    var date: String?
    var ru: [String]
    var en: [String]
  }

  var entries: [Entry]

  static let lastSeenVersionKey = "whatsNew.lastSeenVersion"
  static let seenBulletsKey = "whatsNew.seenBullets"
  /// Legacy archive still shipped for historical bullets.
  static let legacyResourceName = "whats-new"
  /// Folder-reference subdirectory inside the app bundle (blue folder in Xcode).
  static let entriesSubdirectory = "WhatsNew/entries"

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
    let legacy = loadLegacy(from: bundle)
    let fragments = loadFragments(from: bundle)
    return merge(legacy: legacy, fragments: fragments)
  }

  static func loadLegacy(from bundle: Bundle = .main) -> AppChangelog {
    guard let url = bundle.url(forResource: legacyResourceName, withExtension: "json") else {
      return .empty
    }
    return (try? loadLegacy(from: url)) ?? .empty
  }

  static func loadLegacy(from url: URL) throws -> AppChangelog {
    try decodeLegacy(Data(contentsOf: url))
  }

  /// Discovers `*.json` under `WhatsNew/entries` in the bundle (folder reference).
  static func loadFragments(from bundle: Bundle = .main) -> [Fragment] {
    let urls = bundle.urls(
      forResourcesWithExtension: "json",
      subdirectory: entriesSubdirectory
    ) ?? []
    return loadFragments(from: urls)
  }

  static func loadFragments(from urls: [URL]) -> [Fragment] {
    let fragments = urls.compactMap { url -> Fragment? in
      guard let data = try? Data(contentsOf: url) else { return nil }
      return try? decodeFragment(data, fallbackID: url.deletingPathExtension().lastPathComponent)
    }
    return sortedFragments(fragments)
  }

  static func decodeLegacy(_ data: Data) throws -> AppChangelog {
    let payload = try JSONDecoder().decode(LegacyPayload.self, from: data)
    let entries = payload.entries.map {
      Entry(version: $0.version, date: $0.date, ru: $0.ru ?? [], en: $0.en ?? [])
    }
    return AppChangelog(entries: entries.filter { !$0.version.isEmpty })
  }

  /// Back-compat alias used by unit tests that still pass a legacy mega-file blob.
  static func decode(_ data: Data) throws -> AppChangelog {
    try decodeLegacy(data)
  }

  static func decodeFragment(_ data: Data, fallbackID: String) throws -> Fragment {
    let payload = try JSONDecoder().decode(FragmentPayload.self, from: data)
    let id = payload.id?.trimmingCharacters(in: .whitespacesAndNewlines)
    let resolvedID = (id?.isEmpty == false ? id! : fallbackID)
    let version = payload.version.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !version.isEmpty, !resolvedID.isEmpty else {
      throw DecodeError.invalidFragment
    }
    return Fragment(
      id: resolvedID,
      version: version,
      date: payload.date,
      ru: payload.ru ?? [],
      en: payload.en ?? []
    )
  }

  /// Fragments newest-first: ISO date descending, then id descending (stable unique names).
  static func sortedFragments(_ fragments: [Fragment]) -> [Fragment] {
    fragments.sorted { lhs, rhs in
      switch compareOptionalDates(lhs.date, rhs.date) {
      case .orderedAscending: return false
      case .orderedDescending: return true
      case .orderedSame:
        return lhs.id.localizedStandardCompare(rhs.id) == .orderedDescending
      }
    }
  }

  /// Prepend fragment bullets (already newest-first) onto each marketing-version group.
  static func merge(legacy: AppChangelog, fragments: [Fragment]) -> AppChangelog {
    let ordered = sortedFragments(fragments)
    guard !ordered.isEmpty else { return legacy }

    var byVersion: [String: Entry] = [:]
    var versionOrder: [String] = []

    for entry in legacy.entries {
      byVersion[entry.version] = entry
      versionOrder.append(entry.version)
    }

    var fragmentRU: [String: [String]] = [:]
    var fragmentEN: [String: [String]] = [:]
    var fragmentDate: [String: String?] = [:]

    for fragment in ordered {
      fragmentRU[fragment.version, default: []].append(contentsOf: fragment.ru)
      fragmentEN[fragment.version, default: []].append(contentsOf: fragment.en)
      if fragmentDate[fragment.version] == nil {
        fragmentDate[fragment.version] = fragment.date
      }
      if byVersion[fragment.version] == nil {
        versionOrder.append(fragment.version)
        byVersion[fragment.version] = Entry(
          version: fragment.version,
          date: fragment.date,
          ru: [],
          en: []
        )
      }
    }

    for version in versionOrder {
      guard var entry = byVersion[version] else { continue }
      let extraRU = fragmentRU[version] ?? []
      let extraEN = fragmentEN[version] ?? []
      entry.ru = extraRU + entry.ru
      entry.en = extraEN + entry.en
      if let newer = fragmentDate[version] ?? nil {
        entry.date = newerDate(existing: entry.date, candidate: newer)
      }
      byVersion[version] = entry
    }

    return AppChangelog(entries: versionOrder.compactMap { byVersion[$0] })
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
  enum DecodeError: Error {
    case invalidFragment
  }

  struct LegacyPayload: Decodable {
    var entries: [PayloadEntry]
  }

  struct PayloadEntry: Decodable {
    var version: String
    var date: String?
    var ru: [String]?
    var en: [String]?
  }

  struct FragmentPayload: Decodable {
    var id: String?
    var version: String
    var date: String?
    var ru: [String]?
    var en: [String]?
  }

  static func compareOptionalDates(_ lhs: String?, _ rhs: String?) -> ComparisonResult {
    switch (lhs, rhs) {
    case let (l?, r?):
      return l.compare(r)
    case (_?, nil):
      return .orderedDescending
    case (nil, _?):
      return .orderedAscending
    case (nil, nil):
      return .orderedSame
    }
  }

  static func newerDate(existing: String?, candidate: String) -> String {
    guard let existing else { return candidate }
    return compareOptionalDates(candidate, existing) == .orderedDescending ? candidate : existing
  }
}
