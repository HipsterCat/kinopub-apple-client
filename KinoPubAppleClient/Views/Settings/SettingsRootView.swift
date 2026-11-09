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
/// Shared Settings shell: sidebar split on macOS, category list on iOS.
struct SettingsRootView: View {
  @Environment(\.appContext) private var appContext
  @Bindable var model: ProfileModel
  @State private var showLogoutAlert = false
  @State private var avatarImage: Image?
#if os(macOS)
  /// Back / Forward across panes and pushed pages (`SettingsMacChrome.swift`).
  @State private var history = SettingsHistory(SettingsLocation(category: .general))
     @Environment(\.appearsActive) var appearsActive
     @FocusState private var isFocused: Bool
     @State private var searchText = ""
#endif

  var body: some View {
#if os(macOS)
    macSplit
#else
    iosList
#endif
  }

#if os(macOS)
  private var macSplit: some View {
    NavigationSplitView {
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
      .searchable(text: $searchText, placement: .sidebar)
      .focused($isFocused)
      .opacity(1.0)
      .onAppear {
          isFocused = true
      }
//      .listStyle(.sidebar)
      .navigationSplitViewColumnWidth(Self.macSidebarWidth)
      // System Settings' sidebar does not move; ours was dragged to zero and stayed
      // there (Sasha, 2026-11-08). Pinned, and opened again each time the window opens.
      .background(MacFixedSidebar(width: Self.macSidebarWidth))
      .toolbar(removing: .sidebarToggle)
    } detail: {
      NavigationStack(path: detailPath) {
        macDetailRoot
          .navigationDestination(for: SettingsDetailRoute.self) { route in
            switch route {
            case .devicesList:
              DevicesListView()
                .settingsMacChrome(title: "Devices", isRoot: false)
            case .storage:
              StorageSettingsView()
                .settingsMacChrome(title: "Storage & Data", isRoot: false)
            case .sections:
              SectionsSettingsView()
                .settingsMacChrome(title: "Sections", isRoot: false)
            case .networkLog:
              NetworkConsoleView()
                .settingsMacChrome(title: "Network log", isRoot: false)
            case .featureFlags:
              FeatureFlagsView()
                .settingsMacChrome(title: "Feature flags", isRoot: false)
            case .integration(let integration):
              IntegrationDetailView(integration: integration, keyProvider: appContext.kinopoiskKeyProvider)
                .settingsMacChrome(title: LocalizedStringKey(integration.name), isRoot: false)
            case .languageList(let kind):
              PlaybackLanguageListEditor(kind: kind)
                .settingsMacChrome(title: kind == .audio ? "Prefer audio in" : "Prefer subtitles in", isRoot: false)
#if DEBUG
            case .streamSurvey:
              StreamSurveyView()
                .settingsMacChrome(title: "Stream survey", isRoot: false)
            case .uiLab(let chrome):
              // Prefer Window menu / openWindow on macOS; this is a fallback push.
              UILabRoot(initialChrome: chrome)
                .settingsMacChrome(title: LocalizedStringKey(chrome.windowTitle), isRoot: false)
            case .typeStyles:
              SystemTypeStylesCatalogView()
                .settingsMacChrome(title: "Type Styles", isRoot: false)
            case .libraryLab:
              LibrarySidebarLabView()
                .settingsMacChrome(title: "Library Sidebar Lab", isRoot: false)
            case .playerCases:
              PlayerCasesView()
                .settingsMacChrome(title: "Player cases", isRoot: false)
#endif
            }
          }
      }
      .background(MacFixedSidebar(width: Self.macSidebarWidth))
//      .navigationSplitViewColumnWidth(500)
    }
//    .navigationSplitViewStyle(.balanced)
//    .frame(width: 720, height: 520)
    .environment(history)
    .task {
      model.fetch()
      await loadAvatar()
      if !history.current.category.isAvailable, let first = SettingsCategory.availableCategories.first {
        history.replace(with: SettingsLocation(category: first))
      }
    }
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

  private static let macSidebarWidth: CGFloat = 240

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
#endif

#if os(iOS)
  private var iosList: some View {
    List {
      Section {
        SettingsSidebarProfileView(
          name: profileName,
          subtitle: profileSubtitle,
          avatarImage: avatarImage
        )
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
        NavigationLink {
          AboutView()
        } label: {
          Label {
            Text("About")
          } icon: {
            SettingsIconView(systemImage: "info.circle.fill", color: .gray)
          }
        }
      }
    }
    .navigationDestination(for: SettingsCategory.self) { category in
      pane(for: category)
        .navigationTitle(category.titleKey)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: SettingsDetailRoute.self) { route in
          switch route {
          case .devicesList:
            DevicesListView()
          case .storage:
            StorageSettingsView()
          case .sections:
            SectionsSettingsView()
          case .networkLog:
            NetworkConsoleView()
              .navigationTitle("Network log")
          case .featureFlags:
            FeatureFlagsView()
          case .integration(let integration):
            IntegrationDetailView(integration: integration, keyProvider: appContext.kinopoiskKeyProvider)
              .navigationTitle(integration.name)
          case .languageList(let kind):
            PlaybackLanguageListEditor(kind: kind)
#if DEBUG
          case .streamSurvey:
            StreamSurveyView()
          case .uiLab(let chrome):
            UILabRoot(initialChrome: chrome)
          case .typeStyles:
            SystemTypeStylesCatalogView()
          case .libraryLab:
            LibrarySidebarLabView()
          case .playerCases:
            PlayerCasesView()
#endif
          }
        }
    }
    .platformNavigationTitle("Settings")
    .task {
      model.fetch()
      await loadAvatar()
    }
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
#endif

  private var profileName: String {
    let name = model.userData.profile.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !name.isEmpty { return name }
    let username = model.userData.username.trimmingCharacters(in: .whitespacesAndNewlines)
    return username.isEmpty ? "KinoPub" : username
  }

  private var profileSubtitle: String {
    let days = model.userData.subscription.days
    return "\(days) \("days".localized)"
  }

  @ViewBuilder
  private func pane(for category: SettingsCategory) -> some View {
    switch category {
    case .account:
#if os(macOS)
      AccountSettingsPane(model: model, showLogoutAlert: $showLogoutAlert)
#else
      GeneralSettingsPane(model: model, showLogoutAlert: $showLogoutAlert)
#endif
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

  private func loadAvatar() async {
    if let cached = UserProfileCache.shared.loadAvatar(),
       let image = Self.platformImage(from: cached) {
      avatarImage = image
    }
    let urlString = model.userData.profile.avatar
    guard let urlString, !urlString.isEmpty, let url = URL(string: urlString) else { return }
    do {
      let (data, _) = try await URLSession.shared.data(from: url)
      if let image = Self.platformImage(from: data) {
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
