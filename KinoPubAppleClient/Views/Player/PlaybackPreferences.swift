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

/// Home's Continue Watching row, as the viewer set it up (Settings › Tabs & Home), like
/// Plex's "Weeks to consider for Continue Watching" and "Include bookmarks".
enum ContinueWatchingPreferences {
  static let weeksKey = "continueWatchingWeeks"
  static let includesBookmarksKey = "continueWatchingIncludesBookmarks"

  /// Not watched, released or bookmarked in this many weeks: off the row. Default 8.
  static var weeks: Int {
    let stored = UserDefaults.standard.integer(forKey: weeksKey)
    return stored > 0 ? stored : ContinueWatchingOrder.Rules.defaultWeeks
  }

  /// Mix bookmarks in by the date they were added. Default on.
  static var includesBookmarks: Bool {
    guard UserDefaults.standard.object(forKey: includesBookmarksKey) != nil else { return true }
    return UserDefaults.standard.bool(forKey: includesBookmarksKey)
  }

  static var rules: ContinueWatchingOrder.Rules {
    ContinueWatchingOrder.Rules(weeks: weeks, includesBookmarks: includesBookmarks)
  }

  static func setWeeks(_ weeks: Int) {
    UserDefaults.standard.set(weeks, forKey: weeksKey)
    rowRulesDidChange()
  }

  static func setIncludesBookmarks(_ isOn: Bool) {
    UserDefaults.standard.set(isOn, forKey: includesBookmarksKey)
    rowRulesDidChange()
  }

  /// The row is refetched with the new rules — the same path a watch invalidate takes.
  private static func rowRulesDidChange() {
    NotificationCenter.default.post(name: .contentStoreDidInvalidateWatch, object: nil)
  }
}
