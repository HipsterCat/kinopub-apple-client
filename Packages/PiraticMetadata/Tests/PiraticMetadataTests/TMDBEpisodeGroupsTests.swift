import XCTest
@testable import PiraticMetadata

final class TMDBEpisodeGroupsTests: XCTestCase {

  func testPreferredSummaryPrefersNamedProductionSeasons() {
    let results = [
      TMDBEpisodeGroupSummary(id: "abs", name: "Absolute", type: 1, groupCount: 1, episodeCount: 28),
      TMDBEpisodeGroupSummary(id: "6abff07397b158fd446873f3", name: "Seasons", type: 6,
                              groupCount: 2, episodeCount: 28),
      TMDBEpisodeGroupSummary(id: "cours", name: "Cours", type: 6, groupCount: 4, episodeCount: 28),
    ]
    XCTAssertEqual(TMDBEpisodeGroupsMapper.preferredSummary(from: results)?.id,
                   "6abff07397b158fd446873f3")
  }

  func testShouldApplyOnlyWhenFlat() {
    let flat = [SeasonSummary(seasonNumber: 1, episodeCount: 60)]
    XCTAssertTrue(TMDBEpisodeGroupsMapper.shouldApplyGroups(
      numberOfSeasons: 1, seasonSummaries: flat, groupCount: 3))
    let multi = [SeasonSummary(seasonNumber: 1), SeasonSummary(seasonNumber: 2)]
    XCTAssertFalse(TMDBEpisodeGroupsMapper.shouldApplyGroups(
      numberOfSeasons: 2, seasonSummaries: multi, groupCount: 3))
  }

  func testRemapSkipsSpecialsAndRenumbersWithinGroup() {
    let groups = [
      TMDBEpisodeGroupBucket(
        id: "sp", name: "Specials", order: 0,
        episodes: [TMDBEpisodeGroupEpisode(id: 1, name: "Xtra", overview: nil, airDate: nil,
                                           runtime: 10, stillPath: nil, seasonNumber: 0,
                                           episodeNumber: 1, voteAverage: nil, voteCount: nil,
                                           episodeType: nil)]
      ),
      TMDBEpisodeGroupBucket(
        id: "s1", name: "Season 1", order: 1,
        episodes: [
          TMDBEpisodeGroupEpisode(id: 10, name: "One", overview: "A", airDate: "2024-01-01",
                                  runtime: 50, stillPath: "/a.jpg", seasonNumber: 1,
                                  episodeNumber: 24, voteAverage: 7.2, voteCount: 11,
                                  episodeType: nil),
          TMDBEpisodeGroupEpisode(id: 11, name: "Two", overview: "B", airDate: "2024-01-08",
                                  runtime: 50, stillPath: nil, seasonNumber: 1,
                                  episodeNumber: 54, voteAverage: 0, voteCount: 0,
                                  episodeType: "finale"),
        ]
      ),
      TMDBEpisodeGroupBucket(
        id: "s2", name: "Season 2", order: 2,
        episodes: [
          TMDBEpisodeGroupEpisode(id: 20, name: "Three", overview: nil, airDate: nil,
                                  runtime: nil, stillPath: nil, seasonNumber: 1,
                                  episodeNumber: 55, voteAverage: nil, voteCount: nil,
                                  episodeType: nil),
        ]
      ),
    ]

    let remapped = TMDBEpisodeGroupsMapper.remap(groups: groups) { path in
      path.map { URL(string: "https://image.tmdb.org/t/p/w300\($0)")! }
    }

    XCTAssertEqual(remapped.summaries.map(\.seasonNumber), [1, 2])
    XCTAssertEqual(remapped.summaries.map(\.episodeCount), [2, 1])
    let s1 = remapped.schedule[1]!
    XCTAssertEqual(s1.map(\.episodeNumber), [1, 2])
    XCTAssertEqual(s1.map(\.name), ["One", "Two"])
    XCTAssertEqual(s1[0].overview, "A")
    XCTAssertEqual(s1[1].isSeasonFinale, true)
    // Absolute TMDB numbers must not leak as display episode numbers.
    XCTAssertNotEqual(s1.map(\.episodeNumber), [24, 54])
    XCTAssertEqual(remapped.schedule[2]?.first?.episodeNumber, 1)
  }
}
