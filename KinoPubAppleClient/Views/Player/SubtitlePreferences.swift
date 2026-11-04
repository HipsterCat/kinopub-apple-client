//
//  SubtitlePreferences.swift
//  KinoPubAppleClient
//

import Foundation
import KinoPubBackend
import MediaAccessibility

enum SubtitlePreferences {
  /// Retired: the subtitle language list says the same, ordered. Read once, by
  /// `PlaybackLanguageList.migrateEnglishFirstIfNeeded`.
  static let preferEnglishKey = "preferEnglishSubtitles"
  static let preferNonCCKey = "preferNonCCSubtitles"
  static let dualSubtitlesKey = "dualSubtitlesEnabled"
  static let secondSubtitleLanguageKey = "secondSubtitleLanguage"

  /// Languages offered as the second track. The first one is whatever the item is
  /// being watched in — usually English.
  static let secondLanguageOptions = ["ru", "en", "uk", "de", "fr", "es"]

  static var preferNonCCSubtitles: Bool {
    boolValue(forKey: preferNonCCKey, default: true)
  }

  /// Off by default: two lines of text is a deliberate choice, not something to wake
  /// up to.
  static var dualSubtitlesEnabled: Bool {
    boolValue(forKey: dualSubtitlesKey, default: false)
  }

  static var secondSubtitleLanguage: String {
    UserDefaults.standard.string(forKey: secondSubtitleLanguageKey) ?? "ru"
  }

  private static func boolValue(forKey key: String, default fallback: Bool) -> Bool {
    guard UserDefaults.standard.object(forKey: key) != nil else { return fallback }
    return UserDefaults.standard.bool(forKey: key)
  }
}

extension PlaybackLanguagePreferences {

  static let audioLanguagesKey = "preferredAudioLanguages"
  static let subtitleLanguagesKey = "preferredSubtitleLanguages"
  static let minimumDubKindKey = "minimumDubKind"
  static let subtitleModeKey = "subtitleMode"
  /// Never written by any build; read only so a value set by hand is not lost.
  static let subtitlesDefaultOnKey = "subtitlesDefaultOn"
  static let subtitlesForForeignAudioKey = "subtitlesForForeignAudio"
  static let animeOriginalAudioKey = "animePrefersOriginalAudio"

  /// `minimumDubKind` when the viewer has set no floor.
  static let noDubFloor = -1

  /// The language ladder as the viewer has it. Empty lists mean "mirror the system",
  /// which is the default and covers anyone who never opens Settings.
  static var current: PlaybackLanguagePreferences {
    PlaybackLanguageList.migrateEnglishFirstIfNeeded()
    let defaults = UserDefaults.standard
    var subtitleLanguages = defaults.stringArray(forKey: subtitleLanguagesKey) ?? []
    if subtitleLanguages.isEmpty { subtitleLanguages = systemCaptionLanguages }
    return PlaybackLanguagePreferences(
      audioLanguages: defaults.stringArray(forKey: audioLanguagesKey) ?? [],
      subtitleLanguages: subtitleLanguages,
      // Stored as an Int because `@AppStorage` has no Int? — negative means "no floor",
      // which is also what a missing key means.
      minimumDubKind: (defaults.object(forKey: minimumDubKindKey) as? Int).flatMap { $0 < 0 ? nil : $0 },
      subtitleMode: subtitleMode,
      animePrefersOriginalAudio: defaults.bool(forKey: animeOriginalAudioKey),
      preferNonCCSubtitles: SubtitlePreferences.preferNonCCSubtitles
    )
  }

  /// The app's own answer once it is set; until then the system's — Accessibility ›
  /// Subtitles & Captioning *Always On* is "Always enabled", anything else "Shown with
  /// foreign audio", which is what the app did before it had the setting.
  static var subtitleMode: SubtitleMode {
    let defaults = UserDefaults.standard
    if let raw = defaults.string(forKey: subtitleModeKey), let mode = SubtitleMode(rawValue: raw) {
      return mode
    }
    if defaults.object(forKey: subtitlesDefaultOnKey) as? Bool == true { return .always }
    if defaults.object(forKey: subtitlesForForeignAudioKey) as? Bool == false { return .manual }
    return systemWantsCaptions ? .always : .foreignAudio
  }

  static func setSubtitleMode(_ mode: SubtitleMode) {
    UserDefaults.standard.set(mode.rawValue, forKey: subtitleModeKey)
  }

  /// **Where the viewer already answered "do I watch with subtitles".** Settings →
  /// Accessibility → Subtitles & Captioning, read through `MediaAccessibility`. Answering
  /// it a second time in our own Settings, with its own default, is how an app ends up
  /// disagreeing with the rest of the system about the same preference.
  ///
  /// `.alwaysOn` is the only value that means "on". `.automatic` is the stock default and
  /// means "let the content decide", which for us is the foreign-audio rule below.
  static var systemWantsCaptions: Bool {
    MACaptionAppearanceGetDisplayType(.user) == .alwaysOn
  }

  /// The caption languages chosen in the same place, most preferred first.
  static var systemCaptionLanguages: [String] {
    // Non-optional `Unmanaged<CFArray>`, so there is nothing to bind — take the value and
    // let the bridge cast decide whether it holds strings.
    let copied = MACaptionAppearanceCopySelectedLanguages(.user).takeRetainedValue()
    return (copied as NSArray) as? [String] ?? []
  }
}

extension SubtitleMode {
  /// Plex's wording, which is the clearest anyone has put it.
  var title: String {
    switch self {
    case .always: "Always enabled".localized
    case .foreignAudio: "Shown with foreign audio".localized
    case .manual: "Manually selected".localized
    }
  }
}

/// **The two ordered language lists the viewer edits** — audio and subtitles. Empty in
/// storage means "the system's", which is what the editor shows until the first change:
/// the system's preferred languages for audio, its caption languages (else the audio list)
/// for subtitles.
enum PlaybackLanguageList {
  enum Kind { case audio, subtitles }

  /// What can be added. kino.pub's own subtitle language list, as language keys.
  static let catalog = ["ru", "en", "uk", "de", "fr", "es", "it", "pt", "pl", "fi", "sv", "no",
                        "da", "ro", "tr", "he", "hi", "zh", "ja", "ko", "kk", "uz", "fil"]

  private static func key(_ kind: Kind) -> String {
    kind == .audio ? PlaybackLanguagePreferences.audioLanguagesKey
      : PlaybackLanguagePreferences.subtitleLanguagesKey
  }

  /// The list as it decides, most preferred first.
  static func languages(_ kind: Kind) -> [String] {
    let settings = PlaybackLanguagePreferences.current
    switch kind {
    case .audio: return settings.resolvedAudioLanguages(system: Locale.preferredLanguages)
    case .subtitles: return settings.resolvedSubtitleLanguages(system: Locale.preferredLanguages)
    }
  }

  /// Whether the viewer has changed it, i.e. it no longer follows the system.
  static func isCustom(_ kind: Kind) -> Bool {
    !(UserDefaults.standard.stringArray(forKey: key(kind)) ?? []).isEmpty
  }

  /// Emptying the list hands it back to the system rather than leaving nothing to decide by.
  static func set(_ kind: Kind, _ codes: [String]) {
    var seen = Set<String>()
    let keys = codes.map(SubtitleTracks.languageKey).filter { !$0.isEmpty && seen.insert($0).inserted }
    if keys.isEmpty {
      UserDefaults.standard.removeObject(forKey: key(kind))
    } else {
      UserDefaults.standard.set(keys, forKey: key(kind))
    }
  }

  /// The list exactly as stored — empty for "the system's" — so an edit can be undone.
  static func stored(_ kind: Kind) -> [String] {
    UserDefaults.standard.stringArray(forKey: key(kind)) ?? []
  }

  static func restore(_ kind: Kind, _ stored: [String]) {
    if stored.isEmpty { reset(kind) } else { UserDefaults.standard.set(stored, forKey: key(kind)) }
  }

  static func reset(_ kind: Kind) {
    UserDefaults.standard.removeObject(forKey: key(kind))
  }

  static func add(_ code: String, to kind: Kind) {
    set(kind, languages(kind) + [code])
  }

  static func remove(_ code: String, from kind: Kind) {
    set(kind, languages(kind).filter { $0 != code })
  }

  /// `offset` −1 is up, +1 down.
  static func move(_ code: String, in kind: Kind, by offset: Int) {
    var list = languages(kind)
    guard let index = list.firstIndex(of: code) else { return }
    let target = index + offset
    guard list.indices.contains(target) else { return }
    list.swapAt(index, target)
    set(kind, list)
  }

  static func addable(to kind: Kind) -> [String] {
    let present = Set(languages(kind))
    return catalog.filter { !present.contains($0) }
  }

  /// "Default English subtitles" (on unless switched off) put English first in front of
  /// whatever the list was. It is gone; its effect is written into the list once, where the
  /// viewer can now see and reorder it.
  static func migrateEnglishFirstIfNeeded() {
    let defaults = UserDefaults.standard
    let doneKey = "subtitleLanguagesMigratedFromEnglishToggle"
    guard !defaults.bool(forKey: doneKey) else { return }
    defaults.set(true, forKey: doneKey)
    let englishFirst = defaults.object(forKey: SubtitlePreferences.preferEnglishKey) as? Bool ?? true
    let stored = defaults.stringArray(forKey: key(.subtitles)) ?? []
    guard englishFirst, stored.isEmpty else { return }
    let system = PlaybackLanguagePreferences.systemCaptionLanguages
    let base = system.isEmpty ? Locale.preferredLanguages : system
    set(.subtitles, ["en"] + base)
  }
}
