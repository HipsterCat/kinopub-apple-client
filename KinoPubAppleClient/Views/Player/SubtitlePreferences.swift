//
//  SubtitlePreferences.swift
//  KinoPubAppleClient
//

import Foundation
import KinoPubBackend

enum SubtitlePreferences {
  static let preferEnglishKey = "preferEnglishSubtitles"
  static let preferNonCCKey = "preferNonCCSubtitles"
  static let dualSubtitlesKey = "dualSubtitlesEnabled"
  static let secondSubtitleLanguageKey = "secondSubtitleLanguage"

  /// Languages offered as the second track. The first one is whatever the item is
  /// being watched in — usually English.
  static let secondLanguageOptions = ["ru", "en", "uk", "de", "fr", "es"]

  static var preferEnglishSubtitles: Bool {
    boolValue(forKey: preferEnglishKey, default: true)
  }

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
  static let subtitlesForForeignAudioKey = "subtitlesForForeignAudio"
  static let animeOriginalAudioKey = "animePrefersOriginalAudio"

  /// The language ladder as the viewer has it. Empty lists mean "mirror the system",
  /// which is the default and covers anyone who never opens Settings.
  static var current: PlaybackLanguagePreferences {
    let defaults = UserDefaults.standard
    var subtitleLanguages = defaults.stringArray(forKey: subtitleLanguagesKey) ?? []
    // Interim mapping for the old "Default English subtitles" toggle: subtitles no longer
    // come on merely because English exists — they come on when the audio is in a language
    // the viewer does not read — so the switch now says *which* language wins when they do.
    if SubtitlePreferences.preferEnglishSubtitles, !subtitleLanguages.contains("en") {
      subtitleLanguages.insert("en", at: 0)
    }
    return PlaybackLanguagePreferences(
      audioLanguages: defaults.stringArray(forKey: audioLanguagesKey) ?? [],
      subtitleLanguages: subtitleLanguages,
      minimumDubKind: defaults.object(forKey: minimumDubKindKey) as? Int,
      subtitlesWhenAudioNotUnderstood: defaults.object(forKey: subtitlesForForeignAudioKey) == nil
        ? true
        : defaults.bool(forKey: subtitlesForForeignAudioKey),
      animePrefersOriginalAudio: defaults.bool(forKey: animeOriginalAudioKey),
      preferNonCCSubtitles: SubtitlePreferences.preferNonCCSubtitles
    )
  }
}
