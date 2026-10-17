//
//  EPGServiceImpl.swift
//  KinoPubAppleClient
//
//  The guide is epg.pw, asked one channel at a time: `api/epg.json?channel_id=<id>` answers
//  with about two days of one channel's programmes in ~10 KB. The community fork downloads
//  whole XMLTV feeds instead (5 MB for iptv.online, 22 MB for the UK feed) and parses them
//  on the device — a daily cost an Apple TV does not need to pay for 51 channels.
//
//  Which epg.pw channel is which kino.pub channel is `EPGChannelTable`, by kino.pub id.
//  Each schedule is kept in memory and on disk (Caches) for `freshness`; a failed fetch falls
//  back to the stale copy, and a channel with neither is left out.
//

import Foundation
import KinoPubBackend
import KinoPubLogging
import OSLog

actor EPGServiceImpl: EPGService {
  static let shared = EPGServiceImpl()

  /// How long a schedule is served before it is fetched again. The guide covers two days.
  static let freshness: TimeInterval = 6 * 3600
  /// Requests in flight at once.
  private static let parallelism = 6
  /// The last programme of a schedule has no next start to end at.
  private static let lastProgrammeLength: TimeInterval = 2 * 3600

  private let session: URLSession
  private let cacheDirectory: URL?
  private let table: [Int: String]
  private var memory: [String: Cached] = [:]

  private struct Cached: Codable {
    let fetchedAt: Date
    let programs: [EPGProgram]
  }

  init(session: URLSession = .shared,
       table: [Int: String] = EPGChannelTable.epgPW,
       cacheDirectory: URL? = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
         .appendingPathComponent("EPG", isDirectory: true)) {
    self.session = session
    self.table = table
    self.cacheDirectory = cacheDirectory
  }

  func schedules(for channels: [TVChannel]) async -> [Int: [EPGProgram]] {
    // Several kino.pub channels can share one guide channel (a 4K copy of its HD channel):
    // fetch each guide channel once.
    var byGuideID: [String: [Int]] = [:]
    for channel in channels {
      guard let guideID = table[channel.id] else { continue }
      byGuideID[guideID, default: []].append(channel.id)
    }
    let guideIDs = Array(byGuideID.keys)
    var fetched: [String: [EPGProgram]] = [:]
    await withTaskGroup(of: (String, [EPGProgram]?).self) { group in
      var next = 0
      func enqueue() {
        guard next < guideIDs.count else { return }
        let id = guideIDs[next]
        next += 1
        group.addTask { (id, await self.schedule(guideID: id)) }
      }
      for _ in 0..<Self.parallelism { enqueue() }
      for await (id, programs) in group {
        if let programs, !programs.isEmpty { fetched[id] = programs }
        enqueue()
      }
    }
    var result: [Int: [EPGProgram]] = [:]
    for (guideID, channelIDs) in byGuideID {
      guard let programs = fetched[guideID] else { continue }
      for id in channelIDs { result[id] = programs }
    }
    return result
  }

  // MARK: - One channel

  private func schedule(guideID: String, now: Date = Date()) async -> [EPGProgram]? {
    let cached = memory[guideID] ?? loadFromDisk(guideID)
    if let cached, now.timeIntervalSince(cached.fetchedAt) < Self.freshness {
      return cached.programs
    }
    guard let url = URL(string: "https://epg.pw/api/epg.json?channel_id=\(guideID)") else { return cached?.programs }
    do {
      var request = URLRequest(url: url)
      request.timeoutInterval = 20
      let (data, response) = try await session.data(for: request)
      if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
        return cached?.programs
      }
      let programs = try Self.decode(data)
      let fresh = Cached(fetchedAt: now, programs: programs)
      memory[guideID] = fresh
      saveToDisk(fresh, guideID: guideID)
      return programs
    } catch {
      Logger.app.debug("epg \(guideID, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
      return cached?.programs
    }
  }

  /// epg.pw's answer: `epg_list` of `{title, start_date}` in start order, with no end times —
  /// a programme ends where the next begins.
  static func decode(_ data: Data) throws -> [EPGProgram] {
    struct Answer: Decodable {
      struct Entry: Decodable {
        let title: String?
        let start_date: String
      }
      let epg_list: [Entry]
    }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    let starts = try JSONDecoder().decode(Answer.self, from: data).epg_list
      .compactMap { entry -> (String, Date)? in
        guard let start = formatter.date(from: entry.start_date) else { return nil }
        let title = (entry.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return (title, start)
      }
      .sorted { $0.1 < $1.1 }
    return starts.indices.compactMap { index in
      let (title, start) = starts[index]
      let stop = index + 1 < starts.count ? starts[index + 1].1 : start.addingTimeInterval(lastProgrammeLength)
      guard !title.isEmpty, stop > start else { return nil }
      return EPGProgram(title: title, start: start, stop: stop)
    }
  }

  // MARK: - Disk

  private func cacheURL(_ guideID: String) -> URL? {
    cacheDirectory?.appendingPathComponent("epgpw-\(guideID).json")
  }

  private func loadFromDisk(_ guideID: String) -> Cached? {
    guard let url = cacheURL(guideID), let data = try? Data(contentsOf: url),
          let cached = try? JSONDecoder().decode(Cached.self, from: data) else { return nil }
    memory[guideID] = cached
    return cached
  }

  private func saveToDisk(_ cached: Cached, guideID: String) {
    guard let directory = cacheDirectory, let url = cacheURL(guideID),
          let data = try? JSONEncoder().encode(cached) else { return }
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try? data.write(to: url, options: .atomic)
  }
}
