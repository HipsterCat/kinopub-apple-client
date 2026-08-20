//
//  TrackResolver.swift
//
//

import Foundation

/// Where a remembered choice was learned. Ordered most specific first when resolving,
/// and named so a debug screen can say *why* a title opens the way it does.
public enum TrackMemoryScope: Codable, Hashable {
  /// What this very episode was last watched with. First in the chain, so a rewatch
  /// replays what it played the first time.
  case episode(titleID: Int, season: Int?, episode: Int)
  /// Studios change between seasons — the team that dubbed S1 may not have done S4.
  case season(titleID: Int, season: Int)
  case title(id: Int)
  /// Currently only `anime`. Cartoons are not anime and do not share the bucket.
  case contentClass(String)

  public static let anime = TrackMemoryScope.contentClass("anime")

  /// **The priority chain, most specific first.** The one place the order lives:
  /// episode → season → title → genre → app settings → system languages. The last two
  /// are not scopes — they are the ladder `TrackResolver` falls back to when no scope
  /// here answers, and app settings mirror the system list until they are set.
  public static func chain(titleID: Int,
                           season: Int? = nil,
                           episode: Int? = nil,
                           isAnime: Bool = false) -> [TrackMemoryScope] {
    var scopes: [TrackMemoryScope] = []
    if let episode {
      scopes.append(.episode(titleID: titleID, season: season, episode: episode))
    }
    if let season {
      scopes.append(.season(titleID: titleID, season: season))
    }
    scopes.append(.title(id: titleID))
    if isAnime { scopes.append(.anime) }
    return scopes
  }
}

public struct ScopedLedger: Equatable {
  public let scope: TrackMemoryScope
  public var ledger: TrackPreferenceLedger

  public init(scope: TrackMemoryScope, ledger: TrackPreferenceLedger) {
    self.scope = scope
    self.ledger = ledger
  }
}

public enum AudioSelectionReason: String, Equatable {
  /// The scope's strongest remembered dub was on the menu.
  case remembered
  /// The leader was missing; a weaker remembered dub took it — top-2, top-3.
  case rememberedAlternate
  /// A dub that had never been offered before outranked a habit still under
  /// `TrackPreferenceLedger.confidentWeight`.
  case newBetterDub
  /// No usable history: DUB → MVO → DVO → VO → AVO → Orig within the preferred languages.
  case ladder
  /// The anime toggle, or the dub floor, sent us to the original.
  case originalPreferred
  case onlyOption
  case none
}

public enum SubtitleSelectionReason: String, Equatable {
  case remembered
  /// The audio that won is in a language the viewer does not read.
  case audioNotUnderstood
  case off
  case none
}

public struct TrackDecision: Equatable {
  public var audio: AudioTrackInfo?
  public var subtitle: SubtitleTrack?
  public var audioReason: AudioSelectionReason
  public var subtitleReason: SubtitleSelectionReason
  /// Which scope answered, for the debug view and for "this season you watch Сыендук".
  public var audioScope: TrackMemoryScope?
  public var subtitleScope: TrackMemoryScope?

  public init(audio: AudioTrackInfo? = nil,
              subtitle: SubtitleTrack? = nil,
              audioReason: AudioSelectionReason = .none,
              subtitleReason: SubtitleSelectionReason = .none,
              audioScope: TrackMemoryScope? = nil,
              subtitleScope: TrackMemoryScope? = nil) {
    self.audio = audio
    self.subtitle = subtitle
    self.audioReason = audioReason
    self.subtitleReason = subtitleReason
    self.audioScope = audioScope
    self.subtitleScope = subtitleScope
  }
}

/// **Which dub and which subtitles a title opens with.** One pure function over a menu,
/// what the scopes remember, the settings and the system languages — no player, no
/// network, no storage, so a card can ask it before the player exists.
///
/// The rules and the reason for each: [docs/product/playback-tracks.md].
public enum TrackResolver {

  public static func resolve(audio available: [AudioTrackInfo],
                             subtitles: [SubtitleTrack],
                             ledgers: [ScopedLedger] = [],
                             settings: PlaybackLanguagePreferences = .default,
                             systemLanguages: [String] = Locale.preferredLanguages,
                             profile: TitleTrackProfile = TitleTrackProfile()) -> TrackDecision {
    let languages = settings.resolvedAudioLanguages(system: systemLanguages)
    let (audioTrack, audioReason, audioScope) = resolveAudio(available: available,
                                                             ledgers: ledgers,
                                                             settings: settings,
                                                             languages: languages,
                                                             profile: profile)
    let (subtitleTrack, subtitleReason, subtitleScope) =
      resolveSubtitle(chosen: audioTrack,
                      subtitles: subtitles,
                      ledgers: ledgers,
                      settings: settings,
                      systemLanguages: systemLanguages)

    return TrackDecision(audio: audioTrack,
                         subtitle: subtitleTrack,
                         audioReason: audioReason,
                         subtitleReason: subtitleReason,
                         audioScope: audioScope,
                         subtitleScope: subtitleScope)
  }

  // MARK: - Audio

  private static func resolveAudio(available: [AudioTrackInfo],
                                   ledgers: [ScopedLedger],
                                   settings: PlaybackLanguagePreferences,
                                   languages: [String],
                                   profile: TitleTrackProfile)
  -> (AudioTrackInfo?, AudioSelectionReason, TrackMemoryScope?) {
    guard !available.isEmpty else { return (nil, .none, nil) }

    let ladderPick = ladderChoice(available: available,
                                  languages: languages,
                                  settings: settings,
                                  profile: profile)

    for scoped in ledgers {
      let ladder = scoped.ledger.audioLadder
      guard let hit = ladder.enumerated().first(where: { pair in
        available.contains { pair.element.signature.matches($0) }
      }) else { continue }

      guard let match = available.first(where: { hit.element.signature.matches($0) }) else { continue }

      // A dub that has never been on a menu here, and that outranks a habit still under
      // the confidence floor, wins: the stopgap was never a preference, it was the only
      // thing there when the series started.
      if let ladderPick,
         hit.element.weight < TrackPreferenceLedger.confidentWeight,
         !scoped.ledger.seenAudio.contains(ladderPick.track.signature),
         isBetter(ladderPick.track, than: match, languages: languages) {
        return (ladderPick.track, .newBetterDub, nil)
      }

      return (match, hit.offset == 0 ? .remembered : .rememberedAlternate, scoped.scope)
    }

    if available.count == 1 { return (available[0], .onlyOption, nil) }
    if let ladderPick { return (ladderPick.track, ladderPick.reason, nil) }
    return (AudioTracks.sort(available, preferredLanguages: languages).first, .ladder, nil)
  }

  /// The no-history answer: the anime original, else the preferred languages in order
  /// subject to the dub floor, else the original, else the global ladder.
  private static func ladderChoice(available: [AudioTrackInfo],
                                   languages: [String],
                                   settings: PlaybackLanguagePreferences,
                                   profile: TitleTrackProfile)
  -> (track: AudioTrackInfo, reason: AudioSelectionReason)? {
    if profile.isAnime,
       settings.animePrefersOriginalAudio,
       let original = profile.originalLanguageKey,
       let track = best(available.filter { $0.languageKey == original }, languages: languages) {
      return (track, .originalPreferred)
    }

    // Set once the floor has emptied a language that did have tracks: whatever we land on
    // afterwards, we are there because the dub on offer was not good enough.
    var floorEmptiedALanguage = false

    for language in languages {
      let inLanguage = available.filter { $0.languageKey == language }
      guard !inLanguage.isEmpty else { continue }
      let allowed: [AudioTrackInfo]
      if let floor = settings.minimumDubKind {
        // Original (5) and unknown (6) kinds pass: the floor is about dub quality, and an
        // original track is not a dub.
        allowed = inLanguage.filter { $0.kindRank <= floor || $0.kindRank >= 5 }
      } else {
        allowed = inLanguage
      }
      guard let track = best(allowed, languages: languages) else {
        floorEmptiedALanguage = true
        continue
      }
      return (track, floorEmptiedALanguage ? .originalPreferred : .ladder)
    }

    if let original = profile.originalLanguageKey,
       let track = best(available.filter { $0.languageKey == original }, languages: languages) {
      return (track, .originalPreferred)
    }

    // The floor is a preference for the original, so find one even where the country
    // heuristic could not name its language.
    if settings.minimumDubKind != nil,
       let track = best(available.filter { $0.kindRank == 5 }, languages: languages) {
      return (track, .originalPreferred)
    }

    // The floor prefers the original; it never refuses to play.
    guard let track = best(available, languages: languages) else { return nil }
    return (track, .ladder)
  }

  private static func best(_ tracks: [AudioTrackInfo], languages: [String]) -> AudioTrackInfo? {
    AudioTracks.sort(tracks, preferredLanguages: languages).first
  }

  private static func isBetter(_ lhs: AudioTrackInfo,
                               than rhs: AudioTrackInfo,
                               languages: [String]) -> Bool {
    AudioTracks.sortKey(for: lhs, preferredLanguages: languages)
      < AudioTracks.sortKey(for: rhs, preferredLanguages: languages)
  }

  // MARK: - Subtitles

  private static func resolveSubtitle(chosen: AudioTrackInfo?,
                                      subtitles: [SubtitleTrack],
                                      ledgers: [ScopedLedger],
                                      settings: PlaybackLanguagePreferences,
                                      systemLanguages: [String])
  -> (SubtitleTrack?, SubtitleSelectionReason, TrackMemoryScope?) {
    for scoped in ledgers {
      for entry in scoped.ledger.subtitleLadder {
        if entry.signature.isOff { return (nil, .remembered, scoped.scope) }
        if let track = entry.signature.resolve(in: subtitles) {
          return (track, .remembered, scoped.scope)
        }
      }
    }

    guard !subtitles.isEmpty else { return (nil, .none, nil) }

    if settings.subtitlesWhenAudioNotUnderstood,
       let chosen,
       !settings.readingLanguages(system: systemLanguages).contains(chosen.languageKey) {
      for language in settings.resolvedSubtitleLanguages(system: systemLanguages) {
        if let track = SubtitleTracks.preferred(language: language,
                                                in: subtitles,
                                                preferNonCC: settings.preferNonCCSubtitles) {
          return (track, .audioNotUnderstood, nil)
        }
      }
    }

    return (nil, .off, nil)
  }
}
