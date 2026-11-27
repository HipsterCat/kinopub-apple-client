//
//  SettingsDetailRoute.swift
//  Piratic
//

import Foundation

#if !os(tvOS)
/// Nested Settings destinations pushed inside a category’s detail stack.
enum SettingsDetailRoute: Hashable {
  case devicesList
  case storage
  case sections
  /// Not DEBUG-only on purpose: the launches worth reading a log for happen on a real
  /// Apple TV running a TestFlight build, with no Xcode attached.
  case networkLog
  /// Every `FeatureFlag`, switchable — in TestFlight builds too, which is where a flag
  /// gets judged on a real screen.
  case featureFlags
  /// Settings › Integrations › one source.
  case integration(Integration)
  /// Settings › Details › Items › one enrichment surface.
  case detailsItem(DetailsEnrichmentItem)
  /// Settings › Details › Info › Age rating badge (upper info strip prefs).
  case titleInfoStrip
  /// Playback › the ordered audio or subtitle languages.
  case languageList(PlaybackLanguageList.Kind)
#if DEBUG
  case streamSurvey
  /// Opens the in-process UI lab (iOS). macOS uses `openWindow` instead.
  case uiLab(UILabChrome)
  case typeStyles
  case libraryLab
  case playerCases
#endif
}
#endif
