//
//  SeasonDownloadManager.swift
//  KinoPubAppleClient
//
//  Downloads an entire season in one action, each episode through `DownloadsCenter`
//  (HLS on iPhone and iPad, mp4 on the Mac). Tracks per-season group progress and posts a single "season downloaded"
//  notification when the last episode of a group finishes.
//

import Foundation
import KinoPubBackend
import KinoPubMedia
import KinoPubKit
import OSLog
import KinoPubLogging

@MainActor
final class SeasonDownloadManager: ObservableObject {

  /// In-progress (or just-finished) bulk season download.
  struct Group: Identifiable {
    let id: String
    let seriesTitle: String
    let seasonNumber: Int
    let total: Int
    var completed: Int
    /// `HLSDownloadKey`s of the episodes still downloading — the same key for either
    /// engine, so a season finishes whichever one fetched its episodes.
    var pendingKeys: Set<String>

    var progress: Double { total > 0 ? Double(completed) / Double(total) : 0 }
    var isComplete: Bool { completed >= total }
  }

  @Published private(set) var groups: [String: Group] = [:]

  private let notifications: DownloadNotificationManager
  /// Set once `AppContext` has built the center (it needs the library store, built later).
  var center: DownloadsCenter?

  init(notifications: DownloadNotificationManager) {
    self.notifications = notifications
  }

  /// Distinct quality labels available across a season's episodes, best (highest resolution) first.
  /// A `nolinks=1` payload still lists the ladder, so this reads without resolving links.
  static func availableQualities(in season: Season) -> [String] {
    var seen = Set<String>()
    var result: [(label: String, resolution: Int)] = []
    for episode in season.episodes {
      for file in episode.files where !seen.contains(file.quality) {
        seen.insert(file.quality)
        result.append((file.quality, file.resolution))
      }
    }
    return result.sorted { $0.resolution > $1.resolution }.map { $0.label }
  }

  /// Downloads every episode of `season` at `quality` (or each episode's best file).
  /// A series page is fetched with `nolinks=1`, so an episode has no links until
  /// `MediaLinksResolver` fills it — without that this quietly did nothing. Episodes
  /// already downloaded or downloading are skipped by the engines. Returns how many
  /// episodes were handed over.
  @discardableResult
  func downloadSeason(mediaId: Int,
                      seriesTitle: String,
                      season: Season,
                      quality: String?,
                      using service: VideoContentService) async -> Int {
    guard let center else { return 0 }
    var keys = Set<String>()
    for episode in season.episodes {
      await MediaLinksResolver.shared.fill(episode, using: service)
      guard let file = pickFile(from: episode.files, quality: quality), file.hasPlayableURL else {
        Logger.app.error("[SEASON DL] no links for S\(season.number)E\(episode.number) of \(mediaId)")
        continue
      }
      let meta = downloadMeta(mediaId: mediaId, seriesTitle: seriesTitle, season: season,
                              episode: episode, quality: file.quality)
      center.start(meta: meta, file: file)
      keys.insert(HLSDownloadKey.make(for: meta))
    }
    guard !keys.isEmpty else { return 0 }
    let id = groupID(mediaId: mediaId, seasonNumber: season.number)
    groups[id] = Group(id: id,
                       seriesTitle: seriesTitle,
                       seasonNumber: season.number,
                       total: keys.count,
                       completed: 0,
                       pendingKeys: keys)
    Logger.app.info("[SEASON DL] Queued \(keys.count) episodes for \(id)")
    return keys.count
  }

  /// Advances the season group a finished download belongs to. Returns `true` when it was
  /// part of a group, so the caller can suppress the per-episode "download complete" notification.
  @discardableResult
  func handleFinished(meta: DownloadMeta) -> Bool {
    let key = HLSDownloadKey.make(for: meta)
    guard let id = groups.first(where: { $0.value.pendingKeys.contains(key) })?.key else { return false }
    groups[id]?.pendingKeys.remove(key)
    groups[id]?.completed += 1
    if let group = groups[id], group.isComplete {
      notifications.notifySeasonFinished(
        title: "\(group.seriesTitle) — \(seasonLabel(group.seasonNumber))",
        identifier: group.id)
      Logger.app.info("[SEASON DL] Completed group \(group.id)")
      groups[id] = nil
    }
    return true
  }

  // MARK: - Helpers

  private func groupID(mediaId: Int, seasonNumber: Int) -> String {
    "season_\(mediaId)_\(seasonNumber)"
  }

  private func seasonLabel(_ number: Int) -> String {
    SeasonText(number).formatted(.long)
  }

  /// Picks the file matching `quality`; otherwise the highest-resolution file available.
  private func pickFile(from files: [FileInfo], quality: String?) -> FileInfo? {
    if let quality, let exact = files.first(where: { $0.quality == quality }) { return exact }
    return files.max(by: { $0.resolution < $1.resolution })
  }

  /// The same shape the title page's own Download gives an episode (`DownloadMeta.make`):
  /// the series' id and title, the episode in `metadata` and the marker — so the hero's
  /// circle, the player's offline lookup and the Downloads list all find it.
  private func downloadMeta(mediaId: Int, seriesTitle: String, season: Season, episode: Episode,
                            quality: String) -> DownloadMeta {
    let name = "S\(season.number)E\(episode.number)"
    return DownloadMeta(id: mediaId,
                        files: episode.files,
                        originalTitle: episode.fixedTitle,
                        localizedTitle: seriesTitle,
                        imageUrl: episode.thumbnail,
                        metadata: WatchingMetadata(id: mediaId, video: episode.number, season: season.number),
                        quality: quality,
                        episode: name)
  }
}
