import Foundation
import OSLog
import KinoPubLogging

/// Facade over configured metadata sources. Failures are swallowed — callers
/// treat an empty `TitleMetadata` as "draw the kino.pub page as today".
public actor MetadataService {
  private let sources: [any MetadataSource]
  private let cache: MetadataCache

  public init(sources: [any MetadataSource], cache: MetadataCache = MetadataCache()) {
    self.sources = sources
    self.cache = cache
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
