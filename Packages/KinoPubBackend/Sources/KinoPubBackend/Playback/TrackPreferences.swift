//
//  TrackPreferences.swift
//
//

import Foundation

// MARK: - Signatures

/// How a dub is recognised again on the next episode.
///
/// Not the HLS rendition name, not the index, not the URL — those differ between two
/// episodes of one season, so a choice remembered that way pre-selects nothing on the
/// next one. Language + kind + studio is what a viewer means by "the same озвучка".
public struct AudioTrackSignature: Codable, Hashable {
  public let languageKey: String
  /// `AudioTracks.kindRank`: 0 DUB, 1 MVO, 2 DVO, 3 VO, 4 AVO, 5 Orig, 6 unknown.
  public let kindRank: Int
  /// Trimmed, **original case** — this is what `displayLabel` shows, so lowercasing it
  /// here would turn "Мосфильм" into "мосфильм" on screen. Equality and hashing compare
  /// `studioKey` instead, so two differently-cased spellings of one studio are still one
  /// signature.
  public let studio: String?

  public init(languageKey: String, kindRank: Int, studio: String?) {
    self.languageKey = SubtitleTracks.languageKey(languageKey)
    self.kindRank = kindRank
    let trimmed = studio?.trimmingCharacters(in: .whitespacesAndNewlines)
    self.studio = (trimmed?.isEmpty ?? true) ? nil : trimmed
  }

  public init(_ track: AudioTrackInfo) {
    self.init(languageKey: track.lang, kindRank: track.kindRank, studio: track.authorTitle)
  }

  private var studioKey: String? { studio?.lowercased() }

  public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.languageKey == rhs.languageKey && lhs.kindRank == rhs.kindRank && lhs.studioKey == rhs.studioKey
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(languageKey)
    hasher.combine(kindRank)
    hasher.combine(studioKey)
  }

  /// A studio that keeps its name across a kind change is the same choice: when a team
  /// upgrades its two-voice track to a full dub, the viewer who followed that team still
  /// wants it. Language alone is deliberately *not* a match — "some other Russian track"
  /// is exactly what remembering a dub is supposed to prevent.
  public func matches(_ track: AudioTrackInfo) -> Bool {
    let candidate = AudioTrackSignature(track)
    if candidate == self { return true }
    guard let studioKey, let otherKey = candidate.studioKey else { return false }
    return candidate.languageKey == languageKey && otherKey == studioKey
  }
}

public extension AudioTrackSignature {
  /// How a remembered dub reads on screen — "Русский ∙ Дубляж, LostFilm". Built from the
  /// signature alone, because that is all a stored preference has: the API row it came from
  /// belongs to an episode that may be long gone.
  var displayLabel: String {
    let language = LanguageNames.name(for: languageKey)
    let kind = AudioTracks.localizedKindLabel(rank: kindRank)
    switch (kind, studio) {
    case let (kind?, studio?): return "\(language) ∙ \(kind), \(studio)"
    case let (kind?, nil): return "\(language) ∙ \(kind)"
    case let (nil, studio?): return "\(language) ∙ \(studio)"
    case (nil, nil): return language
    }
  }
}

/// A remembered subtitle choice. `languageKey == nil` means **off**, which is a choice
/// worth storing — otherwise the default turns subtitles back on every episode.
public struct SubtitleChoiceSignature: Codable, Hashable {

  public let languageKey: String?
  public let isCC: Bool

  public init(languageKey: String?, isCC: Bool) {
    self.languageKey = languageKey.map { SubtitleTracks.languageKey($0) }
    self.isCC = isCC
  }

  public init(_ track: SubtitleTrack) {
    self.init(languageKey: track.lang, isCC: track.isCC)
  }

  public static let off = SubtitleChoiceSignature(languageKey: nil, isCC: false)

  public var isOff: Bool { languageKey == nil }

  /// How a remembered subtitle choice reads on screen.
  public var displayLabel: String {
    guard let languageKey else { return String(localized: "Off", bundle: .module) }
    let language = LanguageNames.name(for: languageKey)
    return isCC ? "\(language) (CC)" : language
  }

  /// Language first, CC-ness as a preference rather than a requirement: a viewer who
  /// picked a plain track should still get one when only a CC track survived.
  public func resolve(in tracks: [SubtitleTrack]) -> SubtitleTrack? {
    guard let languageKey else { return nil }
    let sameLanguage = tracks.filter {
      SubtitleTracks.languageKey($0.lang) == languageKey && !$0.isForced
    }
    guard !sameLanguage.isEmpty else { return nil }
    let sameKind = sameLanguage.filter { $0.isCC == isCC }
    let ranked = sameKind.isEmpty ? sameLanguage : sameKind
    return ranked.first(where: \.hasSidecar) ?? ranked.first
  }
}

// MARK: - Track conveniences

public extension AudioTrackInfo {
  var kindRank: Int {
    AudioTracks.kindRank(typeId: typeId, typeTitle: typeTitle, typeShortTitle: typeShortTitle)
  }

  var languageKey: String { SubtitleTracks.languageKey(lang) }

  var signature: AudioTrackSignature { AudioTrackSignature(self) }
}

// MARK: - Ledger

public struct AudioLedgerEntry: Codable, Equatable {
  public var signature: AudioTrackSignature
  /// Episodes actually watched with this dub, plus explicit picks. Not picker opens —
  /// two episodes of a stopgap must never outrank a season of the real preference.
  public var weight: Int
  public var lastPlayedAt: Date
  /// When the viewer last chose this one **themselves**, in the player's menu. The latest
  /// pick leads its scope whatever the weights say (`TrackPreferenceLedger.audioLadder`).
  /// Optional so ledgers stored before it decode unchanged.
  public var pickedAt: Date?

  public init(signature: AudioTrackSignature, weight: Int = 1, lastPlayedAt: Date = Date(),
              pickedAt: Date? = nil) {
    self.signature = signature
    self.weight = weight
    self.lastPlayedAt = lastPlayedAt
    self.pickedAt = pickedAt
  }
}

public struct SubtitleLedgerEntry: Codable, Equatable {
  public var signature: SubtitleChoiceSignature
  public var weight: Int
  public var lastPlayedAt: Date
  /// See `AudioLedgerEntry.pickedAt`.
  public var pickedAt: Date?

  public init(signature: SubtitleChoiceSignature, weight: Int = 1, lastPlayedAt: Date = Date(),
              pickedAt: Date? = nil) {
    self.signature = signature
    self.weight = weight
    self.lastPlayedAt = lastPlayedAt
    self.pickedAt = pickedAt
  }
}

/// What both kinds of ledger entry share, so one ordering serves both ladders.
protocol RankedLedgerEntry {
  var weight: Int { get }
  var lastPlayedAt: Date { get }
  var pickedAt: Date? { get }
}

extension AudioLedgerEntry: RankedLedgerEntry {}
extension SubtitleLedgerEntry: RankedLedgerEntry {}

extension Array where Element: RankedLedgerEntry {
  /// **The viewer's latest own pick first, then the rest by count, then recency.**
  ///
  /// Count alone made a pick in the player worthless: a season watched without subtitles is
  /// "off" × 9, turning them on in episode 10 is "eng" × 1, and episode 11 opened without
  /// them again — the same for a dub. A pick is the one input that says what the viewer
  /// wants *now*, so the next episode follows it until they pick something else. Below the
  /// pick, count before recency still keeps one stray automatic play from displacing a
  /// season.
  func ranked() -> [Element] {
    let byCount = sorted { lhs, rhs in
      if lhs.weight != rhs.weight { return lhs.weight > rhs.weight }
      return lhs.lastPlayedAt > rhs.lastPlayedAt
    }
    guard let latestPick = byCount.indices
      .filter({ byCount[$0].pickedAt != nil })
      .max(by: { byCount[$0].pickedAt! < byCount[$1].pickedAt! }) else { return byCount }
    var ranked = byCount
    let leader = ranked.remove(at: latestPick)
    return [leader] + ranked
  }
}

/// What one scope — a season, a title, or the anime class — has learned.
///
/// Rules and their reasons: [docs/product/playback-tracks.md].
public struct TrackPreferenceLedger: Codable, Equatable {

  /// Weight at which a habit stops being provisional. Below it, a dub that has *never
  /// been on a menu before* and outranks the habit takes over; at or above it the habit
  /// holds. Three episodes is the smallest number that separates "this is what I watch"
  /// from "this was the only thing there when I started".
  public static let confidentWeight = 3

  public var audio: [AudioLedgerEntry]
  public var subtitles: [SubtitleLedgerEntry]
  /// Every dub this scope has ever been offered. A signature missing from here is *new*,
  /// which is what lets a dub that arrived after the fact beat a provisional habit.
  public var seenAudio: Set<AudioTrackSignature>

  public init(audio: [AudioLedgerEntry] = [],
              subtitles: [SubtitleLedgerEntry] = [],
              seenAudio: Set<AudioTrackSignature> = []) {
    self.audio = audio
    self.subtitles = subtitles
    self.seenAudio = seenAudio
  }

  public var isEmpty: Bool { audio.isEmpty && subtitles.isEmpty }

  // MARK: Reading

  /// Strongest first: the viewer's latest own pick, then weight, then most recently played
  /// (`ranked()`).
  public var audioLadder: [AudioLedgerEntry] { audio.ranked() }

  public var subtitleLadder: [SubtitleLedgerEntry] { subtitles.ranked() }

  // MARK: Writing

  /// Record what this episode offered. Call it whether or not anything was chosen —
  /// "seen" is about the menu, not the pick.
  public mutating func noteMenu(_ tracks: [AudioTrackInfo]) {
    for track in tracks { seenAudio.insert(track.signature) }
  }

  /// `picked`: the viewer chose this in the player's menu, as opposed to watching what the
  /// episode opened with. A pick leads the scope from now on (`audioLadder`).
  public mutating func recordAudio(_ signature: AudioTrackSignature,
                                   at date: Date = Date(),
                                   weight: Int = 1,
                                   picked: Bool = false) {
    seenAudio.insert(signature)
    if let index = audio.firstIndex(where: { $0.signature == signature }) {
      audio[index].weight += weight
      audio[index].lastPlayedAt = date
      if picked { audio[index].pickedAt = date }
    } else {
      audio.append(AudioLedgerEntry(signature: signature, weight: weight, lastPlayedAt: date,
                                    pickedAt: picked ? date : nil))
    }
  }

  public mutating func recordSubtitle(_ signature: SubtitleChoiceSignature,
                                      at date: Date = Date(),
                                      weight: Int = 1,
                                      picked: Bool = false) {
    if let index = subtitles.firstIndex(where: { $0.signature == signature }) {
      subtitles[index].weight += weight
      subtitles[index].lastPlayedAt = date
      if picked { subtitles[index].pickedAt = date }
    } else {
      subtitles.append(SubtitleLedgerEntry(signature: signature, weight: weight, lastPlayedAt: date,
                                           pickedAt: picked ? date : nil))
    }
  }
}

// MARK: - Settings

/// **Whether a title opens with subtitles** — Plex's three answers, because they are the
/// ones a viewer actually means (Sasha, 2026-11-01). A pick in the player overrides it for
/// that title until the next pick (`TrackResolver`).
public enum SubtitleMode: String, CaseIterable, Codable {
  /// Every title, in the first preferred subtitle language it offers.
  case always
  /// Only when the audio that plays is in none of the preferred **audio** languages.
  case foreignAudio
  /// Never by themselves.
  case manual
}

/// The app-level half of the ladder. Everything here is a user setting; nothing here is
/// per title.
public struct PlaybackLanguagePreferences: Equatable {
  /// Ordered. Empty means "use the system's preferred languages", which is the default
  /// and covers the viewer who never opens Settings.
  public var audioLanguages: [String]
  /// Ordered. Empty mirrors the resolved audio languages.
  public var subtitleLanguages: [String]
  /// Worst dub kind (`AudioTracks.kindRank`) still preferred over original audio with
  /// subtitles. `nil` = no floor. Original (5) and unknown (6) kinds are never filtered
  /// by it — the floor is about dub quality, and an original track is not a dub.
  public var minimumDubKind: Int?
  /// When subtitles come on without being picked. The app's own setting; until it is set,
  /// the system's captions setting answers (`.alwaysOn` there is `.always` here).
  public var subtitleMode: SubtitleMode
  /// On an anime, original audio plus subtitles wins even when a dub exists.
  public var animePrefersOriginalAudio: Bool
  public var preferNonCCSubtitles: Bool

  public init(audioLanguages: [String] = [],
              subtitleLanguages: [String] = [],
              minimumDubKind: Int? = nil,
              subtitleMode: SubtitleMode = .foreignAudio,
              animePrefersOriginalAudio: Bool = false,
              preferNonCCSubtitles: Bool = true) {
    self.audioLanguages = audioLanguages
    self.subtitleLanguages = subtitleLanguages
    self.minimumDubKind = minimumDubKind
    self.subtitleMode = subtitleMode
    self.animePrefersOriginalAudio = animePrefersOriginalAudio
    self.preferNonCCSubtitles = preferNonCCSubtitles
  }

  public static let `default` = PlaybackLanguagePreferences()

  public func resolvedAudioLanguages(system: [String]) -> [String] {
    let explicit = audioLanguages.filter { !$0.isEmpty }
    let source = explicit.isEmpty ? system : explicit
    return uniqueKeys(source)
  }

  public func resolvedSubtitleLanguages(system: [String]) -> [String] {
    let explicit = subtitleLanguages.filter { !$0.isEmpty }
    guard explicit.isEmpty else { return uniqueKeys(explicit) }
    return resolvedAudioLanguages(system: system)
  }

  private func uniqueKeys(_ codes: [String]) -> [String] {
    var seen = Set<String>()
    return codes.compactMap { code in
      let key = SubtitleTracks.languageKey(code)
      guard !key.isEmpty, seen.insert(key).inserted else { return nil }
      return key
    }
  }
}

// MARK: - Title profile

/// The two things about a title that change how its tracks are chosen. Both are derived
/// from what the item payload already carries — nothing is fetched for this.
public struct TitleTrackProfile: Equatable {
  public var isAnime: Bool
  public var originalLanguageKey: String?

  public init(isAnime: Bool = false, originalLanguageKey: String? = nil) {
    self.isAnime = isAnime
    self.originalLanguageKey = originalLanguageKey.map { SubtitleTracks.languageKey($0) }
  }

  /// The original language, guessed from the countries on the title against the languages
  /// actually on the menu — *"страна есть, язык субтитров есть: ого, Япония и японский"*.
  /// A country whose language nothing on the menu speaks is ignored, which is what keeps
  /// the guess from inventing a track that does not exist.
  public static func inferOriginalLanguage(countries: [String],
                                           trackLanguages: [String]) -> String? {
    let available = Set(trackLanguages.map { SubtitleTracks.languageKey($0) })
    for country in countries {
      guard let key = countryLanguages[normalizedCountry(country)] else { continue }
      if available.contains(key) { return key }
    }
    return nil
  }

  /// **`isAnime` is not decided here.** `MediaPresentationProfile` is the one place a
  /// rule that depends on type or genre is derived; a second genre classifier is how the
  /// same word ends up meaning two things on two surfaces.
  public static func infer(presentation: MediaPresentationProfile,
                           countries: [String],
                           trackLanguages: [String]) -> TitleTrackProfile {
    TitleTrackProfile(
      isAnime: presentation.isAnime,
      originalLanguageKey: inferOriginalLanguage(countries: countries,
                                                 trackLanguages: trackLanguages)
    )
  }

  private static func normalizedCountry(_ country: String) -> String {
    country.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// Deliberately short. kino.pub names countries in Russian, and a title with more than
  /// two languages on the menu is rare enough that guessing harder buys nothing.
  private static let countryLanguages: [String: String] = [
    "япония": "ja", "japan": "ja",
    "китай": "zh", "china": "zh", "гонконг": "zh", "hong kong": "zh", "тайвань": "zh",
    "корея": "ko", "южная корея": "ko", "korea": "ko", "south korea": "ko",
    "россия": "ru", "russia": "ru", "ссср": "ru", "ussr": "ru",
    "сша": "en", "usa": "en", "великобритания": "en", "uk": "en", "австралия": "en",
    "франция": "fr", "france": "fr",
    "германия": "de", "germany": "de",
    "испания": "es", "spain": "es",
    "италия": "it", "italy": "it",
    "турция": "tr", "turkey": "tr",
    "индия": "hi", "india": "hi",
    "польша": "pl", "poland": "pl",
    "украина": "uk", "ukraine": "uk"
  ]
}
