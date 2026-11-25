//
//  AppLanguage.swift
//  KinoPubAppleClient
//
//  In-app interface language without quitting. Foundation still pins
//  `Bundle.main.preferredLocalizations` for the process, so we own the locale
//  explicitly: SwiftUI `\ .locale`, `String.localized`, artwork Accept-Language,
//  and a soft remount of the root scene under a blocking loader.
//

import Foundation
import SwiftUI
import KinoPubUI

/// The viewer's interface language (`en` / `ru`), stored under `selectedLanguage`.
@MainActor
@Observable
final class AppLanguage {
  static let shared = AppLanguage()
  static let storageKey = "selectedLanguage"

  /// Codes the Settings picker offers (`ProfileModel.availableLanguages`).
  nonisolated static let supportedCodes: Set<String> = ["en", "ru"]

  /// Bumped after a language change so `RootView` is recreated (stacks, TVUIKit hosts).
  private(set) var remountID = UUID()

  /// Full-screen blocking loader while the remount runs.
  private(set) var isApplying = false

  private(set) var code: String

  /// Attached from the app scene — lives for the process.
  weak var navigation: NavigationState?

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

  /// Persist, flush language-sensitive caches, clear navigation stacks, remount the shell.
  func apply(_ newCode: String) async {
    let normalized = Locale(identifier: newCode).language.languageCode?.identifier ?? newCode
    let code = Self.supportedCodes.contains(normalized)
      ? normalized
      : (normalized.hasPrefix("ru") ? "ru" : "en")
    guard code != self.code || UserDefaults.standard.string(forKey: Self.storageKey) != code else {
      return
    }
    guard !isApplying else { return }

    isApplying = true
    // Let the blocking overlay paint before we tear the tree down.
    await Task.yield()
    try? await Task.sleep(for: .milliseconds(120))

    UserDefaults.standard.set(code, forKey: Self.storageKey)
    UserDefaults.standard.set([code], forKey: "AppleLanguages")
    self.code = code

    navigation?.clearStacksForLanguageRemount()
    Artwork.clearCaches()

    // Recreate the SwiftUI / TVUIKit shell under the loader.
    remountID = UUID()
    try? await Task.sleep(for: .milliseconds(280))
    isApplying = false
  }
}

extension View {
  /// Pins the interface locale and remounts the root when the language changes.
  func kinopubAppLanguage(_ language: AppLanguage) -> some View {
    modifier(KinopubAppLanguageModifier(language: language))
  }
}

private struct KinopubAppLanguageModifier: ViewModifier {
  @Bindable var language: AppLanguage

  func body(content: Content) -> some View {
    ZStack {
      content
        .environment(\.locale, language.locale)
        .id(language.remountID)
        .allowsHitTesting(!language.isApplying)

      if language.isApplying {
        LanguageApplyingOverlay()
          .transition(.opacity)
      }
    }
    .animation(.easeOut(duration: 0.2), value: language.isApplying)
  }
}

/// System-style freeze: dimmed veil + spinner. No custom chrome beyond ProgressView.
private struct LanguageApplyingOverlay: View {
  var body: some View {
    ZStack {
      Color.black.opacity(0.45)
        .ignoresSafeArea()
      ProgressView()
        .controlSize(.large)
#if os(tvOS)
        .tint(.white)
#endif
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(Text("Loading"))
  }
}
