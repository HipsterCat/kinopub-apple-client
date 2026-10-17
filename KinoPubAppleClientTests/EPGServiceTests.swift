//
//  EPGServiceTests.swift
//  KinoPubAppleClientTests
//
//  The channel guide (epg.pw, one channel per request): what an answer decodes to, which
//  channels get whose schedule, that a schedule is served from cache while fresh, and that a
//  failed fetch falls back to the stale copy instead of emptying the grid's second lines.
//

import XCTest
import KinoPubBackend
@testable import KinoPub

final class EPGServiceTests: XCTestCase {

  private static func answer(_ entries: [(String?, String)]) -> Data {
    let list = entries.map { title, start -> [String: Any] in
      var entry: [String: Any] = ["start_date": start, "desc": NSNull()]
      if let title { entry["title"] = title }
      return entry
    }
    return try! JSONSerialization.data(withJSONObject: ["name": "Channel", "epg_list": list])
  }

  /// A programme ends where the next begins; the answer's order is not trusted (and offsets
  /// are honoured — 13:30+03:00 is 10:30Z); an entry with no title is dropped but still ends
  /// the one before it; the last programme gets a length of its own.
  func testDecodeChainsStopsFromTheNextStart() throws {
    let data = Self.answer([("Second", "2026-10-17T11:00:00+00:00"),
                            ("First", "2026-10-17T10:00:00+00:00"),
                            (nil, "2026-10-17T12:00:00+00:00"),
                            ("Middle", "2026-10-17T13:30:00+03:00"),
                            ("Last", "2026-10-17T12:30:00+00:00")])
    let iso = ISO8601DateFormatter()
    let programs = try EPGServiceImpl.decode(data)
    XCTAssertEqual(programs.map(\.title), ["First", "Middle", "Second", "Last"])
    XCTAssertEqual(programs[0].stop, iso.date(from: "2026-10-17T10:30:00Z"))
    XCTAssertEqual(programs[2].stop, iso.date(from: "2026-10-17T12:00:00Z"), "ends at the untitled entry's start")
    XCTAssertGreaterThan(programs[3].stop, programs[3].start)
    XCTAssertEqual(programs.live(at: iso.date(from: "2026-10-17T10:29:00Z")!)?.title, "First")
    XCTAssertNil(programs.live(at: iso.date(from: "2026-10-17T12:10:00Z")!), "the untitled slot shows nothing")
  }

  /// Two kino.pub channels on one guide channel (a 4K copy) cost one request and both get the
  /// schedule; a channel the table does not know is left out and asks nothing.
  func testSharedGuideChannelIsFetchedOnce() async {
    let now = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-600))
    StubProtocol.reset(answer: Self.answer([("Live", now)]))
    let service = EPGServiceImpl(session: StubProtocol.session, table: [20: "6317", 166: "6317"],
                                 cacheDirectory: nil)
    let channels = [TVChannel(id: 20, title: "Sky Sports F1", stream: "s"),
                    TVChannel(id: 166, title: "Sky Sports F1 4K", stream: "s"),
                    TVChannel(id: 999, title: "Unknown", stream: "s")]
    let schedules = await service.schedules(for: channels)
    XCTAssertEqual(StubProtocol.requests, ["https://epg.pw/api/epg.json?channel_id=6317"])
    XCTAssertEqual(schedules[20]?.first?.title, "Live")
    XCTAssertEqual(schedules[166], schedules[20])
    XCTAssertNil(schedules[999])
  }

  /// Fresh: served from memory, no request. A failed refetch keeps the old schedule.
  func testCacheAndStaleOnFailure() async {
    let now = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-600))
    StubProtocol.reset(answer: Self.answer([("Live", now)]))
    let service = EPGServiceImpl(session: StubProtocol.session, table: [1: "5755"], cacheDirectory: nil)
    let channel = [TVChannel(id: 1, title: "МАТЧ! ТВ", stream: "s")]
    _ = await service.schedules(for: channel)
    _ = await service.schedules(for: channel)
    XCTAssertEqual(StubProtocol.requests.count, 1, "a fresh schedule was fetched again")

    // Past freshness, and the guide is down: the stale schedule still answers.
    let disk = FileManager.default.temporaryDirectory.appendingPathComponent("EPGServiceTests-\(UUID().uuidString)")
    let writer = EPGServiceImpl(session: StubProtocol.session, table: [1: "5755"], cacheDirectory: disk)
    _ = await writer.schedules(for: channel)
    let file = disk.appendingPathComponent("epgpw-5755.json")
    let data = try! Data(contentsOf: file)
    var json = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
    json["fetchedAt"] = (json["fetchedAt"] as! Double) - EPGServiceImpl.freshness - 60
    try! JSONSerialization.data(withJSONObject: json).write(to: file)
    StubProtocol.reset(answer: nil)
    let reader = EPGServiceImpl(session: StubProtocol.session, table: [1: "5755"], cacheDirectory: disk)
    let schedules = await reader.schedules(for: channel)
    XCTAssertEqual(StubProtocol.requests.count, 1, "a stale schedule was not refetched")
    XCTAssertEqual(schedules[1]?.first?.title, "Live", "a failed fetch emptied the schedule")
  }

  /// Every entry of the shipped table points at a guide channel once per kino.pub channel,
  /// and only 4K copies share one.
  func testShippedTableSharesOnlyFor4KCopies() {
    let shared = Dictionary(grouping: EPGChannelTable.epgPW, by: \.value).filter { $0.value.count > 1 }
    XCTAssertEqual(Set(shared.keys), ["6317", "7673"])
  }
}

/// Answers every request with `answer` (or a network failure when nil) and records the URLs.
final class StubProtocol: URLProtocol {
  nonisolated(unsafe) static var answer: Data?
  nonisolated(unsafe) static var requests: [String] = []
  private static let lock = NSLock()

  static func reset(answer: Data?) {
    lock.withLock {
      self.answer = answer
      requests = []
    }
  }

  static var session: URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubProtocol.self]
    return URLSession(configuration: configuration)
  }

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    let answer = Self.lock.withLock { () -> Data? in
      Self.requests.append(request.url?.absoluteString ?? "")
      return Self.answer
    }
    guard let answer, let url = request.url else {
      client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
      return
    }
    client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                        cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: answer)
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}
