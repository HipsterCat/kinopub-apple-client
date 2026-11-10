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
//  One label, «Пропустить», whatever is skipped: per-kind titles were long and the button
//  changed width (Sasha, 2026-11-10). Left alone, the skip takes itself after
//  `countdown` seconds of playback, the time left drawn on the button.
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
  ///
  /// `nextEpisodeAtCredits`: the next episode is proposed when credits that close the
  /// episode begin (tvOS's Up Next panel), so they get no skip of their own.
  static func offer(at seconds: Double, in segments: SkipSegments, durationSeconds: Double,
                    isEpisode: Bool, nextEpisodeAtCredits: Bool = false) -> Offer? {
    let kinds: [SkipSegments.Kind] = isEpisode ? [.recap, .intro, .credits, .preview] : [.recap, .intro]
    for kind in kinds {
      guard let segment = segments[kind] else { continue }
      if kind == .credits, nextEpisodeAtCredits,
         closingCreditsStart(in: segments, durationSeconds: durationSeconds) != nil { continue }
      let start = Double(segment.startMs) / 1000
      var end = segment.endMs.map { Double($0) / 1000 } ?? durationSeconds
      if durationSeconds > 0 { end = min(end, durationSeconds) }
      guard end > start, seconds >= start, seconds < end - tail else { continue }
      return Offer(kind: kind, targetSeconds: end)
    }
    return nil
  }

  /// Seconds of playback the button waits before it skips by itself.
  static let countdown: Double = 5

  /// The button's label, the same for every kind.
  static var title: String { "Player_Skip".localized }

  /// What VoiceOver says: which part goes.
  static func accessibilityTitle(for kind: SkipSegments.Kind) -> String {
    switch kind {
    case .intro: "Player_SkipIntro".localized
    case .recap: "Player_SkipRecap".localized
    case .credits: "Player_SkipCredits".localized
    case .preview: "Player_SkipPreview".localized
    }
  }

  /// Where an episode's closing credits start when nothing follows them: they run to the
  /// stream's end, give or take a few seconds. There the next episode is offered at their
  /// start instead of a skip into the end.
  static func closingCreditsStart(in segments: SkipSegments, durationSeconds: Double) -> Double? {
    guard let credits = segments[.credits], durationSeconds > 0 else { return nil }
    let end = credits.endMs.map { Double($0) / 1000 } ?? durationSeconds
    guard end >= durationSeconds - 5 else { return nil }
    let start = Double(credits.startMs) / 1000
    return start > 0 && start < durationSeconds ? start : nil
  }

  /// Share of the countdown left at `seconds` for an offer shown at `shownAt`, 1 → 0.
  static func countdownLeft(at seconds: Double, shownAt: Double) -> Double {
    min(max(1 - (seconds - shownAt) / countdown, 0), 1)
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
    return order.compactMap { kind -> Row? in
      guard let segment = segments[kind] else { return nil }
      let end = segment.endMs.map { Double($0) / 1000 } ?? durationSeconds
      let seconds = Int((end - Double(segment.startMs) / 1000).rounded())
      guard seconds > 0 else { return nil }
      return Row(kind: kind, length: Swift.Duration.seconds(seconds).formatted(.time(pattern: .minuteSecond)))
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
#if os(tvOS)
        // Up Next moves to where the closing credits start, now that they are known.
        if self.pendingNextEpisode != nil,
           PlaybackSkip.closingCreditsStart(in: segments, durationSeconds: duration) != nil {
          self.installNextEpisodeProposal(on: item)
        }
#endif
      }
    }
  }

  /// Everything about the previous stream's skips goes: an episode played in place must
  /// not keep the last one's button.
  func clearSkipSegments() {
    skipSegmentsTask?.cancel()
    skipSegmentsTask = nil
    skipSegments = nil
    skippedKinds = []
    skipOfferShownAt = nil
    if let skipObserverToken {
      player.removeTimeObserver(skipObserverToken)
      self.skipObserverToken = nil
    }
    if skipOffer != nil {
      skipOffer = nil
      showSkip(nil)
    }
  }

  /// The viewer pressed the button, or its countdown ran out: to the segment's end, and
  /// the button goes at once.
  func performSkip(automatically: Bool = false) {
    guard let offer = skipOffer else { return }
    Logger.app.info("Skip \(offer.kind.rawValue, privacy: .public) to \(offer.targetSeconds)s\(automatically ? " (countdown)" : "", privacy: .public)")
    skippedKinds.insert(offer.kind)
    skipOfferShownAt = nil
    player.seek(to: CMTime(seconds: offer.targetSeconds, preferredTimescale: 600),
                toleranceBefore: .zero, toleranceAfter: .positiveInfinity)
    skippedOffer = offer
    skipOffer = nil
    showSkip(nil)
  }

  private func addSkipTimeObserver() {
    guard skipObserverToken == nil else { return }
    // Four ticks a second: the countdown on the button moves smoothly between them.
    let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
    skipObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
      self?.updateSkipOffer(at: time.seconds.isFinite ? time.seconds : 0)
    }
  }

  private func updateSkipOffer(at seconds: Double) {
    guard let segments = skipSegments else { return }
#if os(tvOS)
    let nextAtCredits = pendingNextEpisode != nil
#else
    let nextAtCredits = false
#endif
    var offer = PlaybackSkip.offer(at: seconds, in: segments, durationSeconds: skipDurationSeconds,
                                   isEpisode: playItem is Episode, nextEpisodeAtCredits: nextAtCredits)
    // The seek just asked for may not have landed yet: no flash of the same button.
    if let skipped = skippedOffer {
      if offer == skipped { offer = nil } else { skippedOffer = nil }
    }
    if offer != skipOffer {
      skipOffer = offer
      // A kind skipped once in this stream is offered again, but waits for a press.
      skipOfferShownAt = offer.flatMap { skippedKinds.contains($0.kind) ? nil : seconds }
      skipCountdownLeft = 1
      showSkip(offer)
    }
    guard offer != nil, let shownAt = skipOfferShownAt else { return }
    // Scrubbed back before the button appeared: the countdown starts over from here.
    if seconds < shownAt { skipOfferShownAt = seconds }
    let left = PlaybackSkip.countdownLeft(at: seconds, shownAt: skipOfferShownAt ?? seconds)
    skipCountdownLeft = left
    if left <= 0 {
      performSkip(automatically: true)
    } else {
      updateSkipRing(left)
    }
  }

  /// tvOS: AVKit's own button (`contextualActions`), which it animates in and out. iOS and
  /// the Mac draw theirs from `skipOffer` (`SkipButtonOverlay`).
  private func showSkip(_ offer: PlaybackSkip.Offer?) {
#if os(tvOS)
    MainActor.assumeIsolated {
      guard let offer else {
        skipAction = nil
        playerViewController?.contextualActions = []
        return
      }
      let action = UIAction(title: PlaybackSkip.title,
                            image: skipOfferShownAt == nil ? nil : SkipCountdownGlyph.image(left: 1)) { [weak self] _ in
        self?.performSkip()
      }
      action.accessibilityLabel = PlaybackSkip.accessibilityTitle(for: offer.kind)
      skipAction = action
      playerViewController?.contextualActions = [action]
    }
#endif
  }

  /// tvOS: the ring beside the label drains as Apple's Next Episode button does; the
  /// action is redrawn in place, not replaced, so AVKit does not animate it in again.
  private func updateSkipRing(_ left: Double) {
#if os(tvOS)
    MainActor.assumeIsolated {
      skipAction?.image = SkipCountdownGlyph.image(left: left)
    }
#endif
  }
}

#if os(tvOS)
/// The glyph of tvOS's skip button: a play arrow inside a ring that drains with the
/// countdown, the shape of the TV app's «Next Episode» (Sasha's photo, 2026-11-10).
@MainActor
enum SkipCountdownGlyph {
  static let side: CGFloat = 38

  static func image(left: Double) -> UIImage {
    // Twenty steps are enough for the eye and keep the images few.
    let step = (left * 20).rounded() / 20
    if let cached = cache[step] { return cached }
    let size = CGSize(width: side, height: side)
    let image = UIGraphicsImageRenderer(size: size).image { context in
      let cg = context.cgContext
      let lineWidth: CGFloat = 3
      let rect = CGRect(origin: .zero, size: size).insetBy(dx: lineWidth / 2 + 1, dy: lineWidth / 2 + 1)
      let center = CGPoint(x: rect.midX, y: rect.midY)
      let radius = rect.width / 2
      cg.setStrokeColor(UIColor.black.cgColor)
      cg.setLineWidth(lineWidth)
      cg.setLineCap(.round)
      if step > 0 {
        let startAngle = -CGFloat.pi / 2
        cg.addArc(center: center, radius: radius, startAngle: startAngle,
                  endAngle: startAngle + 2 * .pi * CGFloat(step), clockwise: false)
        cg.strokePath()
      }
      // The arrow, a third of the ring.
      let arrow = radius * 0.62
      cg.setFillColor(UIColor.black.cgColor)
      cg.move(to: CGPoint(x: center.x - arrow * 0.45, y: center.y - arrow * 0.6))
      cg.addLine(to: CGPoint(x: center.x + arrow * 0.65, y: center.y))
      cg.addLine(to: CGPoint(x: center.x - arrow * 0.45, y: center.y + arrow * 0.6))
      cg.closePath()
      cg.fillPath()
    }.withRenderingMode(.alwaysTemplate)
    cache[step] = image
    return image
  }

  private static var cache: [Double: UIImage] = [:]
}
#endif

#if !os(tvOS)

/// The skip button on iOS and the Mac, where AVKit has no place for one: a capsule in the
/// lower trailing corner, the size and material of the system's own (Sasha, 2026-11-09:
/// one feature on every platform).
struct SkipButtonOverlay: View {
  let offer: PlaybackSkip.Offer?
  /// Share of the countdown left, 1 → 0; 1 when the button waits for a press.
  var countdownLeft: Double = 1
  let action: () -> Void

  var body: some View {
    ZStack(alignment: .bottomTrailing) {
      Color.clear
      if let offer {
        Button(action: action) {
          Label(PlaybackSkip.title, systemImage: "forward.end.fill")
            .font(.headline)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .background {
          // The time spent as a darker band that grows across the capsule from the
          // leading edge, under the label; the light part is the time left (Sasha,
          // 2026-11-10).
          GeometryReader { proxy in
            Rectangle()
              .fill(.black.opacity(0.35))
              .frame(width: proxy.size.width * (1 - countdownLeft))
              .animation(.linear(duration: 0.25), value: countdownLeft)
          }
        }
        .background(.regularMaterial)
        .clipShape(Capsule())
        .environment(\.colorScheme, .dark)
        .padding(.trailing, 24)
        .padding(.bottom, 96)
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
        .accessibilityLabel(PlaybackSkip.accessibilityTitle(for: offer.kind))
        .accessibilityIdentifier("player.skip")
      }
    }
    .animation(.easeOut(duration: 0.2), value: offer)
    .allowsHitTesting(offer != nil)
  }
}
#endif
