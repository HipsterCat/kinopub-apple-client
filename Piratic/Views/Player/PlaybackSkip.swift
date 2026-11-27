//
//  PlaybackSkip.swift
//  Piratic
//
//  «Skip Intro», «Skip Recap», «Skip Credits» in the player, from SkipDB and TheIntroDB
//  (`MetadataService.skipSegments`, Sasha 2026-11-09).
//
//  tvOS draws the button itself: `AVPlayerViewController.contextualActions` is the system
//  button in the lower trailing corner that Apple's own apps use for Skip Intro. It is
//  set while a segment plays and emptied after. iOS and macOS have no such API yet.
//
//  One label, «Пропустить», whatever is skipped: per-kind titles were long and the button
//  changed width (Sasha, 2026-11-10). On iOS and the Mac the button waits for a press
//  unless Settings asks it to take itself (`SkipAutoStyle`, default `.apple`). tvOS
//  still draws AVKit's own button and lets that countdown run.
//

import AVKit
import KinoPubBackend
import PiraticLogging
import PiraticMedia
import PiraticMetadata
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

  /// How close to the stream's end a jump still counts as finishing the title.
  /// Matches `closingCreditsStart`'s end-of-stream tolerance.
  static let endTolerance: Double = 5

  /// The segment playing at `seconds`, while more than `tail` of it is left.
  ///
  /// A film is offered its credits only when they close the title (they run to the end).
  /// Mid-film credits with a scene after them stay off — the end is near and a skip
  /// into the middle of a scene is not useful.
  ///
  /// `nextEpisodeAtCredits`: the next episode is proposed when credits that close the
  /// episode begin (tvOS's Up Next panel), so they get no skip of their own.
  static func offer(at seconds: Double, in segments: SkipSegments, durationSeconds: Double,
                    isEpisode: Bool, nextEpisodeAtCredits: Bool = false) -> Offer? {
    var kinds: [SkipSegments.Kind] = isEpisode
      ? [.recap, .intro, .credits, .preview]
      : [.recap, .intro]
    // Closing credits on a film: Skip finishes the title instead of seeking into the end.
    if !isEpisode, closingCreditsStart(in: segments, durationSeconds: durationSeconds) != nil {
      kinds.append(.credits)
    }
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

  /// Skip lands at (or within `endTolerance` of) the stream's end — last episode credits,
  /// a film's closing credits, or a preview that runs out the item.
  static func finishesTitle(_ offer: Offer, durationSeconds: Double) -> Bool {
    guard durationSeconds > 0 else { return false }
    return offer.targetSeconds >= durationSeconds - endTolerance
  }

  /// SF Symbol for the Skip control: `forward.end.fill` when Skip closes the player,
  /// otherwise `forward.fill`.
  static func symbolName(for offer: Offer, durationSeconds: Double) -> String {
    finishesTitle(offer, durationSeconds: durationSeconds) ? "forward.end.fill" : "forward.fill"
  }

  /// Seconds of playback tvOS waits before its own button skips. iOS and the Mac
  /// read `SkipChipPreferences.delaySeconds` instead, and only when a style auto-skips.
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
    guard end >= durationSeconds - endTolerance else { return nil }
    let start = Double(credits.startMs) / 1000
    return start > 0 && start < durationSeconds ? start : nil
  }

  /// Share of the countdown left at `seconds` for an offer shown at `shownAt`, 1 → 0.
  static func countdownLeft(at seconds: Double, shownAt: Double) -> Double {
    countdownLeft(elapsed: seconds - shownAt, delay: countdown)
  }

  /// 1 is a full delay still to run, 0 is the moment an automatic skip fires.
  /// A delay of 0 does not mean "skip now" — that was the button pressing itself
  /// before anyone could see it.
  static func countdownLeft(elapsed: Double, delay: Double) -> Double {
    guard delay > 0 else { return 1 }
    return min(max(1 - elapsed / delay, 0), 1)
  }

  static func countdownSecondsLeft(countdownLeft: Double, delay: Double) -> Int {
    guard delay > 0 else { return 0 }
    return max(0, Int((countdownLeft * delay).rounded(.up)))
  }

  /// «Пропустить 0:04», counting the delay still left.
  static func countdownLabel(countdownLeft: Double, delay: Double) -> String {
    let seconds = countdownSecondsLeft(countdownLeft: countdownLeft, delay: delay)
    let clock = Swift.Duration.seconds(seconds).formatted(.time(pattern: .minuteSecond))
    return String(format: "Player_SkipCountdown".localized, locale: .current, clock)
  }

  static func shouldAutoSkip(style: SkipAutoStyle, countdownLeft: Double) -> Bool {
    style.autoSkips && countdownLeft <= 0
  }
}

/// How an automatic skip is shown on iOS and the Mac. `.apple` does not press the
/// button; the rest do, after `SkipChipPreferences.delaySeconds`.
enum SkipAutoStyle: String, CaseIterable, Identifiable {
  case apple
  case countdown
  case fill
  case stroke
  case ring
  case pictureInPicture
  case banner

  var id: String { rawValue }
  var autoSkips: Bool { self != .apple }

  var title: String {
    switch self {
    case .apple: "Settings_SkipStyle_Apple".localized
    case .countdown: "Settings_SkipStyle_Countdown".localized
    case .fill: "Settings_SkipStyle_Fill".localized
    case .stroke: "Settings_SkipStyle_Stroke".localized
    case .ring: "Settings_SkipStyle_Ring".localized
    case .pictureInPicture: "Settings_SkipStyle_PiP".localized
    case .banner: "Settings_SkipStyle_Banner".localized
    }
  }
}

/// Always on the chip: a plain X, or the text button «Смотреть титры». The text
/// button is the one that makes Skip the prominent glass button.
enum SkipCancelStyle: String, CaseIterable, Identifiable {
  case dismiss
  case watchCredits

  var id: String { rawValue }
  var skipIsProminent: Bool { self == .watchCredits }

  var title: String {
    switch self {
    case .dismiss: "Settings_SkipCancel_Dismiss".localized
    case .watchCredits: "Settings_SkipCancel_Watch".localized
    }
  }
}

enum SkipChipPreferences {
  static let styleKey = "skipAutoStyle"
  static let delayKey = "skipAutoDelaySeconds"
  static let cancelKey = "skipCancelStyle"
  static let delays = [3, 4, 5, 8, 10, 15]
  static let defaultDelay = 5

  static var style: SkipAutoStyle {
    let raw = UserDefaults.standard.string(forKey: styleKey) ?? ""
    return SkipAutoStyle(rawValue: raw) ?? .apple
  }

  static var delaySeconds: Double {
    let stored = UserDefaults.standard.object(forKey: delayKey) as? Int ?? defaultDelay
    return Double(delays.contains(stored) ? stored : defaultDelay)
  }

  static var cancel: SkipCancelStyle {
    let raw = UserDefaults.standard.string(forKey: cancelKey) ?? ""
    return SkipCancelStyle(rawValue: raw) ?? .dismiss
  }
}

enum SkipChipVisibility {
  /// iPhone / iPad: Skip takes the place of the chrome, as on tvOS. It shows while the
  /// controls are hidden, so it never lands on the subtitles / audio buttons, and a tap
  /// on it reaches it instead of first waking the chrome (Sasha, 2026-11-22).
  /// Mac: the pointer wakes the chrome on its way to the chip, so there Skip stays
  /// with the chrome; an inverse chip would vanish under the cursor.
#if os(macOS)
  static let followsChrome = true
#else
  static let followsChrome = false
#endif

  /// Never over a menu the chrome owns.
  static func shown(hasOffer: Bool, controlsVisible: Bool, menuActive: Bool,
                    followsChrome: Bool = SkipChipVisibility.followsChrome) -> Bool {
    hasOffer && !menuActive && (followsChrome ? controlsVisible : !controlsVisible)
  }

  /// tvOS: AVKit presents `contextualActions` only when the transport bar is
  /// not visible (Apple docs). A transport menu (Speed, Subtitles, Audio, …)
  /// also hides Skip.
  static func actionable(hasOffer: Bool, transportBarVisible: Bool, menuActive: Bool) -> Bool {
    hasOffer && !transportBarVisible && !menuActive
  }

  /// Whether the auto-skip countdown must pause.
  /// - Mac (`chipFollowsChrome`): suspend when chrome is down or a menu is up.
  /// - tvOS, iPhone, iPad: Skip is the inverse of the transport bar — suspend when
  ///   the bar is up or a menu is up.
  static func countdownSuspended(chromeVisible: Bool, menuActive: Bool,
                                 chipFollowsChrome: Bool) -> Bool {
    chipFollowsChrome ? (!chromeVisible || menuActive) : (chromeVisible || menuActive)
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
      playing = episode.stamped(season: season.number, mediaId: season.mediaId,
                                seriesTitle: episode.seriesTitle)
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
  /// end is measured to the runtime. A film's credits are listed too — the player only
  /// offers them when they close the title.
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
    // Prefer skip timings stored with the download (fetched while online). Offline play
    // must not depend on SkipDB / TheIntroDB answering again (KP-91).
    if let stored = offlineStoredSkipSegments(), !stored.isEmpty {
      skipSegments = stored
      skipDurationSeconds = duration
      addSkipTimeObserver()
#if os(tvOS)
      if pendingNextEpisode != nil,
         PlaybackSkip.closingCreditsStart(in: stored, durationSeconds: duration) != nil {
        installNextEpisodeProposal(on: item)
      }
#endif
      Logger.app.info("Skip times: offline store")
      return
    }
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

  /// Skip timings saved on a downloaded `DownloadMeta` (HLS or mp4).
  private func offlineStoredSkipSegments() -> SkipSegments? {
    if let meta = playItem as? DownloadMeta {
      return meta.skipSegments
    }
    let contentIds: Set<Int> = [playItem.id, playItem.metadata.id]
    let video = playItem.metadata.video
    let season = playItem.metadata.season
    for contentId in contentIds {
      if let hls = AppContext.shared.hlsDownloadsStore.asset(
        forId: contentId, video: video, season: season
      )?.meta.skipSegments {
        return hls
      }
    }
    let files = downloadedFilesDatabase.readData() ?? []
    return files.first(where: {
      contentIds.contains($0.metadata.id)
        && $0.metadata.metadata.video == video
        && $0.metadata.metadata.season == season
    })?.metadata.skipSegments
  }

  /// Everything about the previous stream's skips goes: an episode played in place must
  /// not keep the last one's button.
  func clearSkipSegments() {
    skipSegmentsTask?.cancel()
    skipSegmentsTask = nil
    skipSegments = nil
    skippedKinds = []
    skipOfferShownAt = nil
    skipCountdownElapsed = 0
    skipCountdownAnchor = nil
    dismissedOffer = nil
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
  ///
  /// When Skip would finish the title (closing credits on a film, last-episode end,
  /// preview that runs out the stream), do **not** seek to the end — mark watched and
  /// close (or hand off via `onPlaybackEnded`) immediately. Seeking first left the
  /// playhead on the last frame before the end handler ran.
  func performSkip(automatically: Bool = false) {
    guard let offer = skipOffer else { return }
    let finishes = PlaybackSkip.finishesTitle(offer, durationSeconds: skipDurationSeconds)
    Logger.app.info("Skip \(offer.kind.rawValue, privacy: .public) \(finishes ? "finish title" : "to \(offer.targetSeconds)s", privacy: .public)\(automatically ? " (countdown)" : "", privacy: .public)")
    skippedKinds.insert(offer.kind)
    skipOfferShownAt = nil
    skippedOffer = offer
    dismissedOffer = nil
    skipCountdownElapsed = 0
    skipCountdownAnchor = nil
    skipOffer = nil
    showSkip(nil)
    if finishes {
      finishTitleFromSkip()
      return
    }
    player.seek(to: CMTime(seconds: offer.targetSeconds, preferredTimescale: 600),
                toleranceBefore: .zero, toleranceAfter: .positiveInfinity)
  }

  /// The viewer wants this part: credits, a recap, the opening of episode 1.
  /// The chip stays down until the playhead leaves the segment.
  func dismissSkip() {
    guard let offer = skipOffer else { return }
    Logger.app.info("Skip dismissed \(offer.kind.rawValue, privacy: .public)")
    dismissedOffer = offer
    skipOfferShownAt = nil
    skipCountdownElapsed = 0
    skipCountdownAnchor = nil
    skipCountdownLeft = 1
    skipOffer = nil
    showSkip(nil)
  }

  private func addSkipTimeObserver() {
    guard skipObserverToken == nil else { return }
    // Four ticks a second: the countdown on the button moves smoothly between them.
    let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
    skipObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
      MainActor.assumeIsolated {
        self?.updateSkipOffer(at: time.seconds.isFinite ? time.seconds : 0)
      }
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
    if let dismissed = dismissedOffer {
      if offer == dismissed { offer = nil } else { dismissedOffer = nil }
    }
    if offer != skipOffer {
      skipOffer = offer
      // A kind skipped once in this stream is offered again, but waits for a press.
      skipOfferShownAt = offer.flatMap { skippedKinds.contains($0.kind) ? nil : seconds }
      skipCountdownElapsed = 0
      skipCountdownAnchor = seconds
      skipCountdownLeft = 1
      showSkip(offer)
    }
#if os(tvOS)
    refreshTVSkipGate()
    guard offer != nil, let shownAt = skipOfferShownAt else { return }
    // Scrubbed back before the button appeared: the countdown starts over from here.
    if seconds < shownAt { skipOfferShownAt = seconds }
    // Transport bar up, or a Speed / Subtitles / Audio menu: Skip is not on
    // screen, so the countdown must not run or fire.
    if skipCountdownSuspended {
      let left = skipCountdownLeft
      if PlaybackSkip.countdown > 0 {
        skipOfferShownAt = seconds - (1 - left) * PlaybackSkip.countdown
      }
      return
    }
    let left = PlaybackSkip.countdownLeft(at: seconds, shownAt: skipOfferShownAt ?? seconds)
    skipCountdownLeft = left
    if left <= 0 {
      performSkip(automatically: true)
    } else {
      updateSkipRing(left)
    }
#else
    guard offer != nil, skipOfferShownAt != nil else {
      skipCountdownLeft = 1
      return
    }
    let style = SkipChipPreferences.style
    guard style.autoSkips else {
      skipCountdownLeft = 1
      skipCountdownAnchor = seconds
      return
    }
    // Chrome hidden, or a subtitle / audio / speed menu open: the clock does not
    // run, so the skip cannot fire while there is nothing on screen to cancel it.
    if skipCountdownSuspended {
      skipCountdownAnchor = seconds
      return
    }
    if let anchor = skipCountdownAnchor, seconds > anchor {
      skipCountdownElapsed += seconds - anchor
    }
    skipCountdownAnchor = seconds
    let left = PlaybackSkip.countdownLeft(elapsed: skipCountdownElapsed,
                                          delay: SkipChipPreferences.delaySeconds)
    skipCountdownLeft = left
    if PlaybackSkip.shouldAutoSkip(style: style, countdownLeft: left) {
      performSkip(automatically: true)
    }
#endif
  }

#if os(tvOS)
  /// Combines the transport-bar delegate flag with a view-tree poll for menus
  /// (Speed, Subtitles, Audio, …) that the bar-visibility callback alone can miss.
  func refreshTVSkipGate() {
    let menu = playerViewController.map(TVPlayerChrome.menuActive(in:)) ?? false
    transportMenuActive = menu
    let suspended = SkipChipVisibility.countdownSuspended(
      chromeVisible: transportBarVisible,
      menuActive: menu,
      chipFollowsChrome: false
    )
    applyTVSkipSuspension(suspended)
  }

  /// Called from `AVPlayerViewControllerDelegate.willTransitionToVisibilityOfTransportBar`.
  func noteTransportBar(visible: Bool) {
    transportBarVisible = visible
    refreshTVSkipGate()
  }

  private func applyTVSkipSuspension(_ suspended: Bool) {
    let changed = skipCountdownSuspended != suspended
    skipCountdownSuspended = suspended
    if suspended {
      playerViewController?.contextualActions = []
    } else if changed, let offer = skipOffer {
      showSkip(offer)
    }
  }
#endif

  /// tvOS: AVKit's own button (`contextualActions`), which it animates in and out. iOS and
  /// the Mac draw `SkipChipOverlay` from `skipOffer`.
  private func showSkip(_ offer: PlaybackSkip.Offer?) {
#if os(tvOS)
    MainActor.assumeIsolated {
      guard let offer else {
        skipAction = nil
        playerViewController?.contextualActions = []
        return
      }
      let symbol = PlaybackSkip.symbolName(for: offer, durationSeconds: skipDurationSeconds)
      let image: UIImage? = skipOfferShownAt == nil
        ? UIImage(systemName: symbol)
        : SkipCountdownGlyph.image(left: 1, symbolName: symbol)
      let action = UIAction(title: PlaybackSkip.title, image: image) { [weak self] _ in
        self?.performSkip()
      }
      action.accessibilityLabel = PlaybackSkip.accessibilityTitle(for: offer.kind)
      skipAction = action
      // AVKit only presents contextual actions while the transport bar is hidden;
      // keep the array empty while chrome or a menu would hide Skip anyway.
      playerViewController?.contextualActions = skipCountdownSuspended ? [] : [action]
    }
#endif
  }

  /// tvOS: the ring beside the label drains as Apple's Next Episode button does; the
  /// action is redrawn in place, not replaced, so AVKit does not animate it in again.
  private func updateSkipRing(_ left: Double) {
#if os(tvOS)
    MainActor.assumeIsolated {
      guard !skipCountdownSuspended, let offer = skipOffer else { return }
      let symbol = PlaybackSkip.symbolName(for: offer, durationSeconds: skipDurationSeconds)
      skipAction?.image = SkipCountdownGlyph.image(left: left, symbolName: symbol)
    }
#endif
  }
}

#if os(tvOS)
/// The glyph of tvOS's skip button: an SF Symbol (`forward.fill` / `forward.end.fill`)
/// inside a ring that drains with the countdown — the shape of the TV app's
/// «Next Episode», with Apple's skip symbols instead of `play.circle`.
@MainActor
enum SkipCountdownGlyph {
  static let side: CGFloat = 38

  static func image(left: Double, symbolName: String) -> UIImage {
    // Twenty steps are enough for the eye and keep the images few.
    let step = (left * 20).rounded() / 20
    let key = "\(symbolName):\(step)"
    if let cached = cache[key] { return cached }
    let size = CGSize(width: side, height: side)
    let symbolConfig = UIImage.SymbolConfiguration(pointSize: side * 0.42, weight: .semibold)
    let symbol = UIImage(systemName: symbolName, withConfiguration: symbolConfig)?
      .withTintColor(.black, renderingMode: .alwaysOriginal)
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
      if let symbol {
        let symbolSize = symbol.size
        let origin = CGPoint(x: (size.width - symbolSize.width) / 2,
                             y: (size.height - symbolSize.height) / 2)
        symbol.draw(at: origin)
      }
    }.withRenderingMode(.alwaysTemplate)
    cache[key] = image
    return image
  }

  private static var cache: [String: UIImage] = [:]
}
#endif
