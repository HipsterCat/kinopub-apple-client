//
//  WikidataSourceTests.swift
//
//  Claims in the shape `wbgetentities` returns them, values from Q172241 (The Shawshank
//  Redemption) as probed on 2026-11-09.
//

import XCTest
@testable import KinoPubMetadata

final class WikidataSourceTests: XCTestCase {
  private func id(_ property: String, _ value: String) -> String {
    #""\#(property)": [{"mainsnak": {"datavalue": {"value": "\#(value)", "type": "string"}}}]"#
  }

  private var shawshank: String {
    """
    {"entities": {"Q172241": {
      "sitelinks": {"enwiki": {"title": "The Shawshank Redemption"}, "ruwiki": {"title": "Побег из Шоушенка"}},
      "claims": {
        \(id("P345", "tt0111161")), \(id("P4947", "278")), \(id("P2603", "326")), \(id("P4529", "1292052")),
        \(id("P6127", "the-shawshank-redemption")), \(id("P1712", "movie/the-shawshank-redemption")),
        \(id("P1258", "m/shawshank_redemption")), \(id("P8013", "movies/the-shawshank-redemption-1994")),
        "P2142": [
          {"mainsnak": {"datavalue": {"value": {"amount": "+28817291", "unit": "http://www.wikidata.org/entity/Q4917"}}},
           "qualifiers": {"P3005": [{"datavalue": {"value": {"entity-type": "item", "id": "Q13780930"}}}]}},
          {"mainsnak": {"datavalue": {"value": {"amount": "+28767189", "unit": "http://www.wikidata.org/entity/Q4917"}}},
           "qualifiers": {"P3005": [{"datavalue": {"value": {"entity-type": "item", "id": "Q30"}}}]}}
        ],
        "P2130": [{"mainsnak": {"datavalue": {"value": {"amount": "+25000000", "unit": "http://www.wikidata.org/entity/Q4917"}}}}],
        "P166": [{"mainsnak": {"datavalue": {"value": {"id": "Q4745055"}}}}, {"mainsnak": {"datavalue": {"value": {"id": "Q1966965"}}}}],
        "P1411": [{"mainsnak": {"datavalue": {"value": {"id": "Q102427"}}}}],
        "P2047": [{"mainsnak": {"datavalue": {"value": {"amount": "+142", "unit": "http://www.wikidata.org/entity/Q7727"}}}}],
        "P154": [{"mainsnak": {"snaktype": "somevalue"}}]
      }}}}
    """
  }

  func testEntityMapsIdsLinksMoneyAndAwards() throws {
    let response = try JSONDecoder().decode(WikidataEntitiesDTO.self, from: Data(shawshank.utf8))
    let entity = try XCTUnwrap(response.entities["Q172241"])
    var meta = TitleMetadata()
    WikidataSource.apply(entity, qid: "Q172241", isSeries: false, language: "ru", to: &meta)
    XCTAssertEqual(meta.wikidataID, "Q172241")
    XCTAssertEqual(meta.kinopoiskID, 326)
    XCTAssertEqual(meta.tmdbId, 278)
    XCTAssertEqual(meta.boxOfficeWorldwideUSD, 28_817_291)
    XCTAssertEqual(meta.boxOfficeUSD, 28_767_189)
    XCTAssertEqual(meta.budget, 25_000_000)
    XCTAssertEqual(meta.awardCounts, AwardCounts(wins: 2, nominations: 1))
    XCTAssertEqual(meta.externalLinks.map(\.site),
                   [.wikipedia, .kinopoisk, .douban, .letterboxd, .metacritic, .rottenTomatoes, .trakt, .wikidata])
    XCTAssertEqual(meta.externalLinks.first?.url.host(), "ru.wikipedia.org")
    XCTAssertEqual(meta.externalLinks[2].url.absoluteString, "https://movie.douban.com/subject/1292052/")
  }

  func testOtherSourcesWinOverWikidata() {
    var omdb = TitleMetadata()
    omdb.boxOfficeUSD = 1
    var wikidata = TitleMetadata()
    wikidata.boxOfficeUSD = 2
    wikidata.boxOfficeWorldwideUSD = 3
    var merged = TitleMetadata()
    merged.merge(omdb)
    merged.merge(wikidata)
    XCTAssertEqual(merged.boxOfficeUSD, 1)
    XCTAssertEqual(merged.boxOfficeWorldwideUSD, 3)
  }

  func testSearchHitIsTheItem() throws {
    let json = #"{"query": {"searchinfo": {"totalhits": 1}, "search": [{"ns": 0, "title": "Q1079", "pageid": 1}]}}"#
    let dto = try JSONDecoder().decode(WikidataSearchDTO.self, from: Data(json.utf8))
    XCTAssertEqual(dto.query?.search.first?.title, "Q1079")
  }
}
