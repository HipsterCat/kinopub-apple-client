import Foundation
import OSLog
import KinoPubLogging

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
    // Trakt asks by IMDb id, which the kino.pub item already has: it runs beside both.
    async let traktPart = fetchTrakt(identity: identity)
    async let omdbPart = fetchOMDb(identity: identity)
    async let doubanPart = fetchDouban(identity: identity)
    async let wikidataPart = fetchWikidata(identity: identity)
    async let myShowsPart = fetchMyShows(identity: identity)
    if let kinopoisk = identity.kinopoisk, kinopoisk > 0 {
      async let cardPart = fetchTitleCard(titleCard, identity: identity)
      async let proxyPart = fetchProxy(proxy, identity: identity)
      return mergeTitleCard(await cardPart, proxy: await proxyPart, trakt: await traktPart, omdb: await omdbPart,
                            douban: await doubanPart,
                          myShows: await myShowsPart, wikidata: await wikidataPart)
    }
    let cardPart = await fetchTitleCard(titleCard, identity: identity)
    let asking: MediaIdentity
    if let id = cardPart?.kinopoiskID, id > 0 {
      asking = identity.withKinopoisk(id)
    } else {
      asking = identity
    }
    let proxyPart = await fetchProxy(proxy, identity: asking)
    return mergeTitleCard(cardPart, proxy: proxyPart, trakt: await traktPart, omdb: await omdbPart,
                          douban: await doubanPart,
                          myShows: await myShowsPart, wikidata: await wikidataPart)
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
                              wikidata: TitleMetadata? = nil) -> TitleMetadata {
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
