//
//  PlaybackPreferences.swift
//  KinoPubAppleClient
//
//  Settings › Video & audio: what happens when an episode ends.
//

import Foundation
import KinoPubBackend

enum PlaybackPreferences {
  static let autoPlayNextEpisodeKey = "autoPlayNextEpisode"
  static let autoPlayNextSeasonKey = "autoPlayNextSeason"

  /// Play the next episode in the same season when this one ends. Default on.
  static var autoPlayNextEpisode: Bool {
    boolValue(forKey: autoPlayNextEpisodeKey, default: true)
  }

  /// Also play the first episode of the next season. Default off: end of a season
  /// dismisses, the same as end of a series.
  static var autoPlayNextSeason: Bool {
    boolValue(forKey: autoPlayNextSeasonKey, default: false)
  }

  static var policy: PlaybackEndPolicy {
    PlaybackEndPolicy(autoPlayNextEpisode: autoPlayNextEpisode,
                      autoPlayNextSeason: autoPlayNextSeason)
  }

  private static func boolValue(forKey key: String, default fallback: Bool) -> Bool {
    guard UserDefaults.standard.object(forKey: key) != nil else { return fallback }
    return UserDefaults.standard.bool(forKey: key)
  }
}
