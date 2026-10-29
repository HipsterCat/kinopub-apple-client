//
//  NetworkActivity.swift
//  KinoPubLogging
//
//  What is in flight *right now*, by product name and by the request itself.
//
//  Pulse answers "what came back and how"; it writes its record when a task completes,
//  so it cannot answer "what are we still waiting for" — which is the question an empty
//  loader on Apple TV raises and never answers. This registry is that second channel:
//  work registers a named activity and unregisters when it settles, and a debug overlay
//  renders whatever is currently registered.
//
//  `nameKey` is a product word ("History", "TMDB") for the launch label. `detail` is the
//  method a person debugging the overlay actually reads: verb, host, path.
//

import Foundation
import Combine

@MainActor
public final class NetworkActivity: ObservableObject {
  public static let shared = NetworkActivity()

  /// A row stays at least this long after the request *started* — the interaction that
  /// fired it. A find that returns in 200 ms used to vanish before it could be read.
  public static var minimumVisible: TimeInterval = 2

  public struct Entry: Identifiable, Sendable {
    public let id: UUID
    /// Localization key, resolved against the app bundle. This is what a person reads on
    /// the launch screen, which is why it is a key and not a formatted string — the raw
    /// endpoint must never reach a user-facing label.
    public let nameKey: String
    /// Verb, host and path. Debug overlay only.
    public let detail: String
    public let startedAt: Date
    /// Set once the request has settled. The row stays until `startedAt + minimumVisible`,
    /// and the clock stops here so a fast call does not pretend it is still running.
    public var finishedAt: Date?

    public func elapsed(at now: Date = Date()) -> TimeInterval {
      let end = finishedAt ?? now
      return end.timeIntervalSince(startedAt)
    }
  }

  /// Oldest first, so an overlay reads as a queue and the slow one stays at the top.
  @Published public private(set) var inFlight: [Entry] = []

  /// `end` can land before its `begin` — both hop to the main actor and the hops are not
  /// ordered. Without this the entry would never be removed and the overlay would grow a
  /// permanent ghost row, which is exactly the kind of lie a diagnostic must not tell.
  /// A request that finished before it was painted is still shown for `minimumVisible`.
  private var endedEarly: Set<UUID> = []
  /// Cancelled before it was painted. Do not surface it: nothing is waiting on it.
  private var suppressed: Set<UUID> = []
  private var removalTasks: [UUID: Task<Void, Never>] = [:]

  private init() {}

  /// - Returns: the token to hand back to `end`.
  public nonisolated static func begin(nameKey: String, detail: String = "") -> UUID {
    let entry = Entry(id: UUID(), nameKey: nameKey, detail: detail, startedAt: Date())
    Task { @MainActor in shared.append(entry) }
    return entry.id
  }

  /// Registers the request the way the overlay reads it: `GET host/path`.
  public nonisolated static func begin(_ request: URLRequest) -> UUID {
    let described = describe(request)
    return begin(nameKey: described.nameKey, detail: described.detail)
  }

  /// `holdMinimum` keeps a finished row on screen until two seconds after it started.
  /// Pass `false` when the work was cancelled — a prefetch that never mattered should
  /// not sit in the "what are we waiting for" list.
  public nonisolated static func end(_ token: UUID, holdMinimum: Bool = true) {
    Task { @MainActor in shared.finish(token, holdMinimum: holdMinimum) }
  }

  /// Verb + host + path, and the launch-label key for that family.
  /// Query is kept only when it is short enough to name the call (`channel_id`, a
  /// type-ahead string). TMDB's `append_to_response` list is the path's business, not
  /// a second method.
  public nonisolated static func describe(_ request: URLRequest) -> (nameKey: String, detail: String) {
    let method = request.httpMethod ?? "GET"
    let url = request.url
    let host = url?.host ?? ""
    let path = url?.path ?? ""
    var detail = "\(method) \(host)\(path)"
    if let query = url?.query, !query.isEmpty, query.count <= 64, !query.contains("append_to_response") {
      detail += "?\(query)"
    }
    return (nameKey(host: host, path: path), detail)
  }

  /// Worker image routes (`/img/…`) and the title document are methods the page waits
  /// on. Poster CDNs, playlist bytes and `/t/p/` files are not — listing them turns the
  /// overlay into a scroll of pictures.
  public nonisolated static func reportsArtworkRequest(_ url: URL) -> Bool {
    let path = url.path
    if path.contains("/images/") || path.contains("/t/p/") { return false }
    return path.contains("/img/") || path.contains("/v1/title/") || path.contains("/admin/")
  }

  public nonisolated static func nameKey(host: String, path: String) -> String {
    let host = host.lowercased()
    if host.contains("kinopoisk") { return "Activity_Kinopoisk" }
    if host.contains("kpapp.link") {
      if path.contains("/kpapi/") { return "Activity_Kinopoisk" }
      if path.contains("config") { return "Activity_Sections" }
    }
    if host.contains("epg.pw") { return "Activity_Guide" }
    if host.contains("themoviedb.org") || path.hasPrefix("/3/") || path.contains("/v1/title/")
        || path.contains("/img/") || path.contains("/admin/") {
      return "Activity_TMDB"
    }
    if path.contains("autocomplete") { return "Activity_Search" }
    switch true {
    case path.contains("/history"): return "Activity_History"
    case path.contains("/watching"): return "Activity_Watching"
    case path.contains("/bookmarks"): return "Activity_Bookmarks"
    case path.contains("/collections"): return "Activity_Collections"
    case path.contains("/device"): return "Activity_Device"
    case path.contains("/user"), path.contains("/oauth2"): return "Activity_Session"
    case path.contains("/items/search"): return "Activity_Search"
    case path.contains("/items"): return "Activity_Catalog"
    case path.contains("/types"), path.contains("/genres"), path.contains("/countries"):
      return "Activity_Sections"
    default: return "Activity_Network"
    }
  }

  private func append(_ entry: Entry) {
    if suppressed.remove(entry.id) != nil { return }
    if endedEarly.remove(entry.id) != nil {
      var finished = entry
      finished.finishedAt = Date()
      inFlight.append(finished)
      scheduleRemoval(of: finished.id, startedAt: finished.startedAt)
      return
    }
    inFlight.append(entry)
  }

  private func finish(_ token: UUID, holdMinimum: Bool) {
    guard let index = inFlight.firstIndex(where: { $0.id == token }) else {
      if holdMinimum {
        endedEarly.insert(token)
      } else {
        suppressed.insert(token)
      }
      return
    }
    if !holdMinimum {
      removalTasks[token]?.cancel()
      removalTasks[token] = nil
      inFlight.remove(at: index)
      return
    }
    var entry = inFlight[index]
    if entry.finishedAt == nil {
      entry.finishedAt = Date()
      inFlight[index] = entry
    }
    scheduleRemoval(of: token, startedAt: entry.startedAt)
  }

  private func scheduleRemoval(of token: UUID, startedAt: Date) {
    guard removalTasks[token] == nil else { return }
    let remaining = Self.minimumVisible - Date().timeIntervalSince(startedAt)
    if remaining <= 0 {
      inFlight.removeAll { $0.id == token }
      return
    }
    removalTasks[token] = Task { @MainActor in
      try? await Task.sleep(for: .seconds(remaining))
      guard !Task.isCancelled else { return }
      inFlight.removeAll { $0.id == token }
      removalTasks[token] = nil
    }
  }
}
