//
//  AboutView.swift
//  KinoPubAppleClient
//
//  About on iOS, iPadOS and macOS (tvOS draws the same rows in TVSettingKit,
//  `TVSettingsCatalog.aboutSections`): the version as plain text, What's New and the
//  licences in the shared info popup.
//

import SwiftUI
import KinoPubUI

struct AboutView: View {
  @AppStorage("selectedLanguage") private var selectedLanguage: String = (
    Locale.current.language.languageCode?.identifier ?? "ru"
  )
  @State private var showsHistory = false
  @State private var showsLicenses = false

  var body: some View {
    List {
      Section {
        VStack(spacing: 12) {
          Image(systemName: "play.rectangle.fill")
            .font(.title)
            .foregroundStyle(.secondary)

          Text(Bundle.main.displayName)
            .font(.title3.weight(.semibold))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
      }

      Section {
        LabeledContent("Version") {
          Text(verbatim: "\(Bundle.main.appVersionLong) (\(Bundle.main.appBuild))")
#if !os(tvOS)
            .textSelection(.enabled)
#endif
        }
        Button("What's new") { showsHistory = true }
          .infoPopup(Text("What's new"), isPresented: $showsHistory) {
            ChangelogHistory(languageCode: selectedLanguage)
          }
        Button("Licenses") { showsLicenses = true }
          .infoPopup(Text("Licenses"), isPresented: $showsLicenses) {
            OpenSourceLicensesView()
          }
      }

      Section {
        DataSourcesAttributionView()
      }
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
