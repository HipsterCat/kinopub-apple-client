//
//  TVProfileSettingsView.swift
//  KinoPubAppleClient
//
//  The SwiftUI fallback for tvOS Settings, shown only when TVSettingKit is missing on this
//  OS (`TVSettingKit.swift`, `TVSettingsCatalog.swift` are the real thing). Same categories
//  and rows; a plain `NavigationStack`, so pages crossfade.
//
//  Persistent left panel, right list of pill rows. With nothing in the list focused the
//  left panel is the app itself; a focused category shows its icon and tip. Pushed pages
//  draw their title in the tab bar's band and hide the tab bar.
//
//  Every row is focusable, read-only ones included — on a remote, what focus cannot reach
//  cannot be read, and a page with nothing focusable is a dead end.
//
//  Every page is in every build, developer tools included: the builds worth looking at
//  are TestFlight ones on a real Apple TV, with no Xcode attached.
//

#if os(tvOS)
import SwiftUI
import KinoPubBackend
import KinoPubUI

struct TVProfileSettingsView: View {

  let model: ProfileModel
  let kinopoiskKeyProvider: KinopoiskKeyProvider
  @Binding var selectedLanguage: String
  @Binding var preferEnglishSubtitles: Bool
  @Binding var preferNonCCSubtitles: Bool
  @Binding var dualSubtitlesEnabled: Bool
  @Binding var secondSubtitleLanguage: String
  @Binding var streamQualityRaw: String
  var onLogout: () -> Void
  var onLanguageChange: (String) -> Void

  @Environment(\.appContext) private var appContext
  @Environment(ErrorHandler.self) private var errorHandler
  // Forwarded to every pushed page: UIKit-hosted pages do not inherit the environment.
  /// kino.pub's per-device streaming profile — shared by Server & connection and Device,
  /// loaded the first time either is opened.
  @StateObject private var device = DeviceSettingsPaneModel()
  @State private var path = NavigationPath()
  @AppStorage(DiagnosticsSettings.remoteLoggingKey) private var streamsToPulse = false
  @AppStorage(DiagnosticsSettings.activityOverlayKey) private var showsActivityOverlay = false

  var body: some View {
    NavigationStack(path: $path) {
      TVSettingsRootPage { path.append(SettingsRoute.category($0)) }
        .navigationDestination(for: SettingsRoute.self) { route in
          destination(for: route)
            .toolbar(.hidden, for: .tabBar)
        }
    }
    .toolbar(path.isEmpty ? .automatic : .hidden, for: .tabBar)
  }

  /// The left panel shifts sideways instead of crossfading.
  fileprivate static let panelTransition = AnyTransition.push(from: .trailing)

  // MARK: - Destinations

  @ViewBuilder
  private func destination(for route: SettingsRoute) -> some View {
    switch route {
    case .category(let category):
      categoryPage(category)
    case .language:
      SettingsChoiceView(
        title: "Language",
        pageSymbol: "globe",
        tipKey: "Settings_Tip_Language",
        options: model.availableLanguages.keys.sorted().map { key in
          SettingsChoiceOption(id: key, title: model.availableLanguages[key] ?? key)
        },
        selection: $selectedLanguage,
        onSelect: onLanguageChange
      )
    case .secondSubtitleLanguage:
      SettingsChoiceView(
        title: "Second subtitle language",
        pageSymbol: "character.bubble",
        tipKey: "Settings_Tip_SecondLanguage",
        options: SubtitlePreferences.secondLanguageOptions.map { code in
          SettingsChoiceOption(id: code, title: LanguageNames.name(for: code))
        },
        selection: $secondSubtitleLanguage
      )
    case .streamQuality:
      SettingsChoiceView(
        title: "Stream quality",
        pageSymbol: "gauge.with.dots.needle.33percent",
        tipKey: "Settings_Tip_StreamQuality",
        options: StreamQuality.allCases.map { quality in
          SettingsChoiceOption(id: quality.rawValue, title: quality.title)
        },
        selection: $streamQualityRaw
      )
    case .streamType:
      SettingsChoiceView(
        title: "Stream type",
        pageSymbol: TVSettingsCategory.server.symbol,
        tipKey: TVSettingsCategory.server.tipKey,
        options: device.settings.streamingTypeOptions.map { SettingsChoiceOption(id: String($0.id), title: $0.label) },
        selection: deviceChoice(\.streamingType)
      )
    case .serverLocation:
      SettingsChoiceView(
        title: "Server location",
        pageSymbol: TVSettingsCategory.server.symbol,
        tipKey: TVSettingsCategory.server.tipKey,
        options: device.settings.serverLocationOptions.map { SettingsChoiceOption(id: String($0.id), title: $0.label) },
        selection: deviceChoice(\.serverLocation)
      )
    case .rememberedTracks:
      TVRememberedTracksPage()
    case .releaseNotes:
      TVReleaseNotesPage()
    case .kinopoisk:
      TVKinopoiskKeyView(keyProvider: kinopoiskKeyProvider)
    case .networkLog:
      NetworkConsoleView()
    case .lab(let lab):
      lab.page
    }
  }

  @ViewBuilder
  private func categoryPage(_ category: TVSettingsCategory) -> some View {
    switch category {
    case .experiments:
      TVFeatureFlagsPage()
    default:
      SettingsCategoryPage(category: category) { focus in
        rows(for: category, focus: focus)
      }
      .task(id: category) {
        guard category.usesDeviceSettings else { return }
        await loadDeviceSettingsIfNeeded()
      }
    }
  }

  // MARK: - Category rows

  @ViewBuilder
  private func rows(for category: TVSettingsCategory,
                    focus: FocusState<SettingsFocusItem?>.Binding) -> some View {
    switch category {
    case .account:
      accountRows(focus: focus)
    case .server:
      serverRows(focus: focus)
    case .device:
      deviceRows(focus: focus)
    case .videoAudio:
      videoAudioRows(focus: focus)
    case .appearance:
      appearanceRows(focus: focus)
    case .dataSources:
      dataSourcesRows(focus: focus)
    case .advanced:
      advancedRows(focus: focus)
    case .developer:
      SettingsSection {
        ForEach(TVSettingsLab.allCases) { lab in
          navigationRow(lab.titleKey, route: .lab(lab), focus: focus, equals: .lab(lab))
        }
      }
    case .about:
      aboutRows(focus: focus)
    case .experiments:
      // Its own page — see `categoryPage(_:)`.
      EmptyView()
    }
  }

  @ViewBuilder
  private func accountRows(focus: FocusState<SettingsFocusItem?>.Binding) -> some View {
    SettingsSection {
      infoRow(label: "User Name", value: model.userData.username, focus: focus, id: "username")
      infoRow(
        label: "User Subscription",
        value: "\(model.userData.subscription.days) \("days".localized)",
        focus: focus,
        id: "subscription"
      )
      infoRow(label: "Registration Date",
              value: model.userData.registrationDateFormatted,
              focus: focus,
              id: "registration")
      Button(action: onLogout) {
        SettingsPillLabel(title: "Logout", isDestructive: true)
      }
      .buttonStyle(SettingsPillButtonStyle())
      .focused(focus, equals: .logout)
    }
  }

  @ViewBuilder
  private func serverRows(focus: FocusState<SettingsFocusItem?>.Binding) -> some View {
    deviceSettingsGate(focus: focus) {
      SettingsSection {
        navigationRow(
          "Stream type",
          value: label(of: device.settings.streamingType, in: device.settings.streamingTypeOptions),
          route: .streamType,
          focus: focus,
          equals: .streamType
        )
        navigationRow(
          "Server location",
          value: label(of: device.settings.serverLocation, in: device.settings.serverLocationOptions),
          route: .serverLocation,
          focus: focus,
          equals: .serverLocation
        )
        deviceSaveFootnote
      }
    }
  }

  @ViewBuilder
  private func deviceRows(focus: FocusState<SettingsFocusItem?>.Binding) -> some View {
    deviceSettingsGate(focus: focus) {
      SettingsSection {
        if !device.deviceTitle.isEmpty {
          infoRow(label: "This device", value: device.deviceTitle, focus: focus, id: "thisDevice")
        }
        toggleRow(title: "4K", isOn: deviceToggle(\.support4k), focus: focus, equals: .capability("4k"))
        toggleRow(title: "HEVC", isOn: deviceToggle(\.supportHevc), focus: focus, equals: .capability("hevc"))
        toggleRow(title: "HDR", isOn: deviceToggle(\.supportHdr), focus: focus, equals: .capability("hdr"))
        toggleRow(title: "Mixed playlists",
                  isOn: deviceToggle(\.mixedPlaylist),
                  focus: focus,
                  equals: .capability("mixedPlaylist"))
        deviceSaveFootnote
      }
    }
  }

  @ViewBuilder
  private func videoAudioRows(focus: FocusState<SettingsFocusItem?>.Binding) -> some View {
    SettingsSection {
      navigationRow(
        "Stream quality",
        value: (StreamQuality(rawValue: streamQualityRaw) ?? .auto).title,
        route: .streamQuality,
        focus: focus,
        equals: .streamQuality
      )
      navigationRow("Remembered tracks", route: .rememberedTracks, focus: focus, equals: .rememberedTracks)
    }

    SettingsSection("Subtitles") {
      toggleRow(
        title: "Default English subtitles",
        isOn: $preferEnglishSubtitles,
        focus: focus,
        equals: .englishSubs
      )

      toggleRow(
        title: "Prefer non-CC / non-SDH",
        isOn: $preferNonCCSubtitles,
        focus: focus,
        equals: .nonCC
      )
      .disabled(!preferEnglishSubtitles)

      // The dual-subtitle stage's rows — parked with the sidecar machinery they feed.
      if FeatureFlags.tvOSSidecarSubtitles {
        toggleRow(
          title: "Dual subtitles",
          isOn: $dualSubtitlesEnabled,
          focus: focus,
          equals: .dual
        )

        navigationRow(
          "Second subtitle language",
          value: LanguageNames.name(for: secondSubtitleLanguage),
          route: .secondSubtitleLanguage,
          focus: focus,
          equals: .secondLang
        )
        .disabled(!dualSubtitlesEnabled)
      }
    }
  }

  @ViewBuilder
  private func appearanceRows(focus: FocusState<SettingsFocusItem?>.Binding) -> some View {
    SettingsSection {
      navigationRow(
        "Language",
        value: model.availableLanguages[selectedLanguage] ?? selectedLanguage,
        route: .language,
        focus: focus,
        equals: .language
      )
      infoRow(label: "Theme", value: "Dark".localized, focus: focus, id: "theme")
    }
  }

  @ViewBuilder
  private func dataSourcesRows(focus: FocusState<SettingsFocusItem?>.Binding) -> some View {
    SettingsSection("Kinopoisk") {
      navigationRow("API key", route: .kinopoisk, focus: focus, equals: .kinopoisk)
    }
    // Each source is a row; what it supplies is the row's tip on the left.
    SettingsSection("Sources") {
      ForEach(TVDataSource.current) { source in
        infoRow(label: source.titleKey, value: source.host, focus: focus, item: .source(source))
      }
      Text("This product uses the TMDB API but is not endorsed or certified by TMDB.")
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, Metrics.pillHorizontalPadding)
        .padding(.top, 4)
    }
  }

  @ViewBuilder
  private func advancedRows(focus: FocusState<SettingsFocusItem?>.Binding) -> some View {
    // Not DEBUG-only: this is the platform the slow launches happen on, and the builds
    // they happen in are TestFlight ones with no Xcode attached.
    SettingsSection("Diagnostics") {
      navigationRow("Network log", route: .networkLog, focus: focus, equals: .networkLog)
      // Reading a log on a television with a remote is nobody's idea of a good time;
      // this is the row that moves it to a Mac.
      Button {
        streamsToPulse.toggle()
        NetworkDiagnostics.setRemoteLoggingEnabled(streamsToPulse)
      } label: {
        SettingsPillLabel(title: "Stream to Pulse on Mac", showsCheckmark: streamsToPulse)
      }
      .buttonStyle(SettingsPillButtonStyle())
      .focused(focus, equals: .streamToPulse)
      toggleRow(
        title: "Show in-flight requests",
        isOn: $showsActivityOverlay,
        focus: focus,
        equals: .activityOverlay
      )
    }
  }

  @ViewBuilder
  private func aboutRows(focus: FocusState<SettingsFocusItem?>.Binding) -> some View {
    SettingsSection {
      infoRow(label: "Version", value: Bundle.main.appVersionLong, focus: focus, id: "version")
      infoRow(label: "Build", value: Bundle.main.appBuild, focus: focus, id: "build")
      navigationRow("What's new", route: .releaseNotes, focus: focus, equals: .releaseNotes)
    }
  }

  // MARK: - Device settings

  /// Shows `content` once kino.pub has answered. Until then a spinner, and after a failed
  /// load a Retry pill — a page with nothing focusable is a dead end on a remote.
  @ViewBuilder
  private func deviceSettingsGate<Content: View>(
    focus: FocusState<SettingsFocusItem?>.Binding,
    @ViewBuilder content: () -> Content
  ) -> some View {
    if !device.settings.streamingTypeOptions.isEmpty {
      content()
    } else if device.isLoading {
      ProgressView()
        .frame(maxWidth: .infinity)
        .padding(.vertical, Metrics.pillVerticalPadding)
    } else {
      SettingsSection {
        Button {
          Task { await loadDeviceSettingsIfNeeded() }
        } label: {
          SettingsPillLabel(title: "Retry")
        }
        .buttonStyle(SettingsPillButtonStyle())
        .focused(focus, equals: .retry)
      }
    }
  }

  private var deviceSaveFootnote: some View {
    Text(device.didSave ? "Saved. Changes take effect within a minute." : "Changes take effect within a minute.")
      .font(.caption)
      .foregroundStyle(.secondary)
      .padding(.horizontal, Metrics.pillHorizontalPadding)
      .padding(.top, 4)
  }

  private func loadDeviceSettingsIfNeeded() async {
    guard device.settings.streamingTypeOptions.isEmpty, !device.isLoading else { return }
    await device.load(deviceService: appContext.deviceService, errorHandler: errorHandler)
  }

  /// There is no Save button on a remote: every change is sent as it is made.
  private func saveDeviceSettings() {
    Task { await device.save(deviceService: appContext.deviceService, errorHandler: errorHandler) }
  }

  private func deviceToggle(_ keyPath: WritableKeyPath<DeviceSettings, Bool>) -> Binding<Bool> {
    Binding(
      get: { device.settings[keyPath: keyPath] },
      set: { newValue in
        device.settings[keyPath: keyPath] = newValue
        saveDeviceSettings()
      }
    )
  }

  /// `SettingsChoiceView` speaks string ids; kino.pub's options are numbered.
  private func deviceChoice(_ keyPath: WritableKeyPath<DeviceSettings, Int>) -> Binding<String> {
    Binding(
      get: { String(device.settings[keyPath: keyPath]) },
      set: { newValue in
        guard let id = Int(newValue), id != device.settings[keyPath: keyPath] else { return }
        device.settings[keyPath: keyPath] = id
        saveDeviceSettings()
      }
    )
  }

  private func label(of id: Int, in options: [DeviceSettingOption]) -> String? {
    options.first { $0.id == id }?.label
  }

  // MARK: - Row helpers

  private func navigationRow(_ title: LocalizedStringKey,
                             value: String? = nil,
                             route: SettingsRoute,
                             focus: FocusState<SettingsFocusItem?>.Binding,
                             equals item: SettingsFocusItem) -> some View {
    Button {
      path.append(route)
    } label: {
      SettingsPillLabel(title: title, value: value, showsChevron: true)
    }
    .buttonStyle(SettingsPillButtonStyle())
    .focused(focus, equals: item)
  }

  private func infoRow(label: LocalizedStringKey,
                       value: String,
                       focus: FocusState<SettingsFocusItem?>.Binding,
                       id: String) -> some View {
    infoRow(label: label, value: value, focus: focus, item: .info(id))
  }

  private func infoRow(label: LocalizedStringKey,
                       value: String,
                       focus: FocusState<SettingsFocusItem?>.Binding,
                       item: SettingsFocusItem) -> some View {
    SettingsInfoRow(title: label, value: value)
      .focused(focus, equals: item)
  }

  private func toggleRow(
    title: LocalizedStringKey,
    isOn: Binding<Bool>,
    focus: FocusState<SettingsFocusItem?>.Binding,
    equals item: SettingsFocusItem
  ) -> some View {
    Button {
      isOn.wrappedValue.toggle()
    } label: {
      SettingsPillLabel(
        title: title,
        value: isOn.wrappedValue ? "On".localized : "Off".localized
      )
    }
    .buttonStyle(SettingsPillButtonStyle())
    .focused(focus, equals: item)
  }
}

// MARK: - Root

/// The category list. Its own view, so its focus state lives in the page that is hosted.
private struct TVSettingsRootPage: View {
  let onSelect: (TVSettingsCategory) -> Void

  @FocusState private var focusedCategory: TVSettingsCategory?

  var body: some View {
    SettingsSplitLayout(title: nil) {
      ZStack(alignment: .top) {
        if let focusedCategory {
          SettingsLeftPanel(symbol: focusedCategory.symbol, tipKey: focusedCategory.tipKey)
            .transition(TVProfileSettingsView.panelTransition)
        } else {
          SettingsAppInfoPanel()
            .transition(TVProfileSettingsView.panelTransition)
        }
      }
      .animation(.smooth(duration: 0.3), value: focusedCategory == nil)
    } content: {
      // One list, not one group per row: these are siblings.
      SettingsSection {
        ForEach(TVSettingsCategory.allCases) { category in
          Button {
            onSelect(category)
          } label: {
            SettingsPillLabel(title: category.titleKey, showsChevron: true)
          }
          .buttonStyle(SettingsPillButtonStyle())
          .focused($focusedCategory, equals: category)
        }
      }
    }
    .defaultFocus($focusedCategory, .account)
  }
}

// MARK: - Categories

/// tvOS's own catalogue: the iOS / macOS one (`SettingsCategory`) still carries demo panes
/// that have nothing behind them, and a TV page with nothing focusable on it is a trap.
private enum TVSettingsCategory: String, CaseIterable, Identifiable, Hashable {
  case account
  case server
  case device
  case videoAudio
  case appearance
  case dataSources
  case advanced
  case experiments
  case developer
  case about

  var id: String { rawValue }

  var titleKey: LocalizedStringKey {
    switch self {
    case .account: "Kinopub account"
    case .server: "Server & connection"
    case .device: "Device"
    case .videoAudio: "Video & audio"
    case .appearance: "Appearance"
    case .dataSources: "Data sources"
    case .advanced: "Advanced"
    case .experiments: "Feature flags"
    case .developer: "For developers"
    case .about: "About"
    }
  }

  var symbol: String {
    switch self {
    case .account: "person.crop.circle"
    case .server: "server.rack"
    case .device: "appletv"
    case .videoAudio: "play.rectangle"
    case .appearance: "paintbrush"
    case .dataSources: "square.stack.3d.up"
    case .advanced: "gearshape.2"
    case .experiments: "flask"
    case .developer: "hammer"
    case .about: "info.circle"
    }
  }

  var tipKey: LocalizedStringKey {
    switch self {
    case .account: "Settings_Tip_Account"
    case .server: "Settings_Tip_Server"
    case .device: "Settings_Tip_Device"
    case .videoAudio: "Settings_Tip_VideoAudio"
    case .appearance: "Settings_Tip_Appearance"
    case .dataSources: "Settings_Tip_DataSourcesCategory"
    case .advanced: "Settings_Tip_Advanced"
    case .experiments: "Settings_Tip_Experiments"
    case .developer: "Settings_Tip_Developer"
    case .about: "Settings_Tip_About"
    }
  }

  var usesDeviceSettings: Bool {
    self == .server || self == .device
  }
}

/// Developer tools — labs, galleries, probes. Listed in every build.
private enum TVSettingsLab: String, CaseIterable, Identifiable, Hashable {
  case playerCases
  case tvUIKitGallery
  case navFocusLab
  case libraryLab
  case typeStyles
  case streamSurvey

  var id: String { rawValue }

  var titleKey: LocalizedStringKey {
    switch self {
    case .playerCases: "Player cases"
    case .tvUIKitGallery: "TVUIKit Gallery"
    case .navFocusLab: "Navigation / Focus Lab"
    case .libraryLab: "Library Sidebar Lab"
    case .typeStyles: "Type Styles"
    case .streamSurvey: "Stream survey"
    }
  }

  @MainActor @ViewBuilder
  var page: some View {
    switch self {
    case .playerCases: PlayerCasesView()
    case .tvUIKitGallery: TVUIKitComponentGalleryView()
    case .navFocusLab: NavigationFocusLabView()
    case .libraryLab: LibrarySidebarLabView()
    case .typeStyles: SystemTypeStylesCatalogView()
    case .streamSurvey: StreamSurveyView()
    }
  }
}

/// Where metadata comes from — the tvOS rows of `DataSourcesAttributionView`.
private enum TVDataSource: String, CaseIterable, Identifiable, Hashable {
  case tmdb
  case kinopoiskProxy
  case kinopoiskUnofficial

  var id: String { rawValue }

  /// The keyed Kinopoisk API is only a source once the user's key has validated.
  static var current: [TVDataSource] {
    allCases.filter { $0 != .kinopoiskUnofficial || KinopoiskKeyValidation.isValidated }
  }

  var titleKey: LocalizedStringKey {
    switch self {
    case .tmdb: "TMDB"
    case .kinopoiskProxy: "Kinopoisk"
    case .kinopoiskUnofficial: "Kinopoisk Unofficial API"
    }
  }

  var host: String {
    switch self {
    case .tmdb: "themoviedb.org"
    case .kinopoiskProxy: "kpapp.link"
    case .kinopoiskUnofficial: "kinopoiskapiunofficial.tech"
    }
  }

  var tipKey: LocalizedStringKey {
    switch self {
    case .tmdb: "Settings_Tip_DataSources"
    case .kinopoiskProxy:
      "Facts, stills, reviews and some cast details come from a third-party Kinopoisk data proxy (kpapp.link), not an official Kinopoisk product."
    case .kinopoiskUnofficial:
      "Awards and richer metadata also use your own Kinopoisk Unofficial API key (kinopoiskapiunofficial.tech)."
    }
  }
}

// MARK: - Split chrome

/// 50/50 left panel and right list. A pushed page's title sits where the tab bar was.
///
/// Not `.navigationTitle`: on tvOS the system bar is laid out under the hidden tab bar's
/// top inset, which put the title a tab bar's height down, level with the list (tvOS 27.2
/// simulator). The system bar is hidden instead and the title drawn in the tab bar's band.
private struct SettingsSplitLayout<Leading: View, Content: View>: View {
  let title: LocalizedStringKey?
  @ViewBuilder var leading: () -> Leading
  @ViewBuilder var content: () -> Content

  var body: some View {
    if let title {
      split
        .toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .top) {
          Text(title)
            .font(.title3.weight(.bold))
            .foregroundStyle(.secondary)
            .padding(.top, Metrics.titleTopInset)
            .ignoresSafeArea(.container, edges: .top)
        }
    } else {
      split
    }
  }

  private var split: some View {
    HStack(alignment: .top, spacing: 0) {
      leading()
        .padding(.top, topPadding)
        .frame(maxWidth: .infinity)

      ScrollView {
        VStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
          content()
        }
        .padding(.horizontal, Metrics.listHorizontalPadding)
        .padding(.top, topPadding)
        .padding(.bottom, Metrics.listBottomPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .frame(maxWidth: .infinity)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  /// Both columns start on one line.
  private var topPadding: CGFloat {
    title == nil ? Metrics.listTopPaddingRoot : Metrics.listTopPaddingPushed
  }
}

private extension SettingsSplitLayout where Leading == SettingsLeftPanel {
  /// A page whose left panel is its icon plus a tip.
  init(title: LocalizedStringKey?,
       pageSymbol: String,
       tipKey: LocalizedStringKey,
       @ViewBuilder content: @escaping () -> Content) {
    self.init(title: title,
              leading: { SettingsLeftPanel(symbol: pageSymbol, tipKey: tipKey) },
              content: content)
  }
}

/// Icon over tip. When either changes it shifts in sideways, never crossfades.
private struct SettingsLeftPanel: View {
  let symbol: String
  let tipKey: LocalizedStringKey

  var body: some View {
    VStack(spacing: Metrics.previewSpacing) {
      ZStack {
        Image(systemName: symbol)
          .font(.system(size: Metrics.iconPointSize, weight: .medium))
          .foregroundStyle(.secondary)
          .id(symbol)
          .transition(TVProfileSettingsView.panelTransition)
      }
      .frame(width: Metrics.iconFrame, height: Metrics.iconFrame)
      .background(
        RoundedRectangle(cornerRadius: Metrics.iconCornerRadius, style: .continuous)
          .fill(.fill.tertiary)
      )
      .clipShape(RoundedRectangle(cornerRadius: Metrics.iconCornerRadius, style: .continuous))

      ZStack(alignment: .top) {
        Text(tipKey)
          .font(.callout)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .frame(maxWidth: .infinity)
          .id(tipID)
          .transition(TVProfileSettingsView.panelTransition)
      }
      .frame(minHeight: Metrics.tipMinHeight, alignment: .top)
      .padding(.horizontal, Metrics.tipHorizontalPadding)
      .clipped()
    }
    .animation(.smooth(duration: 0.3), value: symbol)
    .animation(.smooth(duration: 0.3), value: tipID)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .padding(.horizontal, Metrics.previewSidePadding)
  }

  /// `LocalizedStringKey` is not `Hashable`; its description is stable per key.
  private var tipID: String { String(describing: tipKey) }
}

/// The left panel while nothing in the list has focus, and on About: the app's own
/// plate, its version and build, and what changed in this build.
private struct SettingsAppInfoPanel: View {
  var showsReleaseNotes = true

  var body: some View {
    VStack(spacing: Metrics.previewSpacing) {
      Image("kinopub_icon")
        .resizable()
        .scaledToFit()
        .frame(width: Metrics.appLogoSize, height: Metrics.appLogoSize)
        .frame(width: Metrics.appPlateWidth, height: Metrics.appPlateHeight)
        // Brand, not chrome: the mark is drawn on a black disc, so the plate is black too.
        .background(
          RoundedRectangle(cornerRadius: Metrics.appPlateCornerRadius, style: .continuous)
            .fill(.black)
        )

      VStack(spacing: 8) {
        Text("KinoPub")
          .font(.title3.weight(.bold))
        Text(SettingsAppInfoPanel.versionLine)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      if showsReleaseNotes, let notes = Bundle.main.releaseNotes {
        Text(verbatim: notes)
          .font(.callout)
          .multilineTextAlignment(.center)
          .lineLimit(Metrics.releaseNotesLineLimit)
          .padding(.horizontal, Metrics.tipHorizontalPadding)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .padding(.horizontal, Metrics.previewSidePadding)
  }

  static var versionLine: LocalizedStringKey {
    "Version \(Bundle.main.appVersionLong) • Build \(Bundle.main.appBuild)"
  }
}

private struct SettingsSection<Content: View>: View {
  let title: Text?
  @ViewBuilder var content: () -> Content

  init(_ title: LocalizedStringKey? = nil, @ViewBuilder content: @escaping () -> Content) {
    self.title = title.map { Text($0) }
    self.content = content
  }

  init(verbatim title: String, @ViewBuilder content: @escaping () -> Content) {
    self.title = Text(verbatim: title)
    self.content = content
  }

  var body: some View {
    VStack(alignment: .leading, spacing: Metrics.rowSpacing) {
      if let title {
        title
          .font(.caption)
          .foregroundStyle(.secondary)
          .textCase(.uppercase)
          .padding(.horizontal, Metrics.pillHorizontalPadding)
          .padding(.bottom, 4)
      }
      content()
    }
  }
}

/// One category's page: its icon on the left with the focused row's tip — or the
/// category's own when the row has none. About shows the app instead.
private struct SettingsCategoryPage<Content: View>: View {
  let category: TVSettingsCategory
  @ViewBuilder var content: (FocusState<SettingsFocusItem?>.Binding) -> Content

  @FocusState private var focused: SettingsFocusItem?

  var body: some View {
    SettingsSplitLayout(title: category.titleKey) {
      if category == .about {
        SettingsAppInfoPanel(showsReleaseNotes: false)
      } else {
        SettingsLeftPanel(symbol: category.symbol, tipKey: focused?.tipKey ?? category.tipKey)
      }
    } content: {
      content($focused)
    }
    .background(Color.KinoPub.background.ignoresSafeArea())
  }
}

// MARK: - What's new

/// This build's notes, one focusable row per line — a block of text focus cannot reach
/// cannot be scrolled on a remote.
private struct TVReleaseNotesPage: View {
  @FocusState private var focused: Int?

  private let lines: [String] = (Bundle.main.releaseNotes ?? "")
    .split(whereSeparator: \.isNewline)
    .map { line in
      var line = line.trimmingCharacters(in: .whitespaces)
      if line.hasPrefix("- ") || line.hasPrefix("• ") { line.removeFirst(2) }
      return line
    }
    .filter { !$0.isEmpty }

  var body: some View {
    SettingsSplitLayout(title: "What's new") {
      SettingsAppInfoPanel(showsReleaseNotes: false)
    } content: {
      SettingsSection {
        if lines.isEmpty {
          SettingsInfoRow(title: "A local build carries no release notes. TestFlight builds show their What to Test text here.")
            .focused($focused, equals: 0)
        } else {
          ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
            SettingsInfoRow(title: "", verbatimTitle: line)
              .focused($focused, equals: index)
          }
        }
      }
    }
    .background(Color.KinoPub.background.ignoresSafeArea())
    .defaultFocus($focused, 0)
  }
}

// MARK: - Routes / focus / tips

private enum SettingsRoute: Hashable {
  case category(TVSettingsCategory)
  case language
  case secondSubtitleLanguage
  case streamQuality
  case streamType
  case serverLocation
  case rememberedTracks
  case releaseNotes
  case kinopoisk
  case networkLog
  case lab(TVSettingsLab)
}

/// One case per focusable row on a page — never one value shared by siblings (the
/// pattern `.claude/skills/tvos-surface/SKILL.md` bans: the engine cannot tell which of
/// them is focused). Payloads only keep siblings apart.
private enum SettingsFocusItem: Hashable {
  case language
  case streamQuality
  case rememberedTracks
  case englishSubs
  case nonCC
  case dual
  case secondLang
  case streamType
  case serverLocation
  case capability(String)
  case info(String)
  case retry
  case kinopoisk
  case source(TVDataSource)
  case logout
  case networkLog
  case streamToPulse
  case activityOverlay
  case releaseNotes
  case lab(TVSettingsLab)

  /// The row's own tip; `nil` falls back to its category's.
  var tipKey: LocalizedStringKey? {
    switch self {
    case .language: "Settings_Tip_Language"
    case .streamQuality: "Settings_Tip_StreamQuality"
    case .rememberedTracks: "Settings_Tip_RememberedTracks"
    case .englishSubs: "Settings_Tip_EnglishSubtitles"
    case .nonCC: "Settings_Tip_PreferNonCC"
    case .dual: "Settings_Tip_DualSubtitles"
    case .secondLang: "Settings_Tip_SecondLanguage"
    case .capability: "Settings_Tip_DeviceCapabilities"
    case .kinopoisk: "Settings_Tip_Kinopoisk"
    case .source(let source): source.tipKey
    case .logout: "Settings_Tip_Logout"
    case .networkLog: "Settings_Tip_NetworkLog"
    case .streamToPulse: "Settings_Tip_StreamToPulse"
    case .activityOverlay: "Settings_Tip_ActivityOverlay"
    case .lab(.streamSurvey): "Settings_Tip_Diagnostics"
    case .streamType, .serverLocation, .info, .retry, .releaseNotes, .lab: nil
    }
  }
}

// MARK: - Pill pieces

/// Title, then an optional value, checkmark or chevron. Colours are the hierarchical
/// styles only: on the focused plate (`.primary`) the label takes the inverse,
/// `.background`, so it reads in dark and light alike.
private struct SettingsPillLabel: View {
  let title: LocalizedStringKey
  var verbatimTitle: String? = nil
  var value: String? = nil
  var showsChevron: Bool = false
  var showsCheckmark: Bool = false
  var isDestructive: Bool = false

  @Environment(\.isFocused) private var isFocused

  var body: some View {
    HStack(spacing: 16) {
      titleText
        .foregroundStyle(titleStyle)
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
      if let value {
        Text(verbatim: value)
          .foregroundStyle(valueStyle)
          // One line, so the capsule keeps even ends; a long value truncates.
          .lineLimit(1)
      }
      if showsCheckmark {
        Image(systemName: "checkmark")
          .foregroundStyle(valueStyle)
      }
      if showsChevron {
        Image(systemName: "chevron.right")
          .font(.caption.weight(.semibold))
          .foregroundStyle(valueStyle)
      }
    }
    .font(.headline)
  }

  @ViewBuilder
  private var titleText: some View {
    if let verbatimTitle {
      Text(verbatim: verbatimTitle)
    } else {
      Text(title)
    }
  }

  private var titleStyle: AnyShapeStyle {
    if isFocused { return AnyShapeStyle(.background) }
    if isDestructive { return AnyShapeStyle(.red) }
    return AnyShapeStyle(.primary)
  }

  private var valueStyle: AnyShapeStyle {
    isFocused ? AnyShapeStyle(.background.secondary) : AnyShapeStyle(.secondary)
  }
}

/// A read-only row. Still a focus stop: it is how the remote reaches — and the page
/// scrolls to — what it says. Select does nothing.
private struct SettingsInfoRow: View {
  let title: LocalizedStringKey
  var verbatimTitle: String? = nil
  var value: String? = nil

  var body: some View {
    Button {} label: {
      SettingsPillLabel(title: title, verbatimTitle: verbatimTitle, value: value)
    }
    .buttonStyle(SettingsPillButtonStyle())
  }
}

private struct SettingsPillButtonStyle: ButtonStyle {
  func makeBody(configuration: ButtonStyleConfiguration) -> some View {
    Pill(configuration: configuration)
  }

  private struct Pill: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isFocused) private var isFocused
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
      configuration.label
        .padding(.horizontal, Metrics.pillHorizontalPadding)
        .padding(.vertical, Metrics.pillVerticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(plate, in: Capsule(style: .continuous))
        .scaleEffect(isFocused ? 1.02 : (configuration.isPressed ? 0.98 : 1.0))
        .opacity(isEnabled ? 1.0 : 0.4)
        .animation(.easeOut(duration: 0.2), value: isFocused)
    }

    private var plate: AnyShapeStyle {
      isFocused ? AnyShapeStyle(.primary) : AnyShapeStyle(.fill.tertiary)
    }
  }
}

// MARK: - Choice destination

private struct SettingsChoiceOption: Identifiable, Hashable {
  let id: String
  let title: String
}

private struct SettingsChoiceView: View {
  let title: LocalizedStringKey
  let pageSymbol: String
  let tipKey: LocalizedStringKey
  let options: [SettingsChoiceOption]
  @Binding var selection: String
  var onSelect: ((String) -> Void)? = nil

  @Environment(\.dismiss) private var dismiss
  @FocusState private var focusedID: String?

  var body: some View {
    SettingsSplitLayout(title: title, pageSymbol: pageSymbol, tipKey: tipKey) {
      ForEach(options) { option in
        Button {
          selection = option.id
          onSelect?(option.id)
          dismiss()
        } label: {
          SettingsPillLabel(
            title: LocalizedStringKey(option.title),
            verbatimTitle: option.title,
            showsCheckmark: selection == option.id
          )
        }
        .buttonStyle(SettingsPillButtonStyle())
        .focused($focusedID, equals: option.id)
      }
    }
    .background(Color.KinoPub.background.ignoresSafeArea())
    .defaultFocus($focusedID, selection)
    .onAppear {
      if focusedID == nil {
        focusedID = selection
      }
    }
  }
}

// MARK: - Feature flags destination

/// Every `FeatureFlag` that matters on tvOS, as the pills the rest of Settings uses. The
/// left panel explains the focused one. The iOS / macOS half is `FeatureFlagsView`.
private struct TVFeatureFlagsPage: View {
  /// One focus value per row — never one shared case (see `SettingsFocusItem`).
  private enum Row: Hashable {
    case flag(FeatureFlag)
    case quit
    case reset
  }

  @State private var values = Dictionary(uniqueKeysWithValues: FeatureFlag.allCases.map { ($0, $0.storedValue) })
  @FocusState private var focused: Row?
  private let flags = FeatureFlag.allCases.filter(\.isRelevantHere)

  var body: some View {
    SettingsSplitLayout(title: "Feature flags", pageSymbol: "flag", tipKey: tip) {
      SettingsSection("Applies on next launch") { rows(appliesAtLaunch: true) }
      SettingsSection("Applies when next opened") { rows(appliesAtLaunch: false) }
      SettingsSection("Defaults") {
        if flags.contains(where: { $0.appliesAtLaunch && values[$0] != $0.isEnabled }) {
          Button { FeatureFlag.quitToApply() } label: {
            SettingsPillLabel(title: "Quit to apply")
          }
          .buttonStyle(SettingsPillButtonStyle())
          .focused($focused, equals: .quit)
        }
        Button {
          FeatureFlag.resetAll()
          values = Dictionary(uniqueKeysWithValues: FeatureFlag.allCases.map { ($0, $0.storedValue) })
        } label: {
          SettingsPillLabel(title: "Reset to defaults", isDestructive: true)
        }
        .buttonStyle(SettingsPillButtonStyle())
        .focused($focused, equals: .reset)
      }
    }
    .background(Color.KinoPub.background.ignoresSafeArea())
  }

  private func rows(appliesAtLaunch: Bool) -> some View {
    ForEach(flags.filter { $0.appliesAtLaunch == appliesAtLaunch }) { flag in
      let isOn = values[flag] ?? flag.defaultValue
      Button {
        flag.set(!isOn)
        values[flag] = !isOn
      } label: {
        SettingsPillLabel(title: "",
                          verbatimTitle: flag.title,
                          value: isOn ? "On".localized : "Off".localized)
      }
      .buttonStyle(SettingsPillButtonStyle())
      .focused($focused, equals: .flag(flag))
    }
  }

  private var tip: LocalizedStringKey {
    switch focused {
    case .flag(let flag)?:
      let changed = values[flag] == flag.defaultValue ? "" : " Ships \(flag.defaultValue ? "on" : "off")."
      return LocalizedStringKey(flag.summary + changed)
    case .quit?:
      return "Launch-time switches take hold on the next launch. This quits the app."
    default:
      return "Stored on this device only. A build ships with the defaults."
    }
  }
}

// MARK: - Kinopoisk key destination

/// First text-entry UI anywhere in this app — auth is device-code OAuth, so
/// there was no existing pattern to follow. `TextField` does work on tvOS (the
/// system on-screen keyboard comes up on focus+click), but typing a 30+ char
/// key via Siri Remote is inherently clunky — an accepted compromise for now,
/// same spirit as this app's other "unverified on real remote" callouts.
private struct TVKinopoiskKeyView: View {
  @StateObject private var model: KinopoiskKeySettingsModel
  @FocusState private var isFieldFocused: Bool

  init(keyProvider: KinopoiskKeyProvider) {
    _model = StateObject(wrappedValue: KinopoiskKeySettingsModel(keyProvider: keyProvider))
  }

  var body: some View {
    SettingsSplitLayout(title: "Kinopoisk", pageSymbol: "photo.stack", tipKey: "Settings_Tip_Kinopoisk") {
      TextField("API key", text: $model.keyText)
        .textFieldStyle(.plain)
        .padding(.horizontal, Metrics.pillHorizontalPadding)
        .padding(.vertical, Metrics.pillVerticalPadding)
        .background(
          Capsule(style: .continuous)
            .fill(isFieldFocused ? AnyShapeStyle(.fill.secondary) : AnyShapeStyle(.fill.tertiary))
        )
        .focused($isFieldFocused)

      Button {
        Task { await model.validate() }
      } label: {
        SettingsPillLabel(title: "Validate")
      }
      .buttonStyle(SettingsPillButtonStyle())
      .disabled(!model.isValidateEnabled)

      Text(model.statusText)
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, Metrics.pillHorizontalPadding)
        .fixedSize(horizontal: false, vertical: true)
    }
    .background(Color.KinoPub.background.ignoresSafeArea())
    .defaultFocus($isFieldFocused, true)
  }
}


// MARK: - Remembered tracks destination

/// The tvOS half of `TrackMemorySections`: same digest, same order. One section per
/// title, one focusable row per scope with its leading choice — the full ladder is noise
/// at ten feet.
private struct TVRememberedTracksPage: View {
  private struct Row: Identifiable {
    let id: String
    let scope: String
    let choice: String
  }

  private struct Group: Identifiable {
    let id: String
    let title: String
    let rows: [Row]
  }

  @State private var groups: [Group] = []
  @FocusState private var focused: String?

  var body: some View {
    SettingsSplitLayout(title: "Remembered tracks",
                        pageSymbol: "captions.bubble",
                        tipKey: "Settings_Tip_RememberedTracks") {
      if groups.isEmpty {
        SettingsSection {
          SettingsInfoRow(title: "Nothing remembered yet. Pick a dub or a subtitle track in the player and it will show up here.")
            .focused($focused, equals: "empty")
        }
      } else {
        ForEach(groups) { group in
          SettingsSection(verbatim: group.title) {
            ForEach(group.rows) { row in
              SettingsInfoRow(title: "", verbatimTitle: row.scope, value: row.choice)
                .focused($focused, equals: row.id)
            }
          }
        }
      }
    }
    .background(Color.KinoPub.background.ignoresSafeArea())
    .onAppear {
      groups = TrackPreferenceDigest.sections(from: AppContext.shared.trackPreferences.storedScopes)
        .enumerated()
        .map { index, section in
          Group(
            id: "\(index)",
            title: title(for: section),
            rows: section.groups.enumerated().compactMap { rowIndex, group in
              guard let leader = group.audio.first ?? group.subtitles.first else { return nil }
              return Row(id: "\(index).\(rowIndex)",
                         scope: scopeLabel(for: group.scope),
                         choice: "\(leader.label) · \(leader.weight)")
            }
          )
        }
        .filter { !$0.rows.isEmpty }
    }
  }

  private func scopeLabel(for scope: TrackMemoryScope) -> String {
    switch scope {
    case .title: return "Whole title".localized
    case let .season(_, season): return "\("Season".localized) \(season)"
    case let .episode(_, season, episode):
      guard let season else { return "\("Episode".localized) \(episode)" }
      return "S\(season)E\(episode)"
    case let .contentClass(name): return name.capitalized
    }
  }

  private func title(for section: TrackPreferenceDigest.Section) -> String {
    guard let titleID = section.titleID else { return "Anime".localized }
    if let snapshot = AppContext.shared.localProgressStore.snapshot(for: titleID) {
      return snapshot.localizedTitle
    }
    return "#\(titleID)"
  }
}

// MARK: - Metrics

private enum Metrics {
  // A pushed page's title, from the top of the screen: the tab bar's band.
  static let titleTopInset: CGFloat = 52

  // Left panel — icon stays put; tip text has a reserved height so focus
  // changes don't reflow the stack.
  static let previewSidePadding: CGFloat = 40
  static let previewSpacing: CGFloat = 28
  static let iconFrame: CGFloat = 260
  static let iconPointSize: CGFloat = 100
  static let iconCornerRadius: CGFloat = 52
  static let tipMinHeight: CGFloat = 120
  static let tipHorizontalPadding: CGFloat = 24

  // App plate on the left panel — a TV icon's 5:3, the mark inside it.
  static let appPlateWidth: CGFloat = 400
  static let appPlateHeight: CGFloat = 240
  static let appPlateCornerRadius: CGFloat = 44
  static let appLogoSize: CGFloat = 132
  static let releaseNotesLineLimit = 8

  // Right list fills its half; only inset, no fixed width clamp.
  static let listHorizontalPadding: CGFloat = 32
  static let listTopPaddingRoot: CGFloat = 72
  static let listTopPaddingPushed: CGFloat = 8
  static let listBottomPadding: CGFloat = 48
  static let sectionSpacing: CGFloat = 36
  static let rowSpacing: CGFloat = 12
  static let pillHorizontalPadding: CGFloat = 28
  static let pillVerticalPadding: CGFloat = 18
}

#endif
