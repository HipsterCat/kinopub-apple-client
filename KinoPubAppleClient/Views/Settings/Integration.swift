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
  case plex
  case douban
  case myShows
  case wikidata
  case skipDB
  case theIntroDB
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
    case .kinopoisk, .tmdb, .trakt, .plex, .omdb, .douban, .myShows, .wikidata, .skipDB, .theIntroDB: true
    case .simkl, .anilist, .myAnimeList: false
    }
  }

  /// Works without anything from the viewer. Trakt's ratings and reviews are public
  /// data: the app's Client ID is enough, no sign-in (Sasha, 2026-11-09).
  var worksByDefault: Bool {
    switch self {
    case .kinopoisk, .tmdb, .douban, .myShows, .wikidata, .skipDB, .theIntroDB: true
    case .trakt: TraktAccount.clientID != nil
    default: false
    }
  }

  /// A source that feeds the title page without anything from the viewer, and can be
  /// switched off: Trakt's ratings and reviews.
  var hasDataSwitch: Bool { dataSwitchDefaultsKey != nil && worksByDefault }

  /// UserDefaults behind that switch.
  var dataSwitchDefaultsKey: String? {
    switch self {
    case .trakt: TraktMetadataAccess.enabledDefaultsKey
    case .douban: DoubanMetadataAccess.enabledDefaultsKey
    case .wikidata: WikidataMetadataAccess.enabledDefaultsKey
    case .myShows: MyShowsMetadataAccess.enabledDefaultsKey
    case .skipDB: SkipTimesMetadataAccess.skipDBDefaultsKey
    case .theIntroDB: SkipTimesMetadataAccess.theIntroDBDefaultsKey
    default: nil
    }
  }

  var dataToggleTitle: String {
    switch self {
    case .douban: "Integration_Douban_DataToggle"
    case .wikidata: "Integration_Wikidata_DataToggle"
    case .myShows: "Integration_MyShows_DataToggle"
    case .skipDB, .theIntroDB: "Integration_SkipTimes_DataToggle"
    default: "Integration_Trakt_DataToggle"
    }
  }

  var dataToggleFooter: String {
    switch self {
    case .douban: "Integration_Douban_DataFooter"
    case .wikidata: "Integration_Wikidata_DataFooter"
    case .myShows: "Integration_MyShows_DataFooter"
    case .skipDB, .theIntroDB: "Integration_SkipTimes_DataFooter"
    default: "Integration_Trakt_DataFooter"
    }
  }

  /// The switch's state, read from storage.
  var isDataSwitchOn: Bool {
    guard let key = dataSwitchDefaultsKey else { return false }
    return UserDefaults.standard.object(forKey: key) as? Bool ?? true
  }

  /// The viewer's own key or account is connected.
  var isConnected: Bool {
    if let keyProvider { return keyProvider.isConnected }
    switch self {
    case .trakt: return TraktAccount.storedUsername != nil
    case .plex: return PlexAccount.storedUsername != nil
    default: return false
    }
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
    case .trakt, .plex, .simkl, .anilist, .myAnimeList: .account
    case .douban, .myShows, .wikidata, .skipDB, .theIntroDB: .builtIn
    }
  }

  var name: String {
    switch self {
    case .kinopoisk: "Kinopoisk".localized
    case .tmdb: "The Movie Database"
    case .omdb: "OMDb"
    case .trakt: "Trakt"
    case .plex: "Plex"
    case .douban: "Douban"
    case .myShows: "MyShows"
    case .wikidata: "Wikidata"
    case .skipDB: "SkipDB"
    case .theIntroDB: "TheIntroDB"
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
    case .plex: "Integration_Plex_About".localized
    case .douban: "Integration_Douban_About".localized
    case .myShows: "Integration_MyShows_About".localized
    case .wikidata: "Integration_Wikidata_About".localized
    case .skipDB: "Integration_SkipDB_About".localized
    case .theIntroDB: "Integration_TheIntroDB_About".localized
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
    case .plex: "Integration_Plex_SignInHelp".localized
    case .douban: "Integration_Douban_Help".localized
    case .myShows: "Integration_MyShows_Help".localized
    case .wikidata: "Integration_Wikidata_Help".localized
    case .skipDB, .theIntroDB: "Integration_SkipTimes_Help".localized
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
    case .plex: URL(string: "https://www.plex.tv")!
    case .douban: URL(string: "https://movie.douban.com")!
    case .myShows: URL(string: "https://myshows.me")!
    case .wikidata: URL(string: "https://www.wikidata.org")!
    case .skipDB: URL(string: "https://skipdb.tv")!
    case .theIntroDB: URL(string: "https://theintrodb.org")!
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
    case .skipDB:
      // ODbL 1.0 asks for attribution wherever the data is used.
      [Note(title: "Attribution".localized, text: "Integration_SkipDB_Attribution".localized)]
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
    case .plex: "plex"
    case .douban: "douban"
    case .myShows: "myshows_tv"
    case .wikidata: "wikidata"
    case .simkl: "simkl"
    case .anilist: "anilist"
    case .myAnimeList: "myanimelist"
    case .omdb, .skipDB, .theIntroDB: nil
    }
  }

  /// The account behind a code sign-in.
  @MainActor
  var account: (any AccountSigningIn)? {
    switch self {
    case .trakt: TraktAccount.shared
    case .plex: PlexAccount.shared
    default: nil
    }
  }

  var markImage: Image? { markName.flatMap(ProviderMark.image(named:)) }

  /// A source with no mark of its own is drawn as Settings draws its panes: a symbol on
  /// the brand colour (Sasha, 2026-11-09). Never an invented logo or acronym.
  var symbol: String {
    switch self {
    case .omdb: "star.fill"
    // Sasha's picks, 2026-11-09.
    case .skipDB: "chevron.forward.dotted.chevron.forward"
    case .theIntroDB: "text.line.first.and.arrowtriangle.forward"
    default: "puzzlepiece.extension.fill"
    }
  }

  /// What the source brings to the title page, one row each on its page, with the mark
  /// of the score it relays or a symbol for the rest.
  struct Provided: Hashable {
    let titleKey: String
    var mark: String?
    var symbol: String = "circle.fill"
    var color: Color = .gray
  }

  var provides: [Provided] {
    let imdb = Provided(titleKey: "Integration_Provides_IMDb", mark: "imdb_big_color")
    let tomatoes = Provided(titleKey: "Integration_Provides_RottenTomatoes", mark: "rotten_tomatoes_critics_big_color")
    let metacritic = Provided(titleKey: "Integration_Provides_Metacritic", mark: "metascore_green")
    let reviews = Provided(titleKey: "Integration_Provides_Reviews", symbol: "text.bubble.fill", color: .blue)
    let boxOffice = Provided(titleKey: "Integration_Provides_BoxOffice", symbol: "dollarsign", color: .green)
    let awards = Provided(titleKey: "Integration_Provides_Awards", symbol: "trophy.fill", color: .orange)
    let audience = Provided(titleKey: "Integration_Provides_Audience", symbol: "person.2.fill", color: .teal)
    switch self {
    case .kinopoisk:
      return [Provided(titleKey: "Integration_Provides_Kinopoisk", mark: "kinopoisk_big_colorful"), imdb, reviews]
    case .tmdb:
      return [Provided(titleKey: "Integration_Provides_TMDB", mark: "tmdb_big_color"),
              Provided(titleKey: "Integration_Provides_Images", symbol: "photo.fill", color: .indigo),
              Provided(titleKey: "Integration_Provides_Episodes", symbol: "list.bullet", color: .purple)]
    case .omdb:
      return [tomatoes, metacritic, imdb, boxOffice, awards]
    case .trakt:
      return [Provided(titleKey: "Integration_Provides_Trakt", mark: "trakt"), tomatoes, metacritic,
              Provided(titleKey: "Integration_Provides_Letterboxd", mark: "letterboxd"),
              Provided(titleKey: "Integration_Provides_MyAnimeList", mark: "myanimelist"), reviews]
    case .plex:
      return [Provided(titleKey: "Integration_Provides_CommonSense", symbol: "figure.and.child.holdinghands", color: .green),
              Provided(titleKey: "Integration_Provides_ContentRating", symbol: "checkmark.shield.fill", color: .gray),
              imdb, tomatoes]
    case .douban:
      return [Provided(titleKey: "Integration_Provides_Douban", mark: "douban"),
              Provided(titleKey: "Integration_Provides_Distribution", symbol: "chart.bar.fill", color: .green), audience]
    case .myShows:
      return [Provided(titleKey: "Integration_Provides_MyShows", mark: "myshows_tv"), audience, imdb]
    case .wikidata:
      return [Provided(titleKey: "Integration_Provides_Links", symbol: "link", color: .blue), boxOffice,
              Provided(titleKey: "Integration_Provides_Budget", symbol: "banknote.fill", color: .green), awards]
    case .skipDB, .theIntroDB:
      return [Provided(titleKey: "Integration_Provides_SkipIntro", symbol: "forward.end.fill", color: .indigo),
              Provided(titleKey: "Integration_Provides_SkipRecap", symbol: "arrow.counterclockwise", color: .gray),
              Provided(titleKey: "Integration_Provides_SkipCredits", symbol: "text.line.last.and.arrowtriangle.forward", color: .purple)]
    case .simkl, .anilist, .myAnimeList:
      return []
    }
  }

  var brandColor: Color {
    switch self {
    case .kinopoisk: Color(red: 1.00, green: 0.40, blue: 0.00)
    case .tmdb: Color(red: 0.05, green: 0.15, blue: 0.25)
    case .omdb: Color(red: 0.80, green: 0.62, blue: 0.10)
    case .trakt: Color(red: 0.93, green: 0.11, blue: 0.14)
    case .plex: Color(red: 0.90, green: 0.63, blue: 0.05)
    case .douban: Color(red: 0.0, green: 0.71, blue: 0.11)
    case .myShows: Color(red: 0.90, green: 0.14, blue: 0.23)
    case .wikidata: Color(red: 0.2, green: 0.4, blue: 0.6)
    case .skipDB: Color(red: 0.36, green: 0.30, blue: 0.85)
    case .theIntroDB: Color(red: 0.12, green: 0.55, blue: 0.75)
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
    if self == .plex {
      return PlexAccount.storedUsername.map(Status.account) ?? .notConnected
    }
    if connection == .builtIn { return isDataSwitchOn ? .byDefault : .notConnected }
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
  var size: CGFloat = SettingsIconView.rowSize

  var body: some View {
    if let mark = integration.markImage {
      // The marks carry their own shape (disc, rounded square); drawn as they are.
      mark
        .resizable()
        .scaledToFit()
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    } else {
      SettingsIconView(systemImage: integration.symbol, color: integration.brandColor, size: size)
        .accessibilityHidden(true)
    }
  }
}

/// One row of what a source brings: its mark, or a symbol tile, at the sidebar's size.
struct IntegrationProvidedIcon: View {
  let item: Integration.Provided
  var size: CGFloat = SettingsIconView.rowSize

  var body: some View {
    if let mark = item.mark.flatMap(ProviderMark.image(named:)) {
      mark
        .resizable()
        .scaledToFit()
        .frame(width: size, height: size)
    } else {
      SettingsIconView(systemImage: item.symbol, color: item.color, size: size)
    }
  }
}
