//
//  GeneralSettingsPane.swift
//  KinoPubAppleClient
//

import SwiftUI

#if !os(tvOS)
struct GeneralSettingsPane: View {
  let model: ProfileModel
  @Binding var showLogoutAlert: Bool
  @AppStorage("selectedLanguage") private var selectedLanguage: String = (
    Locale.current.language.languageCode?.identifier ?? "en"
  )
#if os(macOS)
  @Environment(WindowSettings.self) private var windowSettings
#endif

  var body: some View {
#if os(macOS)
    macBody
#else
    iosBody
#endif
  }

#if os(macOS)
  private var macBody: some View {
    @Bindable var windowSettings = windowSettings
    // The account and Logout are the profile row's page (`AccountSettingsPane`).
    return Form {
      Section {
        LabeledContent("App version", value: Bundle.main.appVersionLong)
      }
      languageSection
      Section("Window") {
        Toggle("AlwaysOnTop", isOn: $windowSettings.alwaysOnTop)
      }
    }
    .formStyle(.grouped)
  }
#endif

#if os(iOS)
  private var iosBody: some View {
    Form {
      accountAndLanguageSections
      Section {
        Button("Logout", role: .destructive) {
          showLogoutAlert = true
        }
      }
    }
  }
#endif

  @ViewBuilder
  private var accountAndLanguageSections: some View {
    Section {
      LabeledContent("User Name", value: model.userData.username)
      LabeledContent("User Subscription", value: "\(model.userData.subscription.days) \("days".localized)")
      LabeledContent("Registration Date", value: model.userData.registrationDateFormatted)
      LabeledContent("App version", value: Bundle.main.appVersionLong)
    }
    languageSection
  }

  private var languageSection: some View {
    Section("Language") {
      Picker("Select Language", selection: $selectedLanguage) {
        ForEach(model.availableLanguages.keys.sorted(), id: \.self) { key in
          Text(model.availableLanguages[key] ?? key).tag(key)
        }
      }
      .pickerStyle(.menu)
      .onChange(of: selectedLanguage) { _, newLanguage in
        model.changeLanguage(to: newLanguage)
      }
    }
  }
}
#endif

#if os(macOS)
/// The page of the profile row at the top of the Settings sidebar: who is signed in, and
/// Logout — as System Settings' account row opens the account's page.
struct AccountSettingsPane: View {
  let model: ProfileModel
  @Binding var showLogoutAlert: Bool

  var body: some View {
    VStack(spacing: 0) {
      Form {
        Section {
          LabeledContent("User Name", value: model.userData.username)
          LabeledContent("User Subscription", value: "\(model.userData.subscription.days) \("days".localized)")
          LabeledContent("Registration Date", value: model.userData.registrationDateFormatted)
        }
      }
      .formStyle(.grouped)

      // macOS Control Center–style pill — not a Form row.
      HStack {
        Button("Logout…") {
          showLogoutAlert = true
        }
        .buttonStyle(.bordered)
        Spacer(minLength: 0)
      }
      .padding(.horizontal, 20)
      .padding(.bottom, 16)
    }
  }
}
#endif
