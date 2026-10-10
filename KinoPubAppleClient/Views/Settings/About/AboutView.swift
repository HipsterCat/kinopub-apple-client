//
//  AboutView.swift
//  KinoPubAppleClient
//

import SwiftUI
import KinoPubUI

struct AboutView: View {
  @AppStorage("selectedLanguage") private var selectedLanguage: String = (
    Locale.current.language.languageCode?.identifier ?? "ru"
  )

  var body: some View {
    List {
      Section {
        VStack(spacing: 12) {
          Image(systemName: "play.rectangle.fill")
            .font(.title)
            .foregroundStyle(.secondary)

          Text(Bundle.main.displayName)
            .font(.title3.weight(.semibold))

          Text(String(format: "Version %@ • Build %@".localized,
                      Bundle.main.appVersionLong, Bundle.main.appBuild))
            .font(TypeScale.heroSecondary)
            .foregroundStyle(.secondary)
#if !os(tvOS)
            .textSelection(.enabled)
#endif
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)

        DataSourcesAttributionView()
      }

      ChangelogHistoryView(languageCode: selectedLanguage)
    }
    .platformNavigationTitle("About")
  }
}

private extension Bundle {
  var displayName: String {
    object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
      ?? object(forInfoDictionaryKey: "CFBundleName") as? String
      ?? "Kinopub Soda"
  }
}
