//
//  String+Localization.swift
//  KinoPubAppleClient
//
//  Created by Kirill Kunst on 2.08.2023.
//

import Foundation

extension String {
  /// Looks up this key in the app's interface language (`selectedLanguage`), not the
  /// process/`Locale.current` pin that only refreshes after a cold launch.
  var localized: String {
    String(
      localized: String.LocalizationValue(self),
      locale: AppLanguage.lookupLocale
    )
  }
}
