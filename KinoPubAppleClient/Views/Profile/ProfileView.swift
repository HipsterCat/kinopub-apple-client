//
//  SettingsView.swift
//  KinoPubAppleClient
//
//  Created by Kirill Kunst on 22.07.2023.
//
import SwiftUI
import KinoPubBackend
import KinoPubKit

struct ProfileView: View {

  @Environment(NavigationState.self) var navigationState
  @Environment(ErrorHandler.self) var errorHandler
  @Environment(\.appContext) var appContext
  // Eager, not lazy: `ProfileModel.init` only stores references and reads
  // `UserDefaults` synchronously — no Task, no network call — so re-evaluating it on
  // every `ProfileView.init` (and discarding the extra instances `@State` doesn't use)
  // costs nothing worth guarding against. See ROADMAP.md
  // "Observation model" for the general rule this follows.
  @State private var model: ProfileModel

  init(model: ProfileModel) {
    _model = State(wrappedValue: model)
  }

  var body: some View {
#if os(tvOS)
    TVProfileSettingsHost(model: model)
#else
    NavigationStack {
      SettingsRootView(model: model)
        .background(Color.KinoPub.background)
    }
    .navigationStackActive(for: .settings, selected: navigationState.selectedTab)
#endif
  }
}

#if os(tvOS)
/// Keeps tvOS bindings and alerts next to whichever tvOS Settings this OS can show.
private struct TVProfileSettingsHost: View {
  @Bindable var model: ProfileModel
  @Environment(\.appContext) private var appContext
  @AppStorage("selectedLanguage") private var selectedLanguage: String = (
    Locale.current.language.languageCode?.identifier ?? "en"
  )
  @AppStorage(SubtitlePreferences.preferEnglishKey) private var preferEnglishSubtitles = true
  @AppStorage(SubtitlePreferences.preferNonCCKey) private var preferNonCCSubtitles = true
  @AppStorage(SubtitlePreferences.dualSubtitlesKey) private var dualSubtitlesEnabled = false
  @AppStorage(SubtitlePreferences.secondSubtitleLanguageKey) private var secondSubtitleLanguage = "ru"
  @AppStorage(StreamQuality.userDefaultsKey) private var streamQualityRaw = StreamQuality.auto.rawValue
  @State private var showLogoutAlert = false

  var body: some View {
    settings
    .background(Color.KinoPub.background.ignoresSafeArea())
    .onAppear { model.fetch() }
    .alert("Are you sure?", isPresented: $showLogoutAlert) {
      Button("Logout", role: .destructive) { model.logout() }
      Button("Cancel", role: .cancel) { }
    }
    .alert(isPresented: $model.shouldShowExitAlert) {
      Alert(
        title: Text("Restarting the app"),
        message: Text("The app will restart to apply the language change."),
        primaryButton: .default(Text("OK")) { exit(0) },
        secondaryButton: .cancel()
      )
    }
  }

  /// Apple's own Settings machinery when this tvOS has it (`TVSettingKit.swift`); the
  /// SwiftUI Settings otherwise.
  @ViewBuilder
  private var settings: some View {
    if TVSettingKit.isAvailable && !Self.forcesSwiftUISettings {
      TVSettingKitSettingsView(
        model: model,
        kinopoiskKeyProvider: appContext.kinopoiskKeyProvider,
        onLogout: { showLogoutAlert = true },
        onLanguageChange: { model.changeLanguage(to: $0) }
      )
    } else {
      fallbackSettings
    }
  }

  /// DEBUG `-KINOPUBSwiftUISettings YES` shows the fallback, which otherwise never appears
  /// while TVSettingKit exists.
  private static var forcesSwiftUISettings: Bool {
#if DEBUG
    UserDefaults.standard.bool(forKey: "KINOPUBSwiftUISettings")
#else
    false
#endif
  }

  private var fallbackSettings: some View {
    TVProfileSettingsView(
      model: model,
      kinopoiskKeyProvider: appContext.kinopoiskKeyProvider,
      selectedLanguage: $selectedLanguage,
      preferEnglishSubtitles: $preferEnglishSubtitles,
      preferNonCCSubtitles: $preferNonCCSubtitles,
      dualSubtitlesEnabled: $dualSubtitlesEnabled,
      secondSubtitleLanguage: $secondSubtitleLanguage,
      streamQualityRaw: $streamQualityRaw,
      onLogout: { showLogoutAlert = true },
      onLanguageChange: { model.changeLanguage(to: $0) }
    )
  }
}
#endif

struct ProfileView_Previews: PreviewProvider {
  static var previews: some View {
    ProfileView(model: ProfileModel(userService: UserServiceMock(),
                                    errorHandler: ErrorHandler(),
                                    authState: AuthState(authService: AuthorizationServiceMock(),
                                                         accessTokenService: AccessTokenServiceMock())))
  }
}
