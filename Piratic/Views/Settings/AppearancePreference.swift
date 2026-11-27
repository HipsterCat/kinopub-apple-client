//
//  AppearancePreference.swift
//  Piratic
//
//  Settings › Appearance › Theme. Default System; Light / Dark override the
//  window. DEBUG `-PIRATICForceColorScheme` still wins at launch.
//

import SwiftUI

/// App-wide light / dark choice. Stored as a string in UserDefaults so
/// `@AppStorage`, tvOS TVSettingKit bindings, and the root color-scheme
/// modifier share one key.
enum AppearancePreference: String, CaseIterable, Identifiable, Sendable {
  case system
  case light
  case dark

  static let storageKey = "appearancePreference"

  var id: String { rawValue }

  var titleKey: LocalizedStringKey {
    switch self {
    case .system: return "System"
    case .light: return "Light"
    case .dark: return "Dark"
    }
  }

  /// Localized label for non-SwiftUI chrome (TVSettingKit formatters).
  var localizedTitle: String {
    switch self {
    case .system: return String(localized: "System")
    case .light: return String(localized: "Light")
    case .dark: return String(localized: "Dark")
    }
  }

  /// `nil` means follow the system — and means **omit** `.preferredColorScheme`
  /// entirely (passing `nil` still pinned Dark on tvOS).
  var preferredColorScheme: ColorScheme? {
    switch self {
    case .system: return nil
    case .light: return .light
    case .dark: return .dark
    }
  }

  static var current: AppearancePreference {
    let raw = UserDefaults.standard.string(forKey: storageKey) ?? system.rawValue
    return AppearancePreference(rawValue: raw) ?? .system
  }
}

extension View {
  /// Applies the user's Appearance preference, after DEBUG launch force.
  func piraticAppearancePreference() -> some View {
    modifier(PiraticAppearancePreferenceModifier())
  }
}

private struct PiraticAppearancePreferenceModifier: ViewModifier {
  @AppStorage(AppearancePreference.storageKey)
  private var rawValue = AppearancePreference.system.rawValue

  func body(content: Content) -> some View {
#if DEBUG
    if let forced = LaunchAppearance.forcedColorScheme {
      content.preferredColorScheme(forced)
    } else {
      apply(content)
    }
#else
    apply(content)
#endif
  }

  @ViewBuilder
  private func apply(_ content: Content) -> some View {
    let preference = AppearancePreference(rawValue: rawValue) ?? .system
    if let scheme = preference.preferredColorScheme {
      content.preferredColorScheme(scheme)
    } else {
      content
    }
  }
}
