//
//  SettingsSearch.swift
//  KinoPubAppleClient
//
//  Nested Settings search — Plozz-shaped: a flat catalog of controls (not only
//  top-level categories), local scoring, `.searchable` + results list that opens
//  the real pane (and optional detail route). Borrowed from Plozz SettingsSearch.
//

import SwiftUI

#if !os(tvOS)

/// One searchable control or nested page inside Settings.
struct SettingsSearchEntry: Identifiable, Hashable {
  let id: String
  /// Localization key for the row title (English source string).
  let titleKey: String
  /// Free-text aliases (EN + RU) for plain-language queries.
  let keywords: String
  let category: SettingsCategory
  /// Optional push inside the category's detail stack.
  let route: SettingsDetailRoute?
  /// Extra breadcrumb segment under the category (e.g. "Poster score").
  let sectionKey: String?

  init(
    _ id: String,
    titleKey: String,
    keywords: String = "",
    category: SettingsCategory,
    route: SettingsDetailRoute? = nil,
    sectionKey: String? = nil
  ) {
    self.id = id
    self.titleKey = titleKey
    self.keywords = keywords
    self.category = category
    self.route = route
    self.sectionKey = sectionKey
  }

  var localizedTitle: String {
    String(localized: String.LocalizationValue(titleKey))
  }

  var breadcrumb: String {
    var parts: [String] = [String(localized: String.LocalizationValue(categoryTitleKey))]
    if let sectionKey {
      parts.append(String(localized: String.LocalizationValue(sectionKey)))
    }
    // Same arrow System Settings uses in search hits (Accessibility → Head Tracking).
    return parts.joined(separator: " → ")
  }

  private var categoryTitleKey: String {
    switch category {
    case .account: return "Account"
    case .general: return "General"
    case .playback: return "Playback"
    case .integrations: return "Integrations"
    case .downloads: return "Downloads"
    case .devices: return "Devices"
    case .appearance: return "Appearance"
    case .sidebar: return "Sidebar"
    case .notifications: return "Notifications"
    case .details: return "Details"
    case .backups: return "Backups"
    case .network: return "Network"
    case .advanced: return "Advanced"
    case .about: return "About"
    }
  }

  /// Whether this entry should appear in search on the current platform / flags.
  var isAvailable: Bool {
    switch category {
    case .account, .about:
      return true
    case .downloads:
#if os(tvOS)
      return false
#else
      return FeatureFlags.downloadsEnabled
#endif
    case .sidebar:
#if os(macOS)
      return true
#else
      return false
#endif
    default:
      return true
    }
  }
}

/// Local fuzzy index over title + keywords + breadcrumb. Queries stay on-device.
struct SettingsSearchIndex {
  private struct Document {
    let entry: SettingsSearchEntry
    let titleWords: [String]
    let aliasWords: [String]
  }

  private let documents: [Document]

  init(entries: [SettingsSearchEntry] = SettingsSearchCatalog.entries) {
    documents = entries.filter(\.isAvailable).map { entry in
      let title = entry.localizedTitle.lowercased()
      let breadcrumb = entry.breadcrumb.lowercased()
      let aliases = (entry.keywords + " " + breadcrumb).lowercased()
      return Document(
        entry: entry,
        titleWords: Self.tokens(title),
        aliasWords: Self.tokens(aliases)
      )
    }
  }

  func results(for query: String) -> [SettingsSearchEntry] {
    let rawTokens = Self.tokens(query.lowercased())
    // Drop filler words only when something else remains. A lone «в» / «на» / «и»
    // must still prefix-match («Воспроизведение», «Настройки», …) — System Settings
    // does the same for short queries.
    let meaningful = rawTokens.filter { !Self.fillers.contains($0) }
    let tokens = meaningful.isEmpty ? rawTokens : meaningful
    guard !tokens.isEmpty else { return [] }

    var scored: [(SettingsSearchEntry, Int)] = []
    for document in documents {
      var score = 0
      var matchedAll = true
      for token in tokens {
        if let titleHit = Self.bestMatch(token, in: document.titleWords) {
          score += titleHit
        } else if let aliasHit = Self.bestMatch(token, in: document.aliasWords) {
          score += aliasHit / 2
        } else {
          matchedAll = false
          break
        }
      }
      guard matchedAll else { continue }
      let title = document.entry.localizedTitle.lowercased()
      if title == tokens.joined(separator: " ") { score += 1000 }
      else if title.hasPrefix(tokens[0]) { score += 400 }
      scored.append((document.entry, score))
    }
    return scored.sorted { lhs, rhs in
      if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
      return lhs.0.id < rhs.0.id
    }.map(\.0)
  }

  private static let fillers: Set<String> = [
    "settings", "setting", "the", "a", "an", "in", "on", "to", "of",
    "настройки", "настройка", "в", "на", "и", "для"
  ]

  private static func tokens(_ text: String) -> [String] {
    text.split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { !$0.isEmpty }
  }

  private static func bestMatch(_ token: String, in words: [String]) -> Int? {
    var best: Int?
    for word in words {
      if word == token { best = max(best ?? 0, 100) }
      else if word.hasPrefix(token) { best = max(best ?? 0, 80) }
      else if token.hasPrefix(word), word.count >= 3 { best = max(best ?? 0, 50) }
      else if Self.editDistance(token, word) <= 1, token.count >= 4 {
        best = max(best ?? 0, 40)
      }
    }
    return best
  }

  private static func editDistance(_ a: String, _ b: String) -> Int {
    if a == b { return 0 }
    if a.isEmpty { return b.count }
    if b.isEmpty { return a.count }
    if abs(a.count - b.count) > 1 { return 2 }
    let aChars = Array(a)
    let bChars = Array(b)
    var previous = Array(0...bChars.count)
    for i in 1...aChars.count {
      var current = [i] + Array(repeating: 0, count: bChars.count)
      for j in 1...bChars.count {
        let cost = aChars[i - 1] == bChars[j - 1] ? 0 : 1
        current[j] = min(
          previous[j] + 1,
          current[j - 1] + 1,
          previous[j - 1] + cost
        )
      }
      previous = current
    }
    return previous[bChars.count]
  }
}

/// Hand-maintained flat list of nested Settings controls.
enum SettingsSearchCatalog {
  static let entries: [SettingsSearchEntry] = base + platformExtras + integrations

  /// Shared across iOS and macOS. No `#if` inside this literal — Swift rejects
  /// conditional compilation in container literals.
  private static let base: [SettingsSearchEntry] = [
    // Category roots — so the sidebar names themselves are searchable (EN + RU).
    .init("category-general", titleKey: "General",
          keywords: "основные general",
          category: .general),
    .init("category-playback", titleKey: "Playback",
          keywords: "воспроизведение playback player плеер",
          category: .playback),
    .init("category-integrations", titleKey: "Integrations",
          keywords: "интеграции integrations sources источники",
          category: .integrations),
    .init("category-downloads", titleKey: "Downloads",
          keywords: "загрузки downloads",
          category: .downloads),
    .init("category-devices", titleKey: "Devices",
          keywords: "устройства devices",
          category: .devices),
    .init("category-appearance", titleKey: "Appearance",
          keywords: "внешний вид appearance оформление",
          category: .appearance),
    .init("category-notifications", titleKey: "Notifications",
          keywords: "уведомления notifications",
          category: .notifications),
    .init("category-details", titleKey: "Details",
          keywords: "детали details enrichment метаданные",
          category: .details),
    .init("category-backups", titleKey: "Backups",
          keywords: "backups резервные копии",
          category: .backups),
    .init("category-network", titleKey: "Network",
          keywords: "сеть network подключение",
          category: .network),
    .init("category-advanced", titleKey: "Advanced",
          keywords: "дополнительно advanced",
          category: .advanced),

    // Account / Profile
    .init("account-profile", titleKey: "Account",
          keywords: "profile user logout аккаунт профиль выход",
          category: .account),
    .init("account-username", titleKey: "User Name",
          keywords: "username login имя пользователь",
          category: .account),
    .init("account-subscription", titleKey: "User Subscription",
          keywords: "subscription plan подписка",
          category: .account),

    // General
    .init("general-language", titleKey: "Select Language",
          keywords: "language locale язык интерфейс",
          category: .general),
    .init("general-version", titleKey: "App version",
          keywords: "version build версия",
          category: .general),

    // Playback
    .init("playback-quality", titleKey: "Stream quality",
          keywords: "quality hls 4k stream качество поток воспроизведение",
          category: .playback),
    .init("playback-auto-next", titleKey: "Auto-Play Next Episode",
          keywords: "autoplay next episode следующая серия авто",
          category: .playback),
    .init("playback-next-season", titleKey: "Continue to Next Season",
          keywords: "next season следующий сезон",
          category: .playback),
    .init("playback-skip", titleKey: "Settings_Skip",
          keywords: "skip intro credits пропустить заставка",
          category: .playback),
    .init("playback-skip-delay", titleKey: "Settings_SkipDelay",
          keywords: "skip delay задержка пропуска",
          category: .playback),
    .init("playback-skip-style", titleKey: "Settings_SkipStyle",
          keywords: "skip style вид пропуска",
          category: .playback),
    .init("playback-audio-languages", titleKey: "Prefer audio in",
          keywords: "audio language dub озвучка язык",
          category: .playback, route: .languageList(.audio)),
    .init("playback-dub-floor", titleKey: "Lowest acceptable dub",
          keywords: "dub floor озвучка порог",
          category: .playback),
    .init("playback-anime-original", titleKey: "Anime in the original",
          keywords: "anime original japanese аниме оригинал",
          category: .playback),
    .init("playback-subtitle-mode", titleKey: "Subtitle mode",
          keywords: "subtitles captions субтитры режим",
          category: .playback),
    .init("playback-subtitle-languages", titleKey: "Prefer subtitles in",
          keywords: "subtitle language язык субтитров",
          category: .playback, route: .languageList(.subtitles)),
    .init("playback-prefer-non-cc", titleKey: "Prefer non-CC / non-SDH",
          keywords: "cc sdh captions субтитры без cc",
          category: .playback),

    // Devices
    .init("devices-stream-type", titleKey: "Stream type",
          keywords: "hls mpegts stream type тип потока",
          category: .devices),
    .init("devices-server", titleKey: "Server location",
          keywords: "server location сервер регион",
          category: .devices),
    .init("devices-4k", titleKey: "4K",
          keywords: "uhd 4k",
          category: .devices),
    .init("devices-hevc", titleKey: "HEVC",
          keywords: "hevc h265",
          category: .devices),
    .init("devices-hdr", titleKey: "HDR",
          keywords: "hdr dolby",
          category: .devices),
    .init("devices-manage", titleKey: "Manage devices",
          keywords: "devices list устройства",
          category: .devices, route: .devicesList),

    // Appearance
    .init("appearance-theme", titleKey: "Theme",
          keywords: "theme dark light system appearance тема тёмная светлая система внешний вид",
          category: .appearance),
    .init("appearance-covers", titleKey: "Covers and images",
          keywords: "covers posters artwork обложки картинки",
          category: .appearance),
    .init("appearance-rating", titleKey: "Rating",
          keywords: "rating score оценка рейтинг",
          category: .appearance, sectionKey: "Poster score"),
    .init("appearance-rating-source", titleKey: "Rating source",
          keywords: "imdb kinopoisk combined источник оценки",
          category: .appearance, sectionKey: "Poster score"),
    .init("appearance-vote-count", titleKey: "Show vote count",
          keywords: "votes count голоса",
          category: .appearance, sectionKey: "Poster score"),
    .init("appearance-imdb", titleKey: "Show IMDb",
          keywords: "imdb",
          category: .appearance, sectionKey: "Poster score"),
    .init("appearance-kinopoisk", titleKey: "Show Kinopoisk",
          keywords: "kinopoisk кинопоиск",
          category: .appearance, sectionKey: "Poster score"),
    .init("appearance-badges", titleKey: "Quality badges",
          keywords: "4k hdr hd badges значки качество",
          category: .appearance, sectionKey: "Badges"),
    .init("appearance-unwatched-count", titleKey: "Unwatched episode count",
          keywords: "unwatched episodes subscribed following непросмотренных серий подписка бейдж",
          category: .appearance, sectionKey: "Badges"),
    .init("appearance-bookmark-badge", titleKey: "Bookmark on artwork",
          keywords: "bookmark закладка на постере",
          category: .appearance, sectionKey: "Badges"),
    .init("appearance-original-title", titleKey: "Original title",
          keywords: "original title оригинальное название",
          category: .appearance, sectionKey: "Vertical posters"),
    .init("appearance-year", titleKey: "Year",
          keywords: "year год",
          category: .appearance, sectionKey: "Vertical posters"),
    .init("appearance-sections", titleKey: "Sections",
          keywords: "tabs home sections вкладки секции главная",
          category: .appearance, route: .sections),
    .init("sections-home-banner", titleKey: "Баннер на Главной",
          keywords: "home banner баннер главная",
          category: .appearance, route: .sections),
    .init("sections-exclude-concerts", titleKey: "Без концертов на Главной",
          keywords: "concerts концерты главная",
          category: .appearance, route: .sections),

    // Details
    .init("details-metadata-fetching", titleKey: "Metadata Fetching",
          keywords: "metadata enrichment метаданные обогащение",
          category: .details),
    .init("details-age-rating", titleKey: "Age rating badge",
          keywords: "age rating certification возраст",
          category: .details, sectionKey: "Display"),
    .init("details-spoilers-descriptions", titleKey: "Hide descriptions",
          keywords: "spoilers spoilers описания спойлеры",
          category: .details, sectionKey: "Spoilers"),
    .init("details-spoilers-titles", titleKey: "Hide titles",
          keywords: "spoilers titles названия спойлеры",
          category: .details, sectionKey: "Spoilers"),
    .init("details-spoilers-blur", titleKey: "Blur previews",
          keywords: "spoilers blur кадры спойлеры",
          category: .details, sectionKey: "Spoilers"),
    .init("details-posters", titleKey: "Posters",
          keywords: "posters постеры",
          category: .details, route: .detailsItem(.posters), sectionKey: "Images"),
    .init("details-cast", titleKey: "Cast & Team",
          keywords: "cast crew актёры состав",
          category: .details, route: .detailsItem(.castAndTeam), sectionKey: "Info"),
    .init("details-ratings", titleKey: "Ratings",
          keywords: "ratings оценки",
          category: .details, route: .detailsItem(.ratings), sectionKey: "Info"),
    .init("details-skip", titleKey: "Skip timings",
          keywords: "skip intro credits пропуск",
          category: .details, route: .detailsItem(.skipTimings), sectionKey: "Info"),

    // Downloads
    .init("downloads-simultaneous", titleKey: "Simultaneous Downloads",
          keywords: "downloads parallel одновременные загрузки",
          category: .downloads),

    // Notifications
    .init("notifications-badge", titleKey: "App Icon Badge",
          keywords: "badge icon бейдж иконка уведомления",
          category: .notifications),
    .init("notifications-badge-mode", titleKey: "Display the number of",
          keywords: "unwatched episodes shows new непросмотренные серии",
          category: .notifications),

    // Network
    .init("network-proxy", titleKey: "Use proxy",
          keywords: "proxy прокси",
          category: .network),
    .init("network-ipv6", titleKey: "Prefer IPv6",
          keywords: "ipv6",
          category: .network),

    // Backups
    .init("backups-icloud", titleKey: "iCloud Sync",
          keywords: "icloud backup sync резервная копия",
          category: .backups),

    // Advanced
    .init("advanced-storage", titleKey: "Storage & Data",
          keywords: "storage cache disk память хранилище",
          category: .advanced, route: .storage),
    .init("advanced-network-log", titleKey: "Network log",
          keywords: "pulse network log сеть лог",
          category: .advanced, route: .networkLog),
    .init("advanced-feature-flags", titleKey: "Feature flags",
          keywords: "feature flags диагностика флаги",
          category: .advanced, route: .featureFlags),
    .init("advanced-activity-overlay", titleKey: "Show in-flight requests",
          keywords: "in-flight requests overlay запросы",
          category: .advanced),
    .init("advanced-pulse-stream", titleKey: "Stream to Pulse on Mac",
          keywords: "pulse remote stream пульс",
          category: .advanced),

    // About
    .init("about", titleKey: "About",
          keywords: "about version licenses о программе лицензии",
          category: .about),
  ]

  private static var platformExtras: [SettingsSearchEntry] {
#if os(macOS)
    [
      .init("general-always-on-top", titleKey: "AlwaysOnTop",
            keywords: "window always on top поверх окон",
            category: .general),
      .init("sidebar-folders", titleKey: "Show bookmark folders",
            keywords: "sidebar folders закладки боковая",
            category: .sidebar),
    ]
#else
    []
#endif
  }

  private static var integrations: [SettingsSearchEntry] {
    Integration.allCases.map { integration in
      SettingsSearchEntry(
        "integration-\(integration.id)",
        titleKey: integration.name,
        keywords: "integration \(integration.name) интеграция",
        category: .integrations,
        route: .integration(integration)
      )
    }
  }
}

/// Results list shown while the Settings search field is non-empty.
struct SettingsSearchResults: View {
  let query: String
  let onSelect: (SettingsSearchEntry) -> Void

  private var results: [SettingsSearchEntry] {
    SettingsSearchIndex().results(for: query)
  }

  var body: some View {
    List {
      if results.isEmpty {
        ContentUnavailableView.search(text: query)
      } else {
        ForEach(results) { entry in
          Button {
            onSelect(entry)
          } label: {
            // iPhone / Mac System Settings search row: section tile, title, path.
            HStack(spacing: 12) {
              SettingsIconView(
                systemImage: entry.category.systemImage,
                color: entry.category.iconColor
              )
              VStack(alignment: .leading, spacing: 2) {
                Text(entry.localizedTitle)
                Text(entry.breadcrumb)
                  .font(.subheadline)
                  .foregroundStyle(.secondary)
              }
              Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
        }
      }
    }
#if os(iOS)
    .listStyle(.insetGrouped)
#elseif os(macOS)
    .listStyle(.sidebar)
#endif
  }
}

#if os(iOS)
/// Phone: bottom search (iOS 26). Wide / iPad: nav-bar drawer always — Plozz placement.
/// Only attaches `.searchable` — the host swaps its body when `query` is non-empty
/// (overlay + `allowsHitTesting(false)` ate taps on the iPhone search field).
struct SettingsSearchableModifier: ViewModifier {
  @Binding var query: String
  @Binding var isPresented: Bool
  var isPhone: Bool
  /// Kept for call-site compatibility; results are rendered by the host.
  var onSelect: (SettingsSearchEntry) -> Void = { _ in }

  func body(content: Content) -> some View {
    Group {
      if #available(iOS 26.0, *), isPhone {
        searchableContent(content)
          .toolbar {
            DefaultToolbarItem(kind: .search, placement: .bottomBar)
          }
      } else {
        searchableContent(content)
      }
    }
  }

  private func searchableContent(_ content: Content) -> some View {
    content
      .searchable(
        text: $query,
        isPresented: $isPresented,
        placement: isPhone
          ? .automatic
          : .navigationBarDrawer(displayMode: .always),
        prompt: "Search settings"
      )
  }
}
#endif

#if os(macOS)
struct SettingsMacSearchableModifier: ViewModifier {
  @Binding var query: String
  /// Kept for call-site compatibility; results are rendered by the host.
  var onSelect: (SettingsSearchEntry) -> Void = { _ in }

  func body(content: Content) -> some View {
    content
      .searchable(text: $query, placement: .sidebar, prompt: "Search settings")
  }
}
#endif

#endif
