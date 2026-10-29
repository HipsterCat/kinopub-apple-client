import XCTest
@testable import KinoPubLogging

@MainActor
final class KinoPubLoggingTests: XCTestCase {
  override func tearDown() async throws {
    NetworkActivity.minimumVisible = 2
    try await super.tearDown()
  }

  func testDescribeNamesEveryStackThePageWaitsOn() {
    func described(_ string: String) -> (nameKey: String, detail: String) {
      NetworkActivity.describe(URLRequest(url: URL(string: string)!))
    }

    let tmdb = described("https://tmdb-proxy.example.workers.dev/3/tv/1396?language=ru-RU")
    XCTAssertEqual(tmdb.nameKey, "Activity_TMDB")
    XCTAssertEqual(tmdb.detail, "GET tmdb-proxy.example.workers.dev/3/tv/1396?language=ru-RU")

    let logo = described("https://tmdb-proxy.example.workers.dev/img/logo/by/kinopub/7?w=960")
    XCTAssertEqual(logo.nameKey, "Activity_TMDB")
    XCTAssertTrue(logo.detail.hasPrefix("GET tmdb-proxy.example.workers.dev/img/logo/"))

    let direct = described("https://kinopoiskapiunofficial.tech/api/v2.2/films/301/facts")
    XCTAssertEqual(direct.nameKey, "Activity_Kinopoisk")
    XCTAssertTrue(direct.detail.contains("kinopoiskapiunofficial.tech/api/v2.2/films/301/facts"))

    let proxy = described("https://kpapp.link/kpapi/films/301/staff")
    XCTAssertEqual(proxy.nameKey, "Activity_Kinopoisk")

    let config = described("https://www.kpapp.link/config.json")
    XCTAssertEqual(config.nameKey, "Activity_Sections")

    let guide = described("https://epg.pw/api/epg.json?channel_id=6317")
    XCTAssertEqual(guide.nameKey, "Activity_Guide")
    XCTAssertTrue(guide.detail.contains("channel_id=6317"))

    let search = described("https://api.kinopub.link/v1.1/autocomplete?query=matrix")
    XCTAssertEqual(search.nameKey, "Activity_Search")

    let catalog = described("https://api.service-kp.com/v1/items")
    XCTAssertEqual(catalog.nameKey, "Activity_Catalog")

    let history = described("https://api.service-kp.com/v1/history")
    XCTAssertEqual(history.nameKey, "Activity_History")

    let longQuery = "https://tmdb-proxy.example.workers.dev/3/movie/550?append_to_response=credits,images,videos"
    let details = described(longQuery)
    XCTAssertEqual(details.nameKey, "Activity_TMDB")
    XCTAssertFalse(details.detail.contains("append_to_response"))
  }

  func testArtworkRoutesAreTheWorkerMethodsNotTheCDNs() {
    XCTAssertTrue(NetworkActivity.reportsArtworkRequest(
      URL(string: "https://worker.example/img/backdrop/by/kinopub/7")!))
    XCTAssertTrue(NetworkActivity.reportsArtworkRequest(
      URL(string: "https://worker.example/v1/title/by/kinopub/7")!))
    XCTAssertFalse(NetworkActivity.reportsArtworkRequest(
      URL(string: "https://m.staticpop.net/poster/item/big/1.jpg")!))
    XCTAssertFalse(NetworkActivity.reportsArtworkRequest(
      URL(string: "https://m.pushbr.com/actors/ab.jpg")!))
    XCTAssertFalse(NetworkActivity.reportsArtworkRequest(
      URL(string: "https://worker.example/t/p/w300/abc.jpg")!))
    XCTAssertFalse(NetworkActivity.reportsArtworkRequest(
      URL(string: "https://kinopoiskapiunofficial.tech/images/posters/kp/1.jpg")!))
  }

  func testAFastRequestStaysUntilTwoSecondsAfterItStarted() async {
    NetworkActivity.minimumVisible = 0.35
    let id = NetworkActivity.begin(nameKey: "Activity_TMDB", detail: "GET worker.example/3/find/tt1")
    let appeared = await waitUntil { NetworkActivity.shared.inFlight.contains { $0.id == id } }
    XCTAssertTrue(appeared)

    NetworkActivity.end(id)
    let settled = await waitUntil {
      NetworkActivity.shared.inFlight.first { $0.id == id }?.finishedAt != nil
    }
    XCTAssertTrue(settled)
    XCTAssertTrue(NetworkActivity.shared.inFlight.contains { $0.id == id })

    try? await Task.sleep(for: .milliseconds(500))
    XCTAssertFalse(NetworkActivity.shared.inFlight.contains { $0.id == id })
  }

  func testACancelledRequestDoesNotLinger() async {
    NetworkActivity.minimumVisible = 2
    let id = NetworkActivity.begin(nameKey: "Activity_TMDB", detail: "GET worker.example/img/logo/by/kinopub/1")
    let appeared = await waitUntil { NetworkActivity.shared.inFlight.contains { $0.id == id } }
    XCTAssertTrue(appeared)

    NetworkActivity.end(id, holdMinimum: false)
    let gone = await waitUntil { !NetworkActivity.shared.inFlight.contains { $0.id == id } }
    XCTAssertTrue(gone)
  }

  private func waitUntil(_ predicate: @MainActor () -> Bool) async -> Bool {
    let start = Date()
    while Date().timeIntervalSince(start) < 1 {
      if predicate() { return true }
      try? await Task.sleep(for: .milliseconds(20))
    }
    return predicate()
  }
}
