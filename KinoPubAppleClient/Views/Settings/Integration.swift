//
//  Integration.swift
//  KinoPubAppleClient
//
//  Settings › Integrations, one catalog for every platform: the macOS / iOS form
//  (`IntegrationsSettingsPane`, `IntegrationDetailView`) and the tvOS TVSettingKit pages
//  (`TVSettingsCatalog.integrationSections`) both read their rows, wording and state
//  from here. Laid out like macOS Internet Accounts: a row per source with its icon,
//  each opening a page to connect, switch off or read about it (Sasha, 2026-11-09).
//

import SwiftUI
import KinoPubUI

/// An outside source of metadata or sync. Brand names stay as their owners write them.
enum Integration: String, CaseIterable, Identifiable, Hashable {
  case kinopoisk
  case tmdb
  case omdb
  case trakt
  case douban
  case simkl
  case anilist
  case myAnimeList

  var id: String { rawValue }

  /// How the viewer connects their own access. Kinopoisk and TMDB work without it, by
  /// default; a key of one's own lifts the limits and opens more (Sasha, 2026-11-09).
  enum Connection: Hashable {
    /// The viewer's own API key, entered in an alert and checked before it is kept.
    case apiKey
    /// Signing in to an account (OAuth / device code). None is implemented yet.
    case account
    /// Nothing to connect: the source works through our worker (Douban).
    case builtIn
  }

  /// Wired into the app. The others are listed ahead of time so their place, wording and
  /// links are settled; their pages say they are coming.
  var isSupported: Bool {
    switch self {
    case .kinopoisk, .tmdb, .trakt, .omdb, .douban: true
    case .simkl, .anilist, .myAnimeList: false
    }
  }

  /// Works without anything from the viewer. Trakt's ratings and reviews are public
  /// data: the app's Client ID is enough, no sign-in (Sasha, 2026-11-09).
  var worksByDefault: Bool {
    switch self {
    case .kinopoisk, .tmdb, .douban: true
    case .trakt: TraktAccount.clientID != nil
    default: false
    }
  }

  /// A source that feeds the title page without anything from the viewer, and can be
  /// switched off: Trakt's ratings and reviews.
  var hasDataSwitch: Bool { (self == .trakt || self == .douban) && worksByDefault }

  /// UserDefaults behind that switch.
  var dataSwitchDefaultsKey: String? {
    switch self {
    case .trakt: TraktMetadataAccess.enabledDefaultsKey
    case .douban: DoubanMetadataAccess.enabledDefaultsKey
    default: nil
    }
  }

  var dataToggleTitle: String {
    self == .douban ? "Integration_Douban_DataToggle" : "Integration_Trakt_DataToggle"
  }

  var dataToggleFooter: String {
    self == .douban ? "Integration_Douban_DataFooter" : "Integration_Trakt_DataFooter"
  }

  /// The viewer's own key or account is connected.
  var isConnected: Bool {
    if let keyProvider { return keyProvider.isConnected }
    return self == .trakt && TraktAccount.storedUsername != nil
  }

  /// «Доступно»: what works by default, and whatever the viewer has connected — a source
  /// moves here once connected (Sasha, 2026-11-09).
  static var available: [Integration] { allCases.filter { $0.worksByDefault || $0.isConnected } }
  /// «Дополнительно»: the rest. Rows of sources that cannot be connected yet are disabled.
  static var additional: [Integration] { allCases.filter { !available.contains($0) } }

  /// The viewer's own key, for the sources that take one.
  var keyProvider: IntegrationKeyProvider? {
    switch self {
    case .kinopoisk: .kinopoisk
    case .tmdb: .tmdb
    case .omdb: .omdb
    default: nil
    }
  }

  var connection: Connection {
    switch self {
    case .kinopoisk, .tmdb, .omdb: .apiKey
    case .trakt, .simkl, .anilist, .myAnimeList: .account
    case .douban: .builtIn
    }
  }

  var name: String {
    switch self {
    case .kinopoisk: "Kinopoisk".localized
    case .tmdb: "The Movie Database"
    case .omdb: "OMDb"
    case .trakt: "Trakt"
    case .douban: "Douban"
    case .simkl: "Simkl"
    case .anilist: "AniList"
    case .myAnimeList: "MyAnimeList"
    }
  }

  /// The page's explanation: where the data comes from and what it is used for.
  var about: String {
    switch self {
    case .kinopoisk: "Integration_Kinopoisk_About".localized
    case .tmdb: "Integration_TMDB_About".localized
    case .omdb: "Integration_OMDb_About".localized
    case .trakt: "Integration_Trakt_About".localized
    case .douban: "Integration_Douban_About".localized
    case .simkl: "Integration_Simkl_About".localized
    case .anilist: "Integration_AniList_About".localized
    case .myAnimeList: "Integration_MyAnimeList_About".localized
    }
  }

  /// What the "?" beside Connect explains: how to get a key, or how signing in will work.
  var connectHelp: String {
    switch self {
    case .kinopoisk: "Integration_Kinopoisk_KeyHelp".localized
    case .omdb: "Integration_OMDb_KeyHelp".localized
    case .tmdb: "Integration_TMDB_KeyHelp".localized
    case .trakt: "Integration_Trakt_SignInHelp".localized
    case .douban: "Integration_Douban_Help".localized
    case .simkl, .anilist, .myAnimeList: "Integration_Account_Help".localized
    }
  }

  /// The source's own site.
  var website: URL {
    switch self {
    case .kinopoisk: URL(string: "https://kinopoiskapiunofficial.tech")!
    case .tmdb: URL(string: "https://www.themoviedb.org")!
    case .omdb: URL(string: "https://www.omdbapi.com")!
    case .trakt: URL(string: "https://trakt.tv")!
    case .douban: URL(string: "https://movie.douban.com")!
    case .simkl: URL(string: "https://simkl.com")!
    case .anilist: URL(string: "https://anilist.co")!
    case .myAnimeList: URL(string: "https://myanimelist.net")!
    }
  }

  /// Where a key is issued, for sources that ask for one.
  var keyURL: URL? {
    switch self {
    case .kinopoisk: URL(string: "https://kinopoiskapiunofficial.tech/signup")!
    case .omdb: URL(string: "https://www.omdbapi.com/apikey.aspx")!
    case .tmdb: URL(string: "https://www.themoviedb.org/settings/api")!
    default: nil
    }
  }

  /// Hosts the source talks to, shown as plain text where a link cannot be opened (tvOS).
  var host: String { website.host()?.replacingOccurrences(of: "www.", with: "") ?? website.absoluteString }

  /// A fact that rides on the source's page without a page of its own.
  struct Note: Hashable {
    var title: String
    var text: String
    /// Shown beside the title where there is room (tvOS's value column).
    var value: String = ""
  }

  var notes: [Note] {
    switch self {
    case .tmdb:
      [Note(title: "Attribution".localized,
            text: "This product uses the TMDB API but is not endorsed or certified by TMDB.".localized)]
    case .trakt:
      // Required by Trakt's API terms wherever its data is shown.
      [Note(title: "Attribution".localized,
            text: "This product uses Trakt but is not endorsed or certified by Trakt.".localized)]
    default:
      []
    }
  }

  // MARK: Icon

  /// The service's mark in KinoPubUI's `ratings/` catalog (Sasha's set, 2026-11-09).
  /// Nil draws the brand colour with the short name on it.
  var markName: String? {
    switch self {
    case .kinopoisk: "kinopoisk_big_colorful"
    case .tmdb: "tmdb_big_color"
    case .trakt: "trakt"
    case .douban: "douban"
    case .simkl: "simkl"
    case .anilist: "anilist"
    case .myAnimeList: "myanimelist"
    case .omdb: nil
    }
  }

  var markImage: Image? { markName.flatMap(ProviderMark.image(named:)) }

  var monogram: String {
    switch self {
    case .kinopoisk: "КП"
    case .tmdb: "TMDB"
    case .omdb: "OMDb"
    case .trakt: "trakt"
    case .douban: "豆"
    case .simkl: "S"
    case .anilist: "AL"
    case .myAnimeList: "MAL"
    }
  }

  var brandColor: Color {
    switch self {
    case .kinopoisk: Color(red: 1.00, green: 0.40, blue: 0.00)
    case .tmdb: Color(red: 0.05, green: 0.15, blue: 0.25)
    case .omdb: Color(red: 0.80, green: 0.62, blue: 0.10)
    case .trakt: Color(red: 0.93, green: 0.11, blue: 0.14)
    case .douban: Color(red: 0.0, green: 0.71, blue: 0.11)
    case .simkl: Color(red: 0.10, green: 0.10, blue: 0.12)
    case .anilist: Color(red: 0.01, green: 0.66, blue: 1.00)
    case .myAnimeList: Color(red: 0.18, green: 0.32, blue: 0.64)
    }
  }

  // MARK: State

  /// What the list and the page say about the source right now.
  enum Status: Equatable {
    /// Working without anything from the viewer.
    case byDefault
    /// The viewer's own key is connected and switched on.
    case apiKey
    /// Signed in to an account, by its name.
    case account(String)
    case notConnected
    case comingSoon

    var title: String {
      switch self {
      case .byDefault: "By default".localized
      case .apiKey: "Integration_Status_APIKey".localized
      case .account(let name): name
      case .notConnected: "Not connected".localized
      case .comingSoon: "Coming soon".localized
      }
    }

    /// Shown on the list row's trailing edge. A source not connected says nothing there.
    var isShownInList: Bool {
      switch self {
      case .byDefault, .apiKey, .account: true
      case .notConnected, .comingSoon: false
      }
    }
  }

  /// Read from storage each time; nothing caches it.
  var status: Status {
    guard isSupported else { return .comingSoon }
    if self == .trakt {
      if let name = TraktAccount.storedUsername { return .account(name) }
      return worksByDefault && TraktMetadataAccess.isEnabled ? .byDefault : .notConnected
    }
    if self == .douban { return DoubanMetadataAccess.isEnabled ? .byDefault : .notConnected }
    // OMDb has no default path: without the viewer's key it is not connected.
    guard let keyProvider, keyProvider.isConnected, keyProvider.isEnabled else {
      return worksByDefault ? .byDefault : .notConnected
    }
    return .apiKey
  }
}

/// The source's logo in a rounded square, or its short name on the brand colour.
struct IntegrationIconView: View {
  let integration: Integration
  var size: CGFloat = 28

  var body: some View {
    if let mark = integration.markImage {
      // The marks carry their own shape (disc, rounded square); drawn as they are.
      mark
        .resizable()
        .scaledToFit()
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    } else {
      let shape = RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
      Text(verbatim: integration.monogram)
        .font(.system(size: size * 0.36, weight: .heavy, design: .rounded))
        .lineLimit(1)
        .minimumScaleFactor(0.4)
        .foregroundStyle(.white)
        .padding(size * 0.1)
        .frame(width: size, height: size)
        .background(integration.brandColor.gradient, in: shape)
        .accessibilityHidden(true)
    }
  }
}
