//
//  SettingsRootView.swift
//  KinoPubAppleClient
//

import SwiftUI
import KinoPubBackend
import KinoPubUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

#if !os(tvOS)
/// Shared Settings shell: sidebar split on macOS and wide iOS; category list on phone.
struct SettingsRootView: View {
  @Environment(\.appContext) private var appContext
  @Bindable var model: ProfileModel
  @State private var showLogoutAlert = false
  @State private var avatarImage: Image?
#if os(iOS)
  /// Over Library on iPhone: TestFlight's sheet, a cross and a small title. The iPad tab
  /// keeps its large one.
  @Environment(\.isSettingsSheet) private var isSheet
  @Environment(\.dismiss) private var dismiss
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  /// Profile by default on the split (Sasha, Settings UX).
  @State private var selectedCategory: SettingsCategory? = .account
  @State private var detailPath: [SettingsDetailRoute] = []
  @State private var compactPath = NavigationPath()
  @State private var searchText = ""
  @State private var isSearchPresented = false
#endif
#if os(macOS)
  /// Back / Forward across panes and pushed pages (`SettingsMacChrome.swift`).
  /// Default pane: Profile / account (was General).
  @State private var history = SettingsHistory(SettingsLocation(category: .account))
  @Environment(\.appearsActive) var appearsActive
  @FocusState private var isFocused: Bool
  @State private var searchText = ""
#endif

  var body: some View {
#if os(macOS)
    macSplit
      .kinopubSettingsChrome()
#else
    Group {
      if horizontalSizeClass == .regular {
        iosSplit
      } else {
        iosCompact
      }
    }
    // Once, on the Group: a sheet on iPad lays out `.regular` first and `.compact` next,
    // so a `.task` on each branch ran twice per open (two `/v1/user`, two toasts).
    .task {
      model.fetch()
      await loadAvatar()
    }
    .kinopubSettingsChrome()
#endif
  }

#if os(macOS)
  private var macSplit: some View {
    NavigationSplitView {
      Group {
        if showsMacSearchResults {
          SettingsSearchResults(query: searchText) { entry in
            searchText = ""
            openSearchEntry(entry)
          }
        } else {
          macSidebarList
        }
      }
      .modifier(SettingsMacSearchableModifier(query: $searchText))
      .focused($isFocused)
      .onAppear {
          isFocused = true
      }
      .navigationSplitViewColumnWidth(Self.macSidebarWidth)
      // System Settings' sidebar does not move; ours was dragged to zero and stayed
      // there (Sasha, 2026-11-08). Pinned, and opened again each time the window opens.
      .background(MacFixedSidebar(width: Self.macSidebarWidth))
      .toolbar(removing: .sidebarToggle)
    } detail: {
      NavigationStack(path: detailPath) {
        macDetailRoot
          .navigationDestination(for: SettingsDetailRoute.self) { route in
            detailDestination(route)
              .settingsMacChrome(title: detailTitle(for: route), isRoot: false)
          }
      }
      .background(MacFixedSidebar(width: Self.macSidebarWidth))
    }
    .environment(history)
    .task {
      model.fetch()
      await loadAvatar()
      if !history.current.category.isAvailable, let first = SettingsCategory.availableCategories.first {
        history.replace(with: SettingsLocation(category: first))
      }
    }
    .settingsAlerts(
      showLogoutAlert: $showLogoutAlert,
      shouldShowExitAlert: $model.shouldShowExitAlert,
      logout: { model.logout() }
    )
  }

  private static let macSidebarWidth: CGFloat = 240

  private var showsMacSearchResults: Bool {
    !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private var macSidebarList: some View {
    List(selection: categorySelection) {
      // A selectable row, as System Settings' account is: a `.plain` button sat on
      // the list without a selection of its own (Sasha, 2026-11-08).
      Section {
        SettingsSidebarProfileView(
          name: profileName,
          subtitle: profileSubtitle,
          avatarImage: avatarImage
        )
        .tag(SettingsCategory.account)
      }

      Section {
        ForEach(SettingsCategory.listedCategories) { category in
          Label {
            Text(category.titleKey)
              .lineLimit(1)
          } icon: {
            SettingsIconView(systemImage: category.systemImage, color: category.iconColor)
          }
          .tag(category)
        }
      }
    }
  }

  /// Picking a pane in the sidebar is a step in the window's history, opening the pane's
  /// root as System Settings does.
  private var categorySelection: Binding<SettingsCategory?> {
    Binding(
      get: { history.current.category },
      set: { category in
        guard let category, category != history.current.category else { return }
        history.visit(SettingsLocation(category: category))
      }
    )
  }

  private var detailPath: Binding<[SettingsDetailRoute]> {
    Binding(
      get: { history.current.path },
      set: { history.stackDidChange(to: $0) }
    )
  }

  @ViewBuilder
  private var macDetailRoot: some View {
    let category = history.current.category
    pane(for: category)
      .settingsMacChrome(title: category.titleKey, isRoot: true)
  }

  private func openSearchEntry(_ entry: SettingsSearchEntry) {
    var location = SettingsLocation(category: entry.category)
    if let route = entry.route {
      location.path = [route]
    }
    history.visit(location)
  }
#endif

#if os(iOS)
  private var iosSplit: some View {
    NavigationSplitView {
      Group {
        if showsCompactSearchResults {
          SettingsSearchResults(query: searchText, onSelect: openSearchEntry(_:))
        } else {
          iosSplitSidebarList
        }
      }
      .navigationTitle("Settings")
      .modifier(SettingsSearchableModifier(
        query: $searchText,
        isPresented: $isSearchPresented,
        isPhone: false
      ))
      .settingsSheetChrome(isSheet: isSheet, dismiss: { dismiss() })
    } detail: {
      NavigationStack(path: $detailPath) {
        Group {
          if let selectedCategory {
            pane(for: selectedCategory)
              .navigationTitle(selectedCategory.titleKey)
              .navigationBarTitleDisplayMode(.inline)
          } else {
            ContentUnavailableView("Settings", systemImage: "gearshape")
          }
        }
        .navigationDestination(for: SettingsDetailRoute.self) { route in
          detailDestination(route)
        }
      }
    }
    .navigationSplitViewStyle(.balanced)
    .settingsAlerts(
      showLogoutAlert: $showLogoutAlert,
      shouldShowExitAlert: $model.shouldShowExitAlert,
      logout: { model.logout() }
    )
  }

  private var iosCompact: some View {
    NavigationStack(path: $compactPath) {
      // Swap the list for results — do not overlay/`allowsHitTesting` the searchable
      // host (that made the bottom search field unresponsive on iPhone).
      Group {
        if showsCompactSearchResults {
          SettingsSearchResults(query: searchText, onSelect: openSearchEntry(_:))
        } else {
          iosCompactCategoryList
        }
      }
      .navigationDestination(for: SettingsCategory.self) { category in
        pane(for: category)
          .navigationTitle(category.titleKey)
          .navigationBarTitleDisplayMode(.inline)
          .navigationDestination(for: SettingsDetailRoute.self) { route in
            detailDestination(route)
          }
      }
      .navigationDestination(for: SettingsDetailRoute.self) { route in
        detailDestination(route)
      }
      .modifier(SettingsSearchableModifier(
        query: $searchText,
        isPresented: $isSearchPresented,
        isPhone: true
      ))
      .settingsSheetChrome(isSheet: isSheet, dismiss: { dismiss() })
    }
    .settingsAlerts(
      showLogoutAlert: $showLogoutAlert,
      shouldShowExitAlert: $model.shouldShowExitAlert,
      logout: { model.logout() }
    )
  }

  private var showsCompactSearchResults: Bool {
    !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private var iosSplitSidebarList: some View {
    List(selection: $selectedCategory) {
      Section {
        SettingsSidebarProfileView(
          name: profileName,
          subtitle: profileSubtitle,
          avatarImage: avatarImage
        )
        .tag(SettingsCategory.account)
      }

      Section {
        ForEach(SettingsCategory.listedCategories) { category in
          Label {
            Text(category.titleKey)
          } icon: {
            SettingsIconView(systemImage: category.systemImage, color: category.iconColor)
          }
          .tag(category)
        }
      }

      Section {
        Label {
          Text("About")
        } icon: {
          SettingsIconView(systemImage: "info.circle.fill", color: .gray)
        }
        .tag(SettingsCategory.about)
      }
    }
  }

  private var iosCompactCategoryList: some View {
    List {
      // The account row opens the account's page, as TestFlight's and Settings' do: it
      // was a dead row and only the categories under it opened (Sasha, 2026-11-10).
      Section {
        NavigationLink(value: SettingsCategory.account) {
          SettingsSidebarProfileView(
            name: profileName,
            subtitle: profileSubtitle,
            avatarImage: avatarImage
          )
        }
      }

      ForEach(SettingsCategory.availableCategories) { category in
        NavigationLink(value: category) {
          Label {
            Text(category.titleKey)
          } icon: {
            SettingsIconView(systemImage: category.systemImage, color: category.iconColor)
          }
        }
      }

      Section {
        NavigationLink(value: SettingsCategory.about) {
          Label {
            Text("About")
          } icon: {
            SettingsIconView(systemImage: "info.circle.fill", color: .gray)
          }
        }
      }
    }
  }

  private func openSearchEntry(_ entry: SettingsSearchEntry) {
    searchText = ""
    isSearchPresented = false
    if horizontalSizeClass == .regular {
      selectedCategory = entry.category
      if let route = entry.route {
        detailPath = [route]
      } else {
        detailPath = []
      }
    } else {
      compactPath = NavigationPath()
      compactPath.append(entry.category)
      if let route = entry.route {
        compactPath.append(route)
      }
    }
  }
#endif

  private var profileName: String {
    let name = model.userData.profile.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !name.isEmpty { return name }
    let username = model.userData.username.trimmingCharacters(in: .whitespacesAndNewlines)
    return username.isEmpty ? "KinoPub" : username
  }

  private var profileSubtitle: String {
    model.userData.subscription.summary
  }

  @ViewBuilder
  private func pane(for category: SettingsCategory) -> some View {
    switch category {
    case .account:
      AccountSettingsPane(model: model, name: profileName, subtitle: profileSubtitle,
                          avatarImage: avatarImage, showLogoutAlert: $showLogoutAlert)
    case .general:
      GeneralSettingsPane(model: model, showLogoutAlert: $showLogoutAlert)
    case .playback:
      PlaybackSettingsPane()
    case .integrations:
      IntegrationsSettingsPane()
    case .downloads:
      DownloadsSettingsPane()
    case .devices:
      DevicesSettingsPane()
    case .appearance:
      AppearanceSettingsPane()
    case .sidebar:
      SidebarSettingsPane()
    case .notifications:
      NotificationsSettingsPane()
    case .details:
      DetailsSettingsPane()
    case .backups:
      BackupsSettingsPane()
    case .network:
      NetworkSettingsPane()
    case .advanced:
      AdvancedSettingsPane()
    case .about:
      AboutView()
    }
  }

  @ViewBuilder
  private func detailDestination(_ route: SettingsDetailRoute) -> some View {
    switch route {
    case .devicesList:
      DevicesListView()
#if os(iOS)
        .navigationTitle("Devices")
#endif
    case .storage:
      StorageSettingsView()
#if os(iOS)
        .navigationTitle("Storage & Data")
#endif
    case .sections:
      SectionsSettingsView()
#if os(iOS)
        .navigationTitle("Sections")
#endif
    case .networkLog:
      NetworkConsoleView()
        .navigationTitle("Network log")
    case .featureFlags:
      FeatureFlagsView()
#if os(iOS)
        .navigationTitle("Feature flags")
#endif
    case .integration(let integration):
      IntegrationDetailView(integration: integration)
        .navigationTitle(integration.name)
    case .detailsItem(let item):
      DetailsEnrichmentItemView(item: item)
    case .titleInfoStrip:
      TitleInfoStripSettingsView()
    case .languageList(let kind):
      PlaybackLanguageListEditor(kind: kind)
#if os(iOS)
        .navigationTitle(kind == .audio ? "Prefer audio in" : "Prefer subtitles in")
#endif
#if DEBUG
    case .streamSurvey:
      StreamSurveyView()
#if os(iOS)
        .navigationTitle("Stream survey")
#endif
    case .uiLab(let chrome):
      UILabRoot(initialChrome: chrome)
#if os(iOS)
        .navigationTitle(LocalizedStringKey(chrome.windowTitle))
#endif
    case .typeStyles:
      SystemTypeStylesCatalogView()
#if os(iOS)
        .navigationTitle("Type Styles")
#endif
    case .libraryLab:
      LibrarySidebarLabView()
#if os(iOS)
        .navigationTitle("Library Sidebar Lab")
#endif
    case .playerCases:
      PlayerCasesView()
#if os(iOS)
        .navigationTitle("Player cases")
#endif
#endif
    }
  }

#if os(macOS)
  private func detailTitle(for route: SettingsDetailRoute) -> LocalizedStringKey {
    switch route {
    case .devicesList: return "Devices"
    case .storage: return "Storage & Data"
    case .sections: return "Sections"
    case .networkLog: return "Network log"
    case .featureFlags: return "Feature flags"
    case .integration(let integration): return LocalizedStringKey(integration.name)
    case .detailsItem(let item): return LocalizedStringKey(item.titleKey)
    case .titleInfoStrip: return "Age rating badge"
    case .languageList(let kind):
      return kind == .audio ? "Prefer audio in" : "Prefer subtitles in"
#if DEBUG
    case .streamSurvey: return "Stream survey"
    case .uiLab(let chrome): return LocalizedStringKey(chrome.windowTitle)
    case .typeStyles: return "Type Styles"
    case .libraryLab: return "Library Sidebar Lab"
    case .playerCases: return "Player cases"
#endif
    }
  }
#endif

  private func loadAvatar() async {
    if let cached = UserProfileCache.shared.loadAvatar(),
       let image = Self.platformImage(from: cached) {
      avatarImage = image
    }
    guard let url = model.userData.profile.avatarURL else { return }
    do {
      let (data, response) = try await URLSession.shared.data(from: url)
      if (response as? HTTPURLResponse)?.statusCode == 404 {
        // No picture of their own (Gravatar's 404): the person glyph, not a cached placeholder.
        avatarImage = nil
        UserProfileCache.shared.clearAvatar()
      } else if let image = Self.platformImage(from: data) {
        avatarImage = image
        UserProfileCache.shared.saveAvatar(data)
      }
    } catch {
      // Keep cached avatar if the network fetch fails.
    }
  }

  private static func platformImage(from data: Data) -> Image? {
#if canImport(UIKit)
    guard let uiImage = UIImage(data: data) else { return nil }
    return Image(uiImage: uiImage)
#elseif canImport(AppKit)
    guard let nsImage = NSImage(data: data) else { return nil }
    return Image(nsImage: nsImage)
#endif
  }
}
#endif

#if os(iOS)
extension EnvironmentValues {
  /// Settings is presented as a sheet (iPhone's Library), not a tab.
  @Entry var isSettingsSheet = false
}

private extension View {
  @ViewBuilder
  func settingsSheetChrome(isSheet: Bool, dismiss: @escaping () -> Void) -> some View {
    if isSheet {
      navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .topBarLeading) {
            Button(role: .close, action: dismiss)
          }
        }
    } else {
      platformNavigationTitle("Settings")
    }
  }
}
#endif

#if !os(tvOS)
/// Switch only — restores UISwitch’s system green under the app’s `.tint(.primary)`
/// without painting close buttons, pickers, or chevrons green.
private struct KinopubSystemToggleStyle: ToggleStyle {
  func makeBody(configuration: ToggleStyleConfiguration) -> some View {
    Toggle(isOn: configuration.$isOn) {
      configuration.label
    }
    .tint(.green)
    // Concrete switch style so this style does not recurse through the environment.
    .toggleStyle(.switch)
  }
}

private extension View {
  /// Toggles keep unmodified system on-colors; every other control keeps the shell tint.
  @ViewBuilder
  func kinopubSettingsChrome() -> some View {
#if os(iOS)
    self.toggleStyle(KinopubSystemToggleStyle())
#else
    self
#endif
  }

  func settingsAlerts(
    showLogoutAlert: Binding<Bool>,
    shouldShowExitAlert: Binding<Bool>,
    logout: @escaping () -> Void
  ) -> some View {
    self
      .alert("Are you sure?", isPresented: showLogoutAlert) {
        Button("Logout", role: .destructive, action: logout)
        Button("Cancel", role: .cancel) { }
      }
      .alert(isPresented: shouldShowExitAlert) {
        Alert(
          title: Text("Restarting the app"),
          message: Text("The app will restart to apply the language change."),
          primaryButton: .default(Text("OK")) { exit(0) },
          secondaryButton: .cancel()
        )
      }
  }
}
#endif
