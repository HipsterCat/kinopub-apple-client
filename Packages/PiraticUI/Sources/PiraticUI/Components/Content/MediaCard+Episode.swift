//
//  MediaCard+Episode.swift
//  PiraticUI
//
//  One mapping from an episode to the landscape card History and Continue Watching
//  already draw, so the detail rail and the season grid stop growing lookalikes.
//

import Foundation
import KinoPubBackend
import PiraticMedia

public extension MediaCard {

  /// An episode as a landscape `MediaCard`.
  ///
  /// The caller owns the strings the payload cannot compose on its own: `title`
  /// (kino.pub's name, or a schedule's when the episode has none) and
  /// `dateLabel` (already formatted — the UI package does not know this app's date rules).
  /// `stillURL` overrides the episode thumbnail when an external schedule carries a
  /// better one. The visible title is always `EpisodeText.listItem` («7. Name» /
  /// «7 серия») so tvOS, iPhone and macOS share one labeling ruleset with future
  /// episode tiles. `episodeLabel` is kept for call-site compatibility only.
  init(episode: Episode,
       in season: Season? = nil,
       title: String? = nil,
       episodeLabel: String? = nil,
       dateLabel: String? = nil,
       stillURL: String? = nil,
       primaryAction: MediaCardPrimaryAction = .play) {
    let still = stillURL ?? episode.thumbnail
    let isWatched = episode.isWatched
    // Resume bar only while unfinished — a watched episode says so with the time chip.
    // `resumeFraction` already applied the start floor and the watched threshold.
    let progress = isWatched ? nil : episode.watchProgress.resumeFraction
    let caption = Self.episodeCaption(name: title ?? episode.title,
                                      number: episode.number,
                                      episodeLabel: episodeLabel
                                        ?? EpisodeText(season: nil, number: episode.number)
                                          .listItem(),
                                      dateLabel: dateLabel,
                                      fallbackTitle: episode.fixedTitle)

    self.init(id: episode.id,
              posterURL: still,
              title: caption.title,
              progress: progress,
              landscapeImageURL: still,
              overlayLabel: caption.meta,
              itemID: season?.mediaId ?? episode.mediaId ?? episode.id,
              video: episode.number,
              season: season?.number ?? episode.seasonNumber,
              mediaID: episode.id,
              isWatched: isWatched,
              isSeries: true,
              durationSeconds: episode.duration >= 60 ? episode.duration : nil,
              primaryAction: primaryAction)
  }

  /// A landscape card for an episode that exists only on a schedule — announced or
  /// simply not uploaded yet. Inert: nothing to play, so Select opens nothing.
  ///
  /// `id` is the caller's synthetic (negative) rail id, kept outside kino.pub's ids.
  init(unavailableEpisodeID id: Int,
       number: Int,
       title: String?,
       episodeLabel: String?,
       dateLabel: String?,
       stillURL: String?,
       unavailableNotice: String? = nil) {
    let still = stillURL ?? ""
    let caption = Self.episodeCaption(name: title ?? "",
                                      number: number,
                                      episodeLabel: episodeLabel,
                                      dateLabel: dateLabel,
                                      fallbackTitle: episodeLabel ?? "")
    self.init(id: id,
              posterURL: still,
              title: caption.title,
              landscapeImageURL: still,
              overlayLabel: caption.meta,
              isSeries: true,
              primaryAction: .openDetail)
    self.unavailableNotice = unavailableNotice
  }

  /// Title line + meta line for an episode caption.
  ///
  /// One ruleset with the tvOS season rail and future/unavailable tiles:
  /// `EpisodeText.listItem` — «7. Name» / «7 серия» / «Ep 7». The date (when there
  /// is one) sits alone under it. `episodeLabel` is ignored when building the title
  /// so platforms cannot drift back to "name only, number on focus".
  private static func episodeCaption(name: String,
                                     number: Int,
                                     episodeLabel: String?,
                                     dateLabel: String?,
                                     fallbackTitle: String) -> (title: String, meta: String?) {
    let meaningful = EpisodeTitle.meaningful(name)
    let title = EpisodeText(season: nil, number: number, name: meaningful).listItem()
    let meta = dateLabel.flatMap { $0.isEmpty ? nil : $0 }
    // Keep a non-empty title even if listItem somehow cannot form one.
    return (title.isEmpty ? (episodeLabel ?? fallbackTitle) : title, meta)
  }
}
