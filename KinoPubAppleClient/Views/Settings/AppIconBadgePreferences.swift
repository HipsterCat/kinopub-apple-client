//
//  AppIconBadgePreferences.swift
//  KinoPubAppleClient
//
//  Settings › Notifications › App Icon Badge. The Watchlist tab badge is separate.
//

import Foundation
import KinoPubBackend
#if canImport(UserNotifications)
import UserNotifications
#endif
#if canImport(UIKit)
import UIKit
#endif

enum AppIconBadgePreferences {
  static let enabledKey = "settings.appIconBadge.enabled"
  static let modeKey = "settings.appIconBadge.mode"

  /// Off by default — a Home Screen number is opt-in.
  static var isEnabled: Bool {
    UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? false
  }

  static var mode: Mode {
    guard let raw = UserDefaults.standard.string(forKey: modeKey),
          let value = Mode(rawValue: raw) else {
      return .unwatchedEpisodes
    }
    return value
  }

  enum Mode: String, CaseIterable, Identifiable {
    case unwatchedEpisodes
    case showsWithNewEpisodes

    var id: String { rawValue }

    var titleKey: String {
      switch self {
      case .unwatchedEpisodes: return "Unwatched episodes"
      case .showsWithNewEpisodes: return "Shows with new episodes"
      }
    }
  }
}

/// Pushes the Home Screen / Dock badge from the watching-serials list.
@MainActor
enum AppIconBadgeController {
  static func apply(serials: [WatchingItem]) {
    guard AppIconBadgePreferences.isEnabled else {
      clear()
      return
    }
    let count: Int
    switch AppIconBadgePreferences.mode {
    case .unwatchedEpisodes:
      // Same total as the Watchlist tab / New Episodes subtitle (`unwatchedCount`).
      count = serials.unwatchedEpisodeTotal
    case .showsWithNewEpisodes:
      count = serials.filter { ($0.unwatchedCount ?? 0) > 0 }.count
    }
    setBadge(count)
  }

  static func refreshFromPreferences() {
    // Preferences changed in Settings — clear immediately when Off; On waits for
    // the next watching-list refresh (TabsNavigationView) which carries the count.
    if !AppIconBadgePreferences.isEnabled {
      clear()
    }
  }

  static func requestAuthorizationIfNeeded() {
#if canImport(UserNotifications)
    UNUserNotificationCenter.current().getNotificationSettings { settings in
      guard settings.authorizationStatus == .notDetermined else { return }
      UNUserNotificationCenter.current().requestAuthorization(options: [.badge]) { _, _ in }
    }
#endif
  }

  private static func clear() {
    setBadge(0)
  }

  private static func setBadge(_ count: Int) {
#if canImport(UserNotifications)
    if #available(iOS 16.0, macOS 13.0, *) {
      UNUserNotificationCenter.current().setBadgeCount(count) { _ in }
      return
    }
#endif
#if canImport(UIKit)
    UIApplication.shared.applicationIconBadgeNumber = count
#endif
  }
}
