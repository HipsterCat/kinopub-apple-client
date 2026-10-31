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
    if let kinopoisk = identity.kinopoisk, kinopoisk > 0 {
      async let cardPart = fetchTitleCard(titleCard, identity: identity)
      async let proxyPart = fetchProxy(proxy, identity: identity)
      return mergeTitleCard(await cardPart, proxy: await proxyPart)
    }
    let cardPart = await fetchTitleCard(titleCard, identity: identity)
    let asking: MediaIdentity
    if let id = cardPart?.kinopoiskID, id > 0 {
      asking = identity.withKinopoisk(id)
    } else {
      asking = identity
    }
    let proxyPart = await fetchProxy(proxy, identity: asking)
    return mergeTitleCard(cardPart, proxy: proxyPart)
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

  private func mergeTitleCard(_ card: TitleMetadata?, proxy: TitleMetadata?) -> TitleMetadata {
    var result = TitleMetadata()
    if let card {
      result.merge(card)
      result.parts[.titleCard] = card
    }
    if let proxy {
      result.merge(proxy)
      result.parts[.kinopoiskProxy] = proxy
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
    var episodes: [EpisodeSchedule] = []
    for source in sources where source.isConfigured {
      do {
        let part = try await source.schedule(for: identity, season: season)
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
