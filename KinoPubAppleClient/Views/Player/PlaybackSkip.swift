//
//  PlaybackSkip.swift
//  KinoPubAppleClient
//
//  «Skip Intro», «Skip Recap», «Skip Credits» in the player, from SkipDB and TheIntroDB
//  (`MetadataService.skipSegments`, Sasha 2026-11-09).
//
//  tvOS draws the button itself: `AVPlayerViewController.contextualActions` is the system
//  button in the lower trailing corner that Apple's own apps use for Skip Intro. It is
//  set while a segment plays and emptied after. iOS and macOS have no such API yet.
//

import AVKit
import KinoPubBackend
import KinoPubLogging
import KinoPubMedia
import KinoPubMetadata
import OSLog

/// Which skip to offer at a moment of the stream. Pure, so the rule is tested apart.
enum PlaybackSkip {

  struct Offer: Equatable {
    let kind: SkipSegments.Kind
    /// Where the button jumps: the segment's end, or the end of the stream.
    let targetSeconds: Double
  }

  /// The button disappears this long before the segment ends: jumping a second ahead is
  /// no skip at all.
  static let tail: Double = 2

  /// The segment playing at `seconds`, while more than `tail` of it is left. A film is never
  /// offered its credits: there may be a scene after them, and the end is near anyway.
  static func offer(at seconds: Double, in segments: SkipSegments, durationSeconds: Double,
                    isEpisode: Bool) -> Offer? {
    let kinds: [SkipSegments.Kind] = isEpisode ? [.recap, .intro, .credits, .preview] : [.recap, .intro]
    for kind in kinds {
      guard let segment = segments[kind] else { continue }
      let start = Double(segment.startMs) / 1000
      var end = segment.endMs.map { Double($0) / 1000 } ?? durationSeconds
      if durationSeconds > 0 { end = min(end, durationSeconds) }
      guard end > start, seconds >= start, seconds < end - tail else { continue }
      return Offer(kind: kind, targetSeconds: end)
    }
    return nil
  }

  static func title(for kind: SkipSegments.Kind) -> String {
    switch kind {
    case .intro: "Player_SkipIntro".localized
    case .recap: "Player_SkipRecap".localized
    case .credits: "Player_SkipCredits".localized
    case .preview: "Player_SkipPreview".localized
    }
  }
}

extension PlaybackMediaContext {

  /// The skip times of what is playing. The season and episode are asked in the official
  /// numbering (TMDB's, which SkipDB and TheIntroDB share with IMDb), matched the same way
  /// `enrich` matches them; the calls behind the match are the cached ones `enrich` made.
  static func skipSegments(for enrichment: Enrichment, durationSeconds: Double,
                           service: MetadataService) async -> SkipSegments? {
    let identity = MediaIdentity(mediaItem: enrichment.title)
    let durationMs = durationSeconds > 0 ? Int(durationSeconds * 1000) : nil
    guard let episode = enrichment.episode else {
      // A film itself; a trailer never gets here (`PlayerManager.loadSkipSegments`).
      guard !enrichment.titleIsParent else { return nil }
      return await service.skipSegments(for: identity, season: nil, episode: nil, durationMs: durationMs)
    }
    let meta = await service.metadata(for: identity)
    let tmdbSeasons = Set(meta.seasonSummaries.map(\.seasonNumber))
    let tmdbSeason = TMDBSeasonMatch.tmdbSeason(kinoNumber: episode.kinoSeason,
                                                titleNumber: episode.titleSeason,
                                                tmdbSeasons: tmdbSeasons)
    var season = tmdbSeason ?? episode.titleSeason ?? episode.kinoSeason
    var number = episode.number
    if let tmdbSeason {
      let schedule = await service.episodeGrid(for: identity, seasons: [tmdbSeason])
      let kino = EpisodeGridMatch.KinoEpisode(blockID: episode.kinoSeason,
                                              blockNumber: episode.kinoSeason,
                                              titledNumber: episode.titleSeason,
                                              number: episode.number,
                                              title: episode.title,
                                              runtimeMinutes: episode.runtimeMinutes)
      let alignment = EpisodeGridMatch.align(kino: [kino], official: schedule.map(KinoEpisodeGrid.official))
      if let hit = alignment.hits.first {
        season = hit.official.season
        number = hit.official.number
      }
    }
    return await service.skipSegments(for: identity, season: season, episode: number, durationMs: durationMs)
  }
}

#if os(tvOS)

extension PlayerManager {

  /// Asks the skip-times sources about the item once its runtime is known, then watches
  /// the clock. Films and episodes only: a trailer or a channel has nothing to skip.
  func loadSkipSegments(enrichment: PlaybackMediaContext.Enrichment, on item: AVPlayerItem) {
    guard watchMode == .media else { return }
    clearSkipSegments()
    let fallbackSeconds = Double((playItem as? Episode)?.duration ?? 0)
    let service = AppContext.shared.metadataService
    skipSegmentsTask = Task { [weak self] in
      // The item's own runtime once it is ready (the enrichment answers after that as a
      // rule); kino.pub's figure before. Read here, not loaded from the asset: the asset is
      // not Sendable.
      let current = item.duration.seconds
      let duration = current.isFinite && current > 0 ? current : fallbackSeconds
      let segments = await PlaybackMediaContext.skipSegments(for: enrichment, durationSeconds: duration,
                                                             service: service)
      guard !Task.isCancelled, let segments else { return }
      await MainActor.run {
        guard let self, self.player.currentItem === item else { return }
        self.skipSegments = segments
        self.skipDurationSeconds = duration
        self.addSkipTimeObserver()
      }
    }
  }

  /// Everything about the previous stream's skips goes: an episode played in place must
  /// not keep the last one's button.
  func clearSkipSegments() {
    skipSegmentsTask?.cancel()
    skipSegmentsTask = nil
    skipSegments = nil
    if let skipObserverToken {
      player.removeTimeObserver(skipObserverToken)
      self.skipObserverToken = nil
    }
    if skipOffer != nil {
      skipOffer = nil
      setSkipActions([])
    }
  }

  private func addSkipTimeObserver() {
    guard skipObserverToken == nil else { return }
    let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
    skipObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
      self?.updateSkipAction(at: time.seconds.isFinite ? time.seconds : 0)
    }
  }

  /// Hands AVKit a fresh action only when the offer changes; AVKit animates the button in
  /// and out by itself.
  private func updateSkipAction(at seconds: Double) {
    guard let segments = skipSegments else { return }
    let offer = PlaybackSkip.offer(at: seconds, in: segments, durationSeconds: skipDurationSeconds,
                                   isEpisode: playItem is Episode)
    guard offer != skipOffer else { return }
    skipOffer = offer
    guard let offer else {
      setSkipActions([])
      return
    }
    let action = UIAction(title: PlaybackSkip.title(for: offer.kind)) { [weak self] _ in
      guard let self else { return }
      Logger.app.info("Skip \(offer.kind.rawValue, privacy: .public) to \(offer.targetSeconds)s")
      self.player.seek(to: CMTime(seconds: offer.targetSeconds, preferredTimescale: 600),
                       toleranceBefore: .zero, toleranceAfter: .positiveInfinity)
      self.skipOffer = nil
      self.setSkipActions([])
    }
    setSkipActions([action])
  }

  /// The time observer and the teardown both run on the main queue.
  private func setSkipActions(_ actions: [UIAction]) {
    MainActor.assumeIsolated {
      playerViewController?.contextualActions = actions
    }
  }
}

#endif
