//
//  MediaLinksResolver.swift
//  Piratic
//
//  Fills in the video links a `nolinks=1` details call left out.
//
//  A series detail response carries a full link ladder for every episode of every
//  season — on a long-running show that is most of the payload, and at most one
//  episode's worth is ever used. So the detail page asks for the item without links
//  (`ItemDetailsRequest(excludeLinks:)`) and the links for a single episode are fetched
//  here, from `/v1/items/media-links?mid=`, at the moment that episode is needed.
//
//  `Episode` is a value: `filled(_:using:)` gives back a copy with its links, and the
//  answer is remembered here, so whoever holds another copy — the seasons rail, the
//  player, next-episode — gets it too. A second play costs no second request.
//

import Foundation
import KinoPubBackend
import PiraticLogging
import OSLog

@MainActor
final class MediaLinksResolver {

  static let shared = MediaLinksResolver()

  /// One request per media id, however many callers ask at once.
  private var inFlight: [Int: Task<MediaLinks?, Never>] = [:]

  /// What came back, by media id. The links are signed and expire, so an answer is not
  /// kept for a session that stays open for days.
  private var resolved: [Int: (links: MediaLinks, at: Date)] = [:]
  private static let lifetime: TimeInterval = 30 * 60

  /// `episode` with its files and subtitles, if it has none. Unchanged when there is still
  /// nothing playable — the caller shows the failure, this does not throw over a stream
  /// that may yet be resolvable from a local download.
  func filled(_ episode: Episode, using service: VideoContentService) async -> Episode {
    // Not `files.isEmpty`: a `nolinks=1` payload still lists the quality ladder, it just
    // gives no links for any rung of it.
    guard !episode.files.hasPlayableURLs else { return episode }
    guard let links = await links(forMediaId: episode.id, using: service) else { return episode }
    var filled = episode
    filled.files = links.files
    // `nolinks` is documented as dropping video links; whether it also drops subtitle
    // links is not, so only fill what is actually missing.
    if filled.subtitles.isEmpty {
      filled.subtitles = links.subtitles
    }
    Logger.app.info(
      "media-links mid=\(episode.id) files=\(links.files.count) subs=\(links.subtitles.count) best=\(links.files.first?.quality ?? "none")"
    )
    return filled
  }

  /// Another account's links are not this one's.
  func clear() {
    resolved = [:]
  }

  func links(forMediaId id: Int, using service: VideoContentService) async -> MediaLinks? {
    if let known = resolved[id], Date().timeIntervalSince(known.at) < Self.lifetime { return known.links }
    if let existing = inFlight[id] { return await existing.value }
    let task = Task<MediaLinks?, Never> {
      do {
        return try await service.fetchMediaLinks(mediaId: id)
      } catch {
        Logger.app.error("media-links failed for \(id): \(error)")
        return nil
      }
    }
    inFlight[id] = task
    let result = await task.value
    inFlight[id] = nil
    if let result, result.files.hasPlayableURLs { resolved[id] = (result, Date()) }
    return result
  }
}
