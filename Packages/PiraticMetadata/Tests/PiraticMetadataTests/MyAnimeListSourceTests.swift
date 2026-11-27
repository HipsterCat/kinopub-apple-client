import XCTest
@testable import PiraticMetadata

final class MyAnimeListSourceTests: XCTestCase {

  private let detailsJSON = """
  {
    "id": 5114,
    "title": "Fullmetal Alchemist: Brotherhood",
    "mean": 9.1,
    "rank": 1,
    "popularity": 3,
    "num_scoring_users": 2100000,
    "statistics": {
      "status": {
        "watching": "150000",
        "completed": "1800000",
        "on_hold": "40000",
        "dropped": "20000",
        "plan_to_watch": "300000"
      },
      "num_list_users": 2310000
    }
  }
  """

  func testDetailsMapMeanVotesRankAndStatistics() throws {
    let dto = try JSONDecoder().decode(MALAnimeDetailsDTO.self, from: Data(detailsJSON.utf8))
    var meta = TitleMetadata()
    MyAnimeListSource.apply(dto, to: &meta)

    XCTAssertEqual(meta.malID, 5114)
    let rating = try XCTUnwrap(meta.externalRatings.first { $0.kind == .myAnimeList })
    XCTAssertEqual(rating.value, 9.1, accuracy: 0.001)
    XCTAssertEqual(rating.votes, 2_100_000)
    XCTAssertEqual(rating.url?.absoluteString, "https://myanimelist.net/anime/5114")

    let stats = try XCTUnwrap(meta.myAnimeListStats)
    XCTAssertEqual(stats.rank, 1)
    XCTAssertEqual(stats.popularity, 3)
    XCTAssertEqual(stats.watching, 150_000)
    XCTAssertEqual(stats.completed, 1_800_000)
    XCTAssertEqual(stats.planToWatch, 300_000)
    XCTAssertEqual(stats.numListUsers, 2_310_000)
  }

  func testAnimeIDParsedFromMALURL() {
    let url = URL(string: "https://myanimelist.net/anime/5114/Fullmetal_Alchemist__Brotherhood")
    XCTAssertEqual(MyAnimeListSource.animeID(from: url), 5114)
    XCTAssertEqual(MyAnimeListSource.animeID(fromLink: "https://myanimelist.net/anime/20"), 20)
    XCTAssertNil(MyAnimeListSource.animeID(fromLink: "https://myanimelist.net/manga/1"))
  }

  func testSearchPrefersYearMatch() throws {
    let payload = """
    {"data":[
      {"node":{"id":1,"title":"Other","start_date":"2003-01-01","start_season":{"year":2003,"season":"winter"}}},
      {"node":{"id":5114,"title":"Fullmetal Alchemist: Brotherhood","start_date":"2009-04-05","start_season":{"year":2009,"season":"spring"}}}
    ]}
    """
    let dto = try JSONDecoder().decode(MALAnimeSearchDTO.self, from: Data(payload.utf8))
    XCTAssertEqual(
      MyAnimeListSource.pick(from: dto.data ?? [], year: 2009, title: "Fullmetal Alchemist: Brotherhood"),
      5114)
  }

  func testMergePrefersFresherMALVotes() throws {
    var base = TitleMetadata()
    base.externalRatings = [
      ExternalRating(kind: .myAnimeList, value: 8.5, votes: 46_305,
                     url: URL(string: "https://myanimelist.net/anime/1"))
    ]
    var official = TitleMetadata()
    official.externalRatings = [
      ExternalRating(kind: .myAnimeList, value: 8.6, votes: 64_129,
                     url: URL(string: "https://myanimelist.net/anime/1"))
    ]
    base.merge(official)
    XCTAssertEqual(base.externalRatings.first?.votes, 64_129)
    XCTAssertEqual(try XCTUnwrap(base.externalRatings.first?.value), 8.6, accuracy: 0.001)
  }

  func testCredentialsRejectPlaceholders() {
    XCTAssertNil(MyAnimeListCredentials.sanitize("$(MAL_CLIENT_ID)"))
    XCTAssertNil(MyAnimeListCredentials.sanitize("  "))
    XCTAssertEqual(MyAnimeListCredentials.sanitize("abc123"), "abc123")
  }

  func testShikimoriOAuthNamesAndRedirect() {
    XCTAssertEqual(ShikimoriOAuth.userAgent, "Piratic")
    XCTAssertEqual(ShikimoriOAuth.redirectURI, "piratic://shikimori")
    XCTAssertEqual(ShikimoriOAuth.clientIDEnvName, "SHIKIMORI_CLIENT_ID")
    XCTAssertEqual(ShikimoriOAuth.clientSecretEnvName, "SHIKIMORI_CLIENT_SECRET")
    XCTAssertNil(ShikimoriOAuth.clientSecret(environment: [:]))
    let url = ShikimoriOAuth.authorizationURL(clientID: "test-id")
    XCTAssertEqual(url?.host, "shikimori.one")
    let query = url?.query ?? ""
    XCTAssertTrue(query.contains("piratic"), query)
    XCTAssertTrue(query.contains("user_rates"), query)

    XCTAssertEqual(PiraticOAuthRedirect(url: URL(string: "piratic://myanimelist?code=1")!),
                   .myAnimeList(URL(string: "piratic://myanimelist?code=1")!))
    XCTAssertEqual(PiraticOAuthRedirect(url: URL(string: "piratic://shikimori?code=1")!),
                   .shikimori(URL(string: "piratic://shikimori?code=1")!))
    XCTAssertNil(PiraticOAuthRedirect(url: URL(string: "piratic://item/1")!))
  }
}
