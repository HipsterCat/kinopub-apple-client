import Foundation

/// Memory + disk cache with inflight dedup and negative caching.
public actor MetadataCache {
  public struct Entry: Codable, Sendable {
    public let storedAt: Date
    public let payload: Data
    /// `true` when the payload is a confirmed miss (no logo, no match, …).
    public let isNegative: Bool

    public init(storedAt: Date = Date(), payload: Data, isNegative: Bool = false) {
      self.storedAt = storedAt
      self.payload = payload
      self.isNegative = isNegative
    }
  }

  private let directory: URL
  private var memory: [String: Entry] = [:]
  private var inflight: [String: Task<Entry?, Never>] = [:]
  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()

  public init(directory: URL? = nil) {
    let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
      ?? URL(fileURLWithPath: NSTemporaryDirectory())
    self.directory = directory ?? caches.appendingPathComponent("KinoPubMetadata", isDirectory: true)
    try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    Self.register(self)
  }

  /// Every live cache writes the same default directory. Settings sizes that folder
  /// once; a per-title reset has to reach each cache's memory, not only the files.
  private struct Live {
    weak var cache: MetadataCache?
  }

  private static let registryLock = NSLock()
  nonisolated(unsafe) private static var registry: [Live] = []

  private static func register(_ cache: MetadataCache) {
    registryLock.lock()
    registry.append(Live(cache: cache))
    registryLock.unlock()
  }

  private static func registered() -> [MetadataCache] {
    registryLock.lock()
    registry = registry.filter { $0.cache != nil }
    let caches = registry.compactMap(\.cache)
    registryLock.unlock()
    return caches
  }

  /// One row per kind of file in the metadata folder: how many answers, and
  /// how many bytes. The id is the cache-key prefix (`tmdb_find`, …).
  public struct DiskGroup: Sendable, Equatable {
    public var id: String
    public var count: Int
    public var bytes: Int64
  }

  public static func groups() -> [DiskGroup] {
    let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
      ?? URL(fileURLWithPath: NSTemporaryDirectory())
    let directory = caches.appendingPathComponent("KinoPubMetadata", isDirectory: true)
    let files = (try? FileManager.default.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]
    )) ?? []
    let prefixes = [
      "tmdb_find", "tmdb_details", "tmdb_season", "tmdb_person",
      "kinopoisk_details", "kinopoisk_staff", "kinopoisk_awards",
      "kinopoisk_images", "kinopoisk_facts",
      "kinopoiskProxy_reviews", "kinopoiskProxy_staff", "kinopoiskProxy",
    ]
    var buckets: [String: (count: Int, bytes: Int64)] = [:]
    for url in files {
      let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
      guard values?.isRegularFile == true else { continue }
      let name = url.deletingPathExtension().lastPathComponent
      let id = prefixes.first { name.hasPrefix($0) } ?? "other"
      var bucket = buckets[id] ?? (0, 0)
      bucket.count += 1
      bucket.bytes += Int64(values?.fileSize ?? 0)
      buckets[id] = bucket
    }
    let known = prefixes.compactMap { id -> DiskGroup? in
      guard let bucket = buckets[id], bucket.count > 0 else { return nil }
      return DiskGroup(id: id, count: bucket.count, bytes: bucket.bytes)
    }
    guard let other = buckets["other"], other.count > 0 else { return known }
    return known + [DiskGroup(id: "other", count: other.count, bytes: other.bytes)]
  }

  public static func diskBytes() -> Int64 {
    let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
      ?? URL(fileURLWithPath: NSTemporaryDirectory())
    return directorySize(caches.appendingPathComponent("KinoPubMetadata", isDirectory: true))
  }

  public static func clearAll() async {
    for cache in registered() {
      await cache.removeAll()
    }
  }

  /// Drops cached TMDB / Kinopoisk answers for one title. `imdb` is `tt…`.
  /// `tmdbID` is optional because the find-file usually already carries it.
  public static func removeTitle(imdb: String?, kinopoisk: Int?, tmdbID knownTMDBID: Int?) async {
    var tmdbIDs = Set<Int>()
    if let knownTMDBID { tmdbIDs.insert(knownTMDBID) }
    if let imdb, let found = tmdbID(storedForIMDb: imdb) {
      tmdbIDs.insert(found)
    }
    guard let match = matcher(imdb: imdb, kinopoisk: kinopoisk, tmdbIDs: tmdbIDs) else { return }
    for cache in registered() {
      await cache.remove(where: match)
    }
  }

  private static func matcher(imdb: String?, kinopoisk: Int?, tmdbIDs: Set<Int>) -> (@Sendable (String) -> Bool)? {
    let imdbToken = imdb?.trimmingCharacters(in: .whitespacesAndNewlines)
    let kp = kinopoisk.flatMap { $0 > 0 ? $0 : nil }
    guard imdbToken?.isEmpty == false || kp != nil || !tmdbIDs.isEmpty else { return nil }
    return { @Sendable key in
      let normalized = key
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: ":", with: "_")
        .replacingOccurrences(of: "?", with: "_")
        .replacingOccurrences(of: "&", with: "_")
      if let imdbToken, !imdbToken.isEmpty, normalized.contains(imdbToken) { return true }
      if let kp, keyOwnsID(normalized, kp) { return true }
      for id in tmdbIDs where keyOwnsID(normalized, id) { return true }
      return false
    }
  }

  /// `_550.json` and `_550_`, not `_5501`.
  private static func keyOwnsID(_ key: String, _ id: Int) -> Bool {
    let token = "_\(id)"
    var search = key[...]
    while let range = search.range(of: token) {
      let after = search[range.upperBound...]
      if after.isEmpty || after.hasPrefix("_") || after.hasPrefix(".") { return true }
      search = after
    }
    return false
  }

  private static func tmdbID(storedForIMDb imdb: String) -> Int? {
    let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
      ?? URL(fileURLWithPath: NSTemporaryDirectory())
    let url = caches
      .appendingPathComponent("KinoPubMetadata", isDirectory: true)
      .appendingPathComponent("tmdb_find_\(imdb).json")
    guard let data = try? Data(contentsOf: url),
          let entry = try? JSONDecoder().decode(Entry.self, from: data),
          !entry.isNegative,
          let resolved = try? JSONDecoder().decode(TMDBResolvedID.self, from: entry.payload) else {
      return nil
    }
    return resolved.tmdbId
  }

  private static func directorySize(_ url: URL) -> Int64 {
    guard let enumerator = FileManager.default.enumerator(
      at: url,
      includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]
    ) else { return 0 }
    var total: Int64 = 0
    for case let file as URL in enumerator {
      let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
      if values?.isRegularFile == true {
        total += Int64(values?.fileSize ?? 0)
      }
    }
    return total
  }

  public func entry(for key: String, ttl: TimeInterval) -> Entry? {
    if let memory = memory[key], Date().timeIntervalSince(memory.storedAt) < ttl {
      return memory
    }
    if let disk = loadFromDisk(key: key), Date().timeIntervalSince(disk.storedAt) < ttl {
      memory[key] = disk
      return disk
    }
    return nil
  }

  public func store(_ entry: Entry, for key: String) {
    memory[key] = entry
    saveToDisk(key: key, entry: entry)
  }

  /// Runs `produce` at most once per key while in flight; callers share the result.
  public func deduped(key: String, ttl: TimeInterval, produce: @escaping @Sendable () async -> Entry?) async -> Entry? {
    if let cached = entry(for: key, ttl: ttl) {
      return cached
    }
    if let existing = inflight[key] {
      return await existing.value
    }
    let task = Task<Entry?, Never> {
      await produce()
    }
    inflight[key] = task
    let result = await task.value
    inflight[key] = nil
    if let result {
      store(result, for: key)
    }
    return result
  }

  public func encode<T: Encodable>(_ value: T) throws -> Data {
    try encoder.encode(value)
  }

  public func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
    try decoder.decode(T.self, from: data)
  }

  private func removeAll() {
    memory.removeAll()
    inflight.values.forEach { $0.cancel() }
    inflight.removeAll()
    removeFiles(where: { _ in true })
  }

  private func remove(where predicate: @Sendable (String) -> Bool) {
    memory = memory.filter { !predicate($0.key) }
    removeFiles { predicate($0.deletingPathExtension().lastPathComponent) }
  }

  private func removeFiles(where predicate: (URL) -> Bool) {
    let contents = (try? FileManager.default.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: nil
    )) ?? []
    for url in contents where predicate(url) {
      try? FileManager.default.removeItem(at: url)
    }
  }

  // MARK: - Disk

  private func fileURL(for key: String) -> URL {
    let safe = key
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: ":", with: "_")
      .replacingOccurrences(of: "?", with: "_")
      .replacingOccurrences(of: "&", with: "_")
    return directory.appendingPathComponent("\(safe).json")
  }

  private func loadFromDisk(key: String) -> Entry? {
    let url = fileURL(for: key)
    guard let data = try? Data(contentsOf: url) else { return nil }
    return try? decoder.decode(Entry.self, from: data)
  }

  private func saveToDisk(key: String, entry: Entry) {
    guard let data = try? encoder.encode(entry) else { return }
    try? data.write(to: fileURL(for: key), options: [.atomic])
  }
}
