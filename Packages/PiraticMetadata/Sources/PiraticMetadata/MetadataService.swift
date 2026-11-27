import Foundation
import OSLog
import PiraticLogging

/// Facade over configured metadata sources. Failures are swallowed — callers
/// treat an empty `TitleMetadata` as "draw the kino.pub page as today".
public actor MetadataService {
  private let sources: [any MetadataSource]
  private let cache: MetadataCache
  /// `GET /v2/title/by/kinopub/{id}`. Nil where the worker URL is not configured.
  private let titleCard: TitleCardSource?
  /// Logo / backdrop / poster by kino.pub id, for screens that only need a picture.
  /// Building a URL is not a lookup, so it is not behind the actor.
  public nonisolated let images: TitleImageRoute

  public init(sources: [any MetadataSource],
              cache: MetadataCache = MetadataCache(),
              images: TitleImageRoute = TitleImageRoute(baseURL: nil),
              titleCard: TitleCardSource? = nil) {
    self.sources = sources
    self.cache = cache
    self.images = images
    self.titleCard = titleCard
  }

  /// The detail page's other path: one title card, plus the Kinopoisk proxy
  /// **without staff**. No TMDB forwarder calls, and no keyed Kinopoisk — that stays
  /// the viewer's own key on the existing path. The card runs first when we still
  /// need its Kinopoisk id; otherwise the two run together.
  public func titleCardMetadata(for identity: MediaIdentity) async -> TitleMetadata {
    guard let titleCard, titleCard.isConfigured else {
      var missing = TitleMetadata()
      missing.debugLog = [SourceDebugEntry(
        source: .titleCard, endpoint: "v2/title", url: "(no proxy)",
        proxied: false, succeeded: false, responseBody: "TMDB proxy base URL is not configured."
      )]
      return missing
    }
    let proxy = sources.compactMap { $0 as? KinopoiskProxySource }.first
    // Trakt / Wikidata / MAL: Trakt and Wikidata can hand MAL an anime id; official MAL
    // then refreshes mean + num_scoring_users (12–24h cache) over Trakt's relayed copy.
    async let traktPart = fetchTrakt(identity: identity)
    async let omdbPart = fetchOMDb(identity: identity)
    async let doubanPart = fetchDouban(identity: identity)
    async let wikidataPart = fetchWikidata(identity: identity)
    async let myShowsPart = fetchMyShows(identity: identity)
    async let plexPart = fetchPlex(identity: identity)
    async let malPart = fetchMyAnimeList(identity: identity)
    if let kinopoisk = identity.kinopoisk, kinopoisk > 0 {
      async let cardPart = fetchTitleCard(titleCard, identity: identity)
      async let proxyPart = fetchProxy(proxy, identity: identity)
      let (card, proxyMeta, trakt, omdb, douban, myShows, plex, wikidata, mal) =
        await (cardPart, proxyPart, traktPart, omdbPart, doubanPart, myShowsPart, plexPart, wikidataPart, malPart)
      let officialMAL = await resolvedMyAnimeList(identity: identity, direct: mal, trakt: trakt, wikidata: wikidata)
      return mergeTitleCard(card, proxy: proxyMeta, trakt: trakt, omdb: omdb, douban: douban,
                            myShows: myShows, plex: plex, wikidata: wikidata, myAnimeList: officialMAL)
    }
    let cardPart = await fetchTitleCard(titleCard, identity: identity)
    let asking: MediaIdentity
    if let id = cardPart?.kinopoiskID, id > 0 {
      asking = identity.withKinopoisk(id)
    } else {
      asking = identity
    }
    let proxyPart = await fetchProxy(proxy, identity: asking)
    let (trakt, omdb, douban, myShows, plex, wikidata, mal) =
      await (traktPart, omdbPart, doubanPart, myShowsPart, plexPart, wikidataPart, malPart)
    let officialMAL = await resolvedMyAnimeList(identity: identity, direct: mal, trakt: trakt, wikidata: wikidata)
    return mergeTitleCard(cardPart, proxy: proxyPart, trakt: trakt, omdb: omdb, douban: douban,
                          myShows: myShows, plex: plex, wikidata: wikidata, myAnimeList: officialMAL)
  }

  /// `identity` with the ids linked in the worker, or nil when it holds no TMDB or IMDb
  /// id this identity lacks.
  public func linkedIdentity(for identity: MediaIdentity) async -> MediaIdentity? {
    guard let ids = await titleCard?.linkedIDs(kinopubID: identity.kinopubId) else { return nil }
    let linked = identity.withLinked(imdb: ids.imdb, tmdb: ids.tmdb)
    return linked == identity ? nil : linked
  }

  private func fetchTrakt(identity: MediaIdentity) async -> TitleMetadata? {
    guard let trakt = sources.compactMap({ $0 as? TraktSource }).first, trakt.isConfigured else { return nil }
    do {
      return try await trakt.titleMetadata(for: identity)
    } catch {
      Logger.metadata.error("Trakt failed: \(error.localizedDescription)")
      return nil
    }
  }

  /// The viewer's own OMDb key. Merged after Trakt, which outranks it on the scores both relay.
  private func fetchOMDb(identity: MediaIdentity) async -> TitleMetadata? {
    guard let omdb = sources.compactMap({ $0 as? OMDbSource }).first, omdb.isConfigured else { return nil }
    do {
      return try await omdb.titleMetadata(for: identity)
    } catch {
      Logger.metadata.error("OMDb failed: \(error.localizedDescription)")
      return nil
    }
  }

  private func fetchDouban(identity: MediaIdentity) async -> TitleMetadata? {
    guard let douban = sources.compactMap({ $0 as? DoubanSource }).first, douban.isConfigured else { return nil }
    do {
      return try await douban.titleMetadata(for: identity)
    } catch {
      Logger.metadata.error("Douban failed: \(error.localizedDescription)")
      return nil
    }
  }

  private func fetchWikidata(identity: MediaIdentity) async -> TitleMetadata? {
    guard let wikidata = sources.compactMap({ $0 as? WikidataSource }).first, wikidata.isConfigured else { return nil }
    do {
      return try await wikidata.titleMetadata(for: identity)
    } catch {
      Logger.metadata.error("Wikidata failed: \(error.localizedDescription)")
      return nil
    }
  }

  private func fetchMyShows(identity: MediaIdentity) async -> TitleMetadata? {
    guard identity.isSeries,
          let myShows = sources.compactMap({ $0 as? MyShowsSource }).first, myShows.isConfigured else { return nil }
    do {
      return try await myShows.titleMetadata(for: identity)
    } catch {
      Logger.metadata.error("MyShows failed: \(error.localizedDescription)")
      return nil
    }
  }

  private func fetchPlex(identity: MediaIdentity) async -> TitleMetadata? {
    guard let plex = sources.compactMap({ $0 as? PlexSource }).first, plex.isConfigured else { return nil }
    do {
      return try await plex.titleMetadata(for: identity)
    } catch {
      Logger.metadata.error("Plex failed: \(error.localizedDescription)")
      return nil
    }
  }

  private func fetchMyAnimeList(identity: MediaIdentity) async -> TitleMetadata? {
    guard let mal = sources.compactMap({ $0 as? MyAnimeListSource }).first, mal.isConfigured else { return nil }
    do {
      return try await mal.titleMetadata(for: identity)
    } catch {
      Logger.metadata.error("MyAnimeList failed: \(error.localizedDescription)")
      return nil
    }
  }

  /// Prefer the parallel MAL answer; if it missed and Trakt/Wikidata handed an anime id,
  /// ask MAL once more by that id so vote counts stay official.
  private func resolvedMyAnimeList(identity: MediaIdentity,
                                   direct: TitleMetadata?,
                                   trakt: TitleMetadata?,
                                   wikidata: TitleMetadata?) async -> TitleMetadata? {
    let hasFresh = direct?.externalRatings.contains {
      $0.kind == .myAnimeList && ($0.votes ?? 0) > 0
    } == true
    if hasFresh { return direct }
    let hint = identity.mal
      ?? wikidata?.malID
      ?? direct?.malID
      ?? MyAnimeListSource.animeID(from: trakt?.externalRatings.first { $0.kind == .myAnimeList }?.url)
      ?? MyAnimeListSource.animeID(from: wikidata?.externalLinks.first { $0.site == .myAnimeList }?.url)
    guard let hint else { return direct }
    return await fetchMyAnimeList(identity: identity.withMAL(hint)) ?? direct
  }

  private func fetchTitleCard(_ source: TitleCardSource, identity: MediaIdentity) async -> TitleMetadata? {
    do {
      return try await source.titleMetadata(for: identity)
    } catch {
      Logger.metadata.error("Title card failed: \(error.localizedDescription)")
      return nil
    }
  }

  private func fetchProxy(_ proxy: KinopoiskProxySource?, identity: MediaIdentity) async -> TitleMetadata? {
    guard let proxy else { return nil }
    do {
      return try await proxy.titleMetadata(for: identity, includeStaff: false)
    } catch {
      Logger.metadata.error("Kinopoisk proxy (no staff) failed: \(error.localizedDescription)")
      return nil
    }
  }

  private func mergeTitleCard(_ card: TitleMetadata?, proxy: TitleMetadata?,
                              trakt: TitleMetadata? = nil, omdb: TitleMetadata? = nil,
                              douban: TitleMetadata? = nil, myShows: TitleMetadata? = nil,
                              plex: TitleMetadata? = nil, wikidata: TitleMetadata? = nil,
                              myAnimeList: TitleMetadata? = nil) -> TitleMetadata {
    var result = TitleMetadata()
    if let card {
      result.merge(card)
      result.parts[.titleCard] = card
    }
    if let proxy {
      result.merge(proxy)
      result.parts[.kinopoiskProxy] = proxy
    }
    if let trakt {
      result.merge(trakt)
      result.parts[.trakt] = trakt
    }
    // After Trakt: official MAL mean + num_scoring_users replace Trakt's relayed MAL
    // when the vote count is higher (`mergeExternalRating`).
    if let myAnimeList {
      result.merge(myAnimeList)
      result.parts[.myAnimeList] = myAnimeList
    }
    if let omdb {
      result.merge(omdb)
      result.parts[.omdb] = omdb
    }
    if let douban {
      result.merge(douban)
      result.parts[.douban] = douban
    }
    if let myShows {
      result.merge(myShows)
      result.parts[.myShows] = myShows
    }
    if let plex {
      result.merge(plex)
      result.parts[.plex] = plex
    }
    // Last: it only fills what the sources above left empty.
    if let wikidata {
      result.merge(wikidata)
      result.parts[.wikidata] = wikidata
    }
    return result
  }

  /// One call per detail page. Sources run in parallel; each contributes what it can.
  public func metadata(for identity: MediaIdentity) async -> TitleMetadata {
    var result = TitleMetadata()
    let configured = sources.filter(\.isConfigured)
    guard !configured.isEmpty else { return result }

    // Parts are merged in the configured source order, never in arrival order: the
    // overlay gap-fills, so "whoever answered first" would otherwise decide its fields.
    var parts: [Int: TitleMetadata] = [:]
    await withTaskGroup(of: (Int, TitleMetadata?).self) { group in
      for (index, source) in configured.enumerated() {
        group.addTask {
          do {
            if let batch = try await source.titleMetadata(for: identity) {
              return (index, batch)
            }
            // Fall back to piecemeal contributions.
            var part = TitleMetadata()
            part.attribution.insert(source.id)
            if let art = try await source.artwork(for: identity) {
              part.artwork = art
            }
            let cast = try await source.cast(for: identity)
            if !cast.isEmpty { part.cast = cast }
            if let next = try await source.nextEpisode(for: identity) {
              part.nextEpisode = next
            }
            return (index, part)
          } catch {
            Logger.metadata.error("Metadata source \(source.id.rawValue) failed: \(error.localizedDescription)")
            return (index, nil)
          }
        }
      }
      for await (index, part) in group {
        if let part { parts[index] = part }
      }
    }
    for index in parts.keys.sorted() {
      guard let part = parts[index] else { continue }
      result.merge(part)
      result.parts[configured[index].id] = part
    }
    return result
  }

  /// What to skip in one episode (or a film: season and episode nil), every skip-times
  /// source asked at once. The first source in `sources` that knows a kind wins it (SkipDB
  /// before TheIntroDB), the next ones fill the kinds it lacks. Nil when nobody knows any.
  public func skipSegments(for identity: MediaIdentity, season: Int?, episode: Int?,
                           durationMs: Int?) async -> SkipSegments? {
    let configured = sources.filter(\.isConfigured)
    let answers = await withTaskGroup(of: (Int, SkipSegments?).self) { group in
      for (index, source) in configured.enumerated() {
        group.addTask {
          do {
            return (index, try await source.segments(for: identity, season: season,
                                                     episode: episode, durationMs: durationMs))
          } catch {
            return (index, nil)
          }
        }
      }
      var found: [Int: SkipSegments] = [:]
      for await (index, segments) in group {
        if let segments { found[index] = segments }
      }
      return found
    }
    var result = SkipSegments()
    for index in answers.keys.sorted() {
      result = result.filling(from: answers[index])
    }
    return result.isEmpty ? nil : result
  }

  /// TMDB's posters for one season, to look through (the season card's «Change Image»).
  public func seasonPosters(for identity: MediaIdentity, season: Int) async -> [URL] {
    guard let tmdb = sources.compactMap({ $0 as? TMDBSource }).first else { return [] }
    return await tmdb.seasonPosters(for: identity, season: season)
  }

  public func schedule(for identity: MediaIdentity, season: Int) async -> [EpisodeSchedule] {
    await schedule(for: identity, season: season, language: nil)
  }

  /// `language` nil is each source's own. An explicit tag is asked of TMDB only —
  /// that is the English episode list beside the configured one.
  public func schedule(for identity: MediaIdentity, season: Int, language: String?) async -> [EpisodeSchedule] {
    var episodes: [EpisodeSchedule] = []
    for source in sources where source.isConfigured {
      do {
        let part: [EpisodeSchedule]
        if let language, let tmdb = source as? TMDBSource {
          part = try await tmdb.schedule(for: identity, season: season, language: language)
        } else if language != nil {
          continue
        } else {
          part = try await source.schedule(for: identity, season: season)
        }
        if !part.isEmpty {
          episodes = part
          break
        }
      } catch {
        Logger.metadata.error("Schedule \(source.id.rawValue) s\(season) failed: \(error.localizedDescription)")
      }
    }
    return episodes
  }

  /// Every season's episodes in the configured language and in English, a few at a
  /// time. Callers align the result onto kino.pub; they do not trust one season index.
  public func episodeGrid(for identity: MediaIdentity, seasons: [Int]) async -> [EpisodeSchedule] {
    let jobs: [(Int, String?)] = Array(Set(seasons)).filter { $0 >= 0 }.sorted().flatMap { number in
      [(number, nil as String?), (number, "en-US")]
    }
    var results: [EpisodeSchedule] = []
    var index = 0
    while index < jobs.count {
      let end = min(index + 4, jobs.count)
      let slice = Array(jobs[index..<end])
      index = end
      await withTaskGroup(of: [EpisodeSchedule].self) { group in
        for job in slice {
          group.addTask {
            await self.schedule(for: identity, season: job.0, language: job.1)
          }
        }
        for await part in group {
          results.append(contentsOf: part)
        }
      }
    }
    return results
  }

  /// Person bio for the credits page. Failures are swallowed — the page keeps the
  /// name and any photo already passed from the cast rail.
  public func person(id: Int) async -> PersonMetadata {
    var result = PersonMetadata()
    for source in sources where source.isConfigured {
      do {
        if let part = try await source.personMetadata(id: id) {
          result.merge(part)
        }
      } catch {
        Logger.metadata.error("Person \(source.id.rawValue) \(id) failed: \(error.localizedDescription)")
      }
    }
    return result
  }
}
