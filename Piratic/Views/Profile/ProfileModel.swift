//
//  SettingsModel.swift
//  Piratic
//
//  Created by Kirill Kunst on 9.08.2023.
//

import Foundation
import KinoPubBackend
import PiraticLogging
import PiraticMedia
import OSLog

@MainActor
@Observable
class ProfileModel {

    private var userService: UserService
    private var errorHandler: ErrorHandler
    private var authState: AuthState

    /// The shared profile (`UserProfileStore`): the cached copy until a fresh one lands.
    public var userData: UserData { UserProfileStore.shared.user ?? .placeholder }
    var selectedLanguage: String

    // LT is not shipping yet — no translations exist for it, so offering it here would
    // just fall back to English everywhere.
    let availableLanguages = ["en": "English", "ru": "Русский"]
    
    init(userService: UserService,
         errorHandler: ErrorHandler,
         authState: AuthState) {
        self.userService = userService
        self.errorHandler = errorHandler
        self.authState = authState
        self.selectedLanguage = AppLanguage.resolvedStoredCode()
    }
    /// Refreshes the profile only when the cached copy is stale (`UserProfileStore`).
    /// A failure is not shown: the screen keeps the copy it has, and nothing retries
    /// until `UserProfileStore.retryAfterFailure` has passed.
    func fetch() {
        Task {
            guard let user = await UserProfileStore.shared.refreshIfStale(using: userService) else { return }
            authState.rememberSignedInUsername(user.username)
        }
    }
    
    func logout() {
        authState.logout()
    }
    
    /// Soft-remounts the shell under a blocking loader (`AppLanguage.apply`).
    func changeLanguage(to language: String) {
        selectedLanguage = language
        Task { await AppLanguage.shared.apply(language) }
    }
}

extension UserData.Subscription {
  /// When it ends, and how much is left: "Подписка до 12 дек. 2026 · ещё 32 дня". The
  /// bare "32.1 days" said neither (Sasha, 2026-11-10).
  var summary: String {
    // Nothing loaded yet: no line rather than a wrong one.
    guard let end = endDate else { return "" }
    guard end > Date() else { return "Profile_SubscriptionEnded".localized }
    return String(format: "Profile_SubscriptionUntil %@".localized,
                  end.formattedForDisplay(.init(date: .abbreviated, time: .omitted, locale: AppLanguage.lookupLocale))) + " · " + daysLeft
  }

  /// The value beside "User Subscription": "до 12 дек. 2026 (ещё 32 дня)".
  var settingsValue: String {
    // Nothing loaded yet: no line rather than a wrong one.
    guard let end = endDate else { return "" }
    guard end > Date() else { return "Profile_SubscriptionEnded".localized }
    return String(format: "Profile_SubscriptionUntilShort %@".localized,
                  end.formattedForDisplay(.init(date: .abbreviated, time: .omitted, locale: AppLanguage.lookupLocale))) + " (" + daysLeft + ")"
  }

  private var endDate: Date? {
    endTime > 0 ? Date(timeIntervalSince1970: endTime) : nil
  }

  private var daysLeft: String {
    String.localizedStringWithFormat("Profile_DaysLeft %lld".localized, Int64(max(0, days.rounded(.down))))
  }
}

extension UserData.Profile {
  /// The avatar's address, with Gravatar asked for a 404 instead of the generated picture
  /// it draws for an address with no avatar (the blue power mark): the app shows a
  /// person glyph then, as Apple's own account rows do (Sasha, 2026-11-10).
  var avatarURL: URL? {
    guard let raw = avatar?.trimmingCharacters(in: .whitespaces), !raw.isEmpty,
          var components = URLComponents(string: raw.hasPrefix("//") ? "https:" + raw : raw)
    else { return nil }
    if components.host?.hasSuffix("gravatar.com") == true {
      var items = (components.queryItems ?? []).filter { $0.name != "d" && $0.name != "default" }
      items.append(URLQueryItem(name: "d", value: "404"))
      components.queryItems = items
    }
    return components.url
  }
}
