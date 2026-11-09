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
import SwiftUI

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

/// **What the player will offer to skip on a title page**: the film, or the episode Play
/// starts, and how long each part lasts. Shown while skip times are being tried out, so it
/// is plain where there is markup and where there is none (Sasha, 2026-11-09). One value
/// for the iOS / macOS card and the tvOS spec card.
struct SkipSegmentsPreview: Equatable {
  struct Row: Equatable {
    let kind: SkipSegments.Kind
    let length: String
  }

  /// «С1 Э3» for a series, nil for a film.
  var episodeLabel: String?
  var rows: [Row]
  /// Who marked it up, «SkipDB & TheIntroDB»; both names before anything answered.
  var sources: String

  /// Which episode, then who marked it up.
  var subtitle: String { [episodeLabel, sources].compactMap { $0 }.joined(separator: " · ") }

  static func isAvailable(for item: MediaItem) -> Bool {
    (item.imdb ?? 0) > 0
      && (SkipTimesMetadataAccess.isEnabled(SkipTimesMetadataAccess.skipDBDefaultsKey)
          || SkipTimesMetadataAccess.isEnabled(SkipTimesMetadataAccess.theIntroDBDefaultsKey))
  }

  static func load(for item: MediaItem, service: MetadataService) async -> SkipSegmentsPreview? {
    guard isAvailable(for: item) else { return nil }
    var playing: any PlayableItem = item
    var label: String?
    var duration = item.mediaEntity.runtime ?? 0
    if let (season, episode) = item.primaryEpisode {
      // The episode Play starts, with its season set the way the hero sets it.
      episode.seasonNumber = season.number
      episode.mediaId = season.mediaId
      playing = episode
      label = EpisodeText(season: season.number, number: episode.number).text(for: .continueWatchingCard)
      duration = Double(episode.duration)
    }
    var segments: SkipSegments?
    if let enrichment = PlaybackMediaContext.enrichment(playing: playing, title: item, isTrailer: false) {
      segments = await PlaybackMediaContext.skipSegments(for: enrichment, durationSeconds: duration,
                                                         service: service)
    }
    return SkipSegmentsPreview(episodeLabel: label,
                               rows: rows(segments, durationSeconds: duration),
                               sources: sources(segments))
  }

  /// Each part in the order it plays, with how long it lasts. A segment that runs to the
  /// end is measured to the runtime. A film's credits are listed too, though the player
  /// never offers them (a scene may follow).
  static func rows(_ segments: SkipSegments?, durationSeconds: Double) -> [Row] {
    guard let segments else { return [] }
    let order: [SkipSegments.Kind] = [.recap, .intro, .credits, .preview]
    return order.compactMap { kind in
      guard let segment = segments[kind] else { return nil }
      let end = segment.endMs.map { Double($0) / 1000 } ?? durationSeconds
      let seconds = Int((end - Double(segment.startMs) / 1000).rounded())
      guard seconds > 0 else { return nil }
      return Row(kind: kind, length: Duration.seconds(seconds).formatted(.time(pattern: .minuteSecond)))
    }
  }

  static func sources(_ segments: SkipSegments?) -> String {
    let all = [(MetadataSourceID.skipDB, "SkipDB"), (.introdb, "TheIntroDB")]
    guard let segments else { return all.map(\.1).joined(separator: " & ") }
    let used = Set(SkipSegments.Kind.allCases.compactMap { segments[$0]?.source })
    return all.filter { used.contains($0.0) }.map(\.1).joined(separator: " & ")
  }

  static func title(for kind: SkipSegments.Kind) -> String {
    switch kind {
    case .intro: "MediaItem_SkipIntro".localized
    case .recap: "MediaItem_SkipRecap".localized
    case .credits: "MediaItem_SkipCredits".localized
    case .preview: "MediaItem_SkipPreview".localized
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

extension PlayerManager {

  /// Asks the skip-times sources about the item once it is ready (its runtime known), then
  /// watches the clock. Films and episodes only: a trailer or a channel has nothing to skip.
  ///
  /// The title comes from the item itself, or the series the page cached; a thin one (no
  /// IMDb id: Continue Watching, search) is filled from one light details call, the same
  /// one the info panel makes and the cache answers.
  func loadSkipSegments(on item: AVPlayerItem) {
    guard watchMode == .media else { return }
    clearSkipSegments()
    let fallbackSeconds = Double((playItem as? Episode)?.duration ?? 0)
    let current = item.duration.seconds
    let duration = current.isFinite && current > 0 ? current : fallbackSeconds
    let service = AppContext.shared.metadataService
    let contentService = self.contentService
    skipSegmentsTask = Task { [weak self] in
      // Read inside the task: the playable is not Sendable.
      guard let playing = self?.playItem else { return }
      let id = playing.metadata.id
      var title = (playing as? MediaItem)
        ?? AppContext.shared.localProgressStore.snapshot(for: id)
      if (title?.imdb ?? 0) <= 0 {
        title = try? await contentService.fetchDetails(for: String(id), excludeLinks: true).item
      }
      guard !Task.isCancelled,
            let enrichment = PlaybackMediaContext.enrichment(playing: playing, title: title, isTrailer: false)
      else { return }
      let segments = await PlaybackMediaContext.skipSegments(for: enrichment, durationSeconds: duration,
                                                             service: service)
      guard !Task.isCancelled, let segments else { return }
      await MainActor.run {
        guard let self, self.player.currentItem === item else { return }
        let kinds = SkipSegments.Kind.allCases.filter { segments[$0] != nil }.map(\.rawValue).joined(separator: ",")
        Logger.app.info("Skip times: \(kinds, privacy: .public)")
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
      showSkip(nil)
    }
  }

  /// The viewer pressed the button: to the segment's end, and the button goes at once.
  func performSkip() {
    guard let offer = skipOffer else { return }
    Logger.app.info("Skip \(offer.kind.rawValue, privacy: .public) to \(offer.targetSeconds)s")
    player.seek(to: CMTime(seconds: offer.targetSeconds, preferredTimescale: 600),
                toleranceBefore: .zero, toleranceAfter: .positiveInfinity)
    skippedOffer = offer
    skipOffer = nil
    showSkip(nil)
  }

  private func addSkipTimeObserver() {
    guard skipObserverToken == nil else { return }
    let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
    skipObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
      self?.updateSkipOffer(at: time.seconds.isFinite ? time.seconds : 0)
    }
  }

  private func updateSkipOffer(at seconds: Double) {
    guard let segments = skipSegments else { return }
    var offer = PlaybackSkip.offer(at: seconds, in: segments, durationSeconds: skipDurationSeconds,
                                   isEpisode: playItem is Episode)
    // The seek just asked for may not have landed yet: no flash of the same button.
    if let skipped = skippedOffer {
      if offer == skipped { offer = nil } else { skippedOffer = nil }
    }
    guard offer != skipOffer else { return }
    skipOffer = offer
    showSkip(offer)
  }

  /// tvOS: AVKit's own button (`contextualActions`), which it animates in and out. iOS and
  /// the Mac draw theirs from `skipOffer` (`SkipButtonOverlay`).
  private func showSkip(_ offer: PlaybackSkip.Offer?) {
#if os(tvOS)
    MainActor.assumeIsolated {
      guard let offer else {
        playerViewController?.contextualActions = []
        return
      }
      let action = UIAction(title: PlaybackSkip.title(for: offer.kind)) { [weak self] _ in
        self?.performSkip()
      }
      playerViewController?.contextualActions = [action]
    }
#endif
  }
}

#if !os(tvOS)

/// The skip button on iOS and the Mac, where AVKit has no place for one: a capsule in the
/// lower trailing corner, the size and material of the system's own (Sasha, 2026-11-09:
/// one feature on every platform).
struct SkipButtonOverlay: View {
  let offer: PlaybackSkip.Offer?
  let action: () -> Void

  var body: some View {
    ZStack(alignment: .bottomTrailing) {
      Color.clear
      if let offer {
        Button(action: action) {
          Label(PlaybackSkip.title(for: offer.kind), systemImage: "forward.end.fill")
            .font(.headline)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .background(.regularMaterial, in: Capsule())
        .environment(\.colorScheme, .dark)
        .padding(.trailing, 24)
        .padding(.bottom, 96)
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
        .accessibilityIdentifier("player.skip")
      }
    }
    .animation(.easeOut(duration: 0.2), value: offer)
    .allowsHitTesting(offer != nil)
  }
}
#endif
