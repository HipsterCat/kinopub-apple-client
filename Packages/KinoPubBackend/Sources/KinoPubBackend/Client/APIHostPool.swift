//
//  APIHostPool.swift
//  KinoPubBackend
//
//  kino.pub answers the same API on several hosts. One of them returning 502 for minutes
//  (seen 2026-11-22: `GET /v1/user` 502 from api.service-kp.com, while other methods
//  still answered) must not leave the app without a backend when another host is fine.
//
//  The order and the "move on, remember the host that worked" rule follow kinopub-tizen
//  (MIT), js/api.js L9-L50 at d39a0b6:
//  https://github.com/k4be1/kinopub-tizen/blob/d39a0b625771ba52b2592867077b8e19ac8b61c7/js/api.js#L9-L50
//  It walks `HOSTS` on a transport error and stores `hostIdx`. Two differences here:
//  - a gateway answer (502/503/504) also moves on: that is the host's front saying it
//    cannot reach its own backend, which a mirror may well reach. Only for requests that
//    are safe to send twice (`Endpoint.isRepeatable`): a write that got a 5xx may already
//    have been applied, and several kino.pub writes are toggles (some even on GET).
//  - a timeout or a dropped connection moves on only for those requests, for the same
//    reason.
//

import Foundation
import Synchronization

/// The kino.pub API hosts, in the order they are tried, and the one in use now.
///
/// Sticky: the host that last answered stays first for every later request and across
/// launches, until it fails. Thread safe; one per app.
public final class APIHostPool: Sendable {

  /// One host. `url` carries the prefix the paths go under (`kino.watch/api`).
  public struct Host: Hashable, Sendable, Identifiable {
    public let url: URL
    public var id: String { url.absoluteString }
    /// `api.service-kp.com`, `kino.watch/api` — for diagnostics.
    public var label: String {
      let host = url.host ?? url.absoluteString
      let path = url.path
      return path.isEmpty || path == "/" ? host : host + path
    }
    public init(_ url: URL) { self.url = url }
  }

  /// What happened on a host most recently, for Settings › Diagnostics.
  public struct Outcome: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
      case answered(status: Int)
      case failed(reason: String)
    }
    public let kind: Kind
    public let date: Date
  }

  /// Everything Diagnostics shows, read at once.
  public struct Snapshot: Sendable, Equatable {
    public let hosts: [Host]
    public let currentIndex: Int
    public let outcomes: [String: Outcome]
    /// The last time the pool moved to another host, and why.
    public let lastSwitch: (date: Date, from: String, to: String, reason: String)?

    public static func == (lhs: Snapshot, rhs: Snapshot) -> Bool {
      lhs.hosts == rhs.hosts && lhs.currentIndex == rhs.currentIndex && lhs.outcomes == rhs.outcomes
        && lhs.lastSwitch?.date == rhs.lastSwitch?.date
    }
  }

  /// kino.pub's own API host first (it is the one `BaseURL` names and the one sign-in has
  /// always used), then the two mirrors kinopub-tizen falls back to. `api.srvkp.com` is
  /// also the host the PWA branch (`/api2/v1.1`, `ItemCollectionsRequest`) lives on;
  /// `kino.watch/api` is the website's own path to the API.
  public static let defaultHostURLs: [URL] = [
    URL(string: "https://api.service-kp.com")!,
    URL(string: "https://api.srvkp.com")!,
    URL(string: "https://kino.watch/api")!
  ]

  /// Posted on the main queue whenever the current host or an outcome changes.
  public static let didChangeNotification = Notification.Name("KinoPubAPIHostPoolDidChange")

  public let hosts: [Host]

  private let suite: DefaultsSuite
  private let storageKey: String

  private struct State {
    var index: Int
    var outcomes: [String: Outcome] = [:]
    var lastSwitch: (date: Date, from: String, to: String, reason: String)?
  }

  private let state: Mutex<State>

  /// - Parameters:
  ///   - primary: the configured `BaseURL`. Put first when it is not in `urls` already.
  ///   - urls: the hosts, in order.
  public init(primary: URL? = nil,
              urls: [URL] = APIHostPool.defaultHostURLs,
              defaults suite: DefaultsSuite = .standard,
              storageKey: String = "KinoPubAPIHost") {
    var ordered = urls.map(Self.normalized)
    if let primary {
      let primary = Self.normalized(primary)
      ordered.removeAll { $0 == primary }
      ordered.insert(primary, at: 0)
    }
    self.hosts = ordered.map(Host.init)
    self.suite = suite
    let defaults = suite.defaults
    self.storageKey = storageKey
    // Stored by URL, not index: a reordered list must not land on a different host.
    let stored = defaults.string(forKey: storageKey)
    var state = State(index: hosts.firstIndex { $0.id == stored } ?? 0)
    if let saved = defaults.dictionary(forKey: storageKey + ".lastSwitch"),
       let date = saved["date"] as? Date, let from = saved["from"] as? String,
       let to = saved["to"] as? String, let reason = saved["reason"] as? String {
      state.lastSwitch = (date, from, to, reason)
    }
    self.state = Mutex(state)
  }

  /// The host requests go to now.
  public var current: Host {
    hosts[state.withLock { $0.index }]
  }

  /// The hosts in the order one request tries them: the current one, then the rest in
  /// list order.
  public var attemptOrder: [Host] {
    let index = state.withLock { $0.index }
    return Array(hosts[index...]) + Array(hosts[..<index])
  }

  public func snapshot() -> Snapshot {
    state.withLock {
      Snapshot(hosts: hosts, currentIndex: $0.index, outcomes: $0.outcomes, lastSwitch: $0.lastSwitch)
    }
  }

  /// A host answered (any HTTP status): it becomes the current one.
  public func recordAnswer(from host: Host, status: Int) {
    update(host: host, outcome: .answered(status: status), makeCurrent: true, reason: nil)
  }

  /// A host failed in a way that moved the request on.
  public func recordFailure(of host: Host, reason: String) {
    update(host: host, outcome: .failed(reason: reason), makeCurrent: false, reason: reason)
  }

  /// Settings: start from this host from now on.
  public func select(_ host: Host) {
    update(host: host, outcome: nil, makeCurrent: true, reason: "chosen by hand")
  }

  private func update(host: Host, outcome: Outcome.Kind?, makeCurrent: Bool, reason: String?) {
    let changed: Bool = state.withLock { state in
      guard let hostIndex = hosts.firstIndex(of: host) else { return false }
      var changed = false
      if let outcome {
        state.outcomes[host.id] = Outcome(kind: outcome, date: Date())
        changed = true
      }
      if makeCurrent, hostIndex != state.index {
        state.lastSwitch = (Date(), hosts[state.index].label, host.label, reason ?? lastFailureReason(in: state, excluding: host) ?? "answered")
        state.index = hostIndex
        let defaults = suite.defaults
        defaults.set(host.id, forKey: storageKey)
        // Kept across launches with the host itself: "why am I on a mirror?" is asked
        // after the relaunch, not before.
        if let lastSwitch = state.lastSwitch {
          defaults.set(["date": lastSwitch.date, "from": lastSwitch.from,
                        "to": lastSwitch.to, "reason": lastSwitch.reason],
                       forKey: storageKey + ".lastSwitch")
        }
        changed = true
      }
      return changed
    }
    if changed {
      DispatchQueue.main.async {
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
      }
    }
  }

  /// Why the host before this one was left.
  private func lastFailureReason(in state: State, excluding host: Host) -> String? {
    let current = hosts[state.index]
    guard current != host, case .failed(let reason)? = state.outcomes[current.id]?.kind else { return nil }
    return reason
  }

  private static func normalized(_ url: URL) -> URL {
    var string = url.absoluteString
    while string.hasSuffix("/") { string.removeLast() }
    return URL(string: string) ?? url
  }
}

// MARK: - When to move on

extension APIHostPool {

  /// Whether a transport error should move the request to the next host.
  ///
  /// Failures before the request left (no DNS, no connection, TLS refused) are safe for
  /// any request. A timeout or a dropped connection may have reached the server, so only
  /// requests that are safe to send twice (`Endpoint.isRepeatable`) move on. Offline and cancelled never do: no other host will do better.
  static func shouldMoveOn(after error: Error, repeatable: Bool) -> Bool {
    guard let urlError = error as? URLError else { return false }
    switch urlError.code {
    case .cannotFindHost, .dnsLookupFailed, .cannotConnectToHost,
         .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
         .serverCertificateNotYetValid, .serverCertificateHasUnknownRoot, .clientCertificateRejected,
         .appTransportSecurityRequiresSecureConnection:
      return true
    case .timedOut, .networkConnectionLost, .badServerResponse, .cannotParseResponse,
         .zeroByteResource:
      return repeatable
    default:
      return false
    }
  }

  /// A gateway status (502/503/504): the host's front could not reach its own backend,
  /// which another host may well reach. Moves a repeatable request on.
  static func isGatewayFailure(_ status: Int) -> Bool {
    [502, 503, 504].contains(status)
  }

  /// A short, unlocalized reason for Diagnostics.
  static func reason(for error: Error) -> String {
    guard let urlError = error as? URLError else { return String(describing: type(of: error)) }
    switch urlError.code {
    case .cannotFindHost, .dnsLookupFailed: return "host not found"
    case .cannotConnectToHost: return "cannot connect"
    case .timedOut: return "timed out"
    case .networkConnectionLost: return "connection lost"
    case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
         .serverCertificateNotYetValid, .serverCertificateHasUnknownRoot, .clientCertificateRejected:
      return "TLS failed"
    case .badServerResponse, .cannotParseResponse, .zeroByteResource: return "bad response"
    default: return "URLError \(urlError.code.rawValue)"
    }
  }
}
