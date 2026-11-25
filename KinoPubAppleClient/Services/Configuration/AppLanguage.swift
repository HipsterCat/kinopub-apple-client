//
//  AppLanguage.swift
//  KinoPubAppleClient
//
//  In-app interface language without quitting. Foundation still pins
//  `Bundle.main.preferredLocalizations` for the process, so we own the locale
//  explicitly: SwiftUI `\.locale`, `String.localized`, artwork Accept-Language,
//  and a soft remount via `ShellRemount`.
//

import Foundation
import KinoPubUI

/// The viewer's interface language (`en` / `ru`), stored under `selectedLanguage`.
@MainActor
@Observable
final class AppLanguage {
  static let shared = AppLanguage()
  /// UserDefaults key — readable from nonisolated `.localized` / package helpers.
  nonisolated static let storageKey = "selectedLanguage"

  /// Codes the Settings picker offers (`ProfileModel.availableLanguages`).
  nonisolated static let supportedCodes: Set<String> = ["en", "ru"]

  private(set) var code: String

  var locale: Locale { Self.locale(for: code) }

  /// Locale for string lookup off the main actor (`.localized`).
  nonisolated static var lookupLocale: Locale {
    locale(for: resolvedStoredCode())
  }

  private init() {
    code = Self.resolvedStoredCode()
    // Cold launch and anything still reading AppleLanguages stay aligned.
    UserDefaults.standard.set([code], forKey: "AppleLanguages")
  }

  nonisolated static func resolvedStoredCode() -> String {
    let raw = UserDefaults.standard.string(forKey: storageKey)
      ?? Locale.current.language.languageCode?.identifier
      ?? "en"
    let code = Locale(identifier: raw).language.languageCode?.identifier ?? raw
    if supportedCodes.contains(code) { return code }
    return code.hasPrefix("ru") ? "ru" : "en"
  }

  nonisolated static func locale(for code: String) -> Locale {
    Locale(identifier: code == "ru" ? "ru_RU" : "en_US")
  }

  /// Persist, flush language-sensitive caches, remount the shell.
  func apply(_ newCode: String) async {
    let normalized = Locale(identifier: newCode).language.languageCode?.identifier ?? newCode
    let code = Self.supportedCodes.contains(normalized)
      ? normalized
      : (normalized.hasPrefix("ru") ? "ru" : "en")
    guard code != self.code || UserDefaults.standard.string(forKey: Self.storageKey) != code else {
      return
    }

    await ShellRemount.shared.run {
      UserDefaults.standard.set(code, forKey: Self.storageKey)
      UserDefaults.standard.set([code], forKey: "AppleLanguages")
      self.code = code
      Artwork.clearCaches()
    }
  }
}
