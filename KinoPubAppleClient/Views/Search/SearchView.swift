//
//  SearchView.swift
//  KinoPubAppleClient
//

import SwiftUI
import KinoPubUI
import KinoPubBackend
#if canImport(UIKit)
import UIKit
#endif

/// Search, sorting and filtering all live here so the Main tab can be a pure
/// browse surface (rows of artwork) the way tvOS apps present a home screen.
struct SearchView: View {
  @EnvironmentObject var navigationState: NavigationState
  @Environment(ErrorHandler.self) var errorHandler
  @EnvironmentObject var authState: AuthState
  @Environment(\.appContext) var appContext

  @StateObject private var catalog: LibraryCatalog
  @StateObject private var cardMenu = MediaCardMenuCoordinator()
  /// What the search field shows. When this matches `filterFieldAnchor`, the
  /// catalog is filter-driven (query stays empty so the filter bar stays up).
//     #if os(tvOS)
//     UISearchBar
//     #endif
#if os(macOS)
  // Bound to the shell's always-visible toolbar field (`NavigationState.macSearchFieldText`).
#else
  @State private var searchFieldText = ""
#endif
  /// The label we stuffed into the field for a filter jump — editing away from
  /// it switches to a normal text search.
  @State private var filterFieldAnchor: String?
#if os(tvOS)
  /// kino.pub's own type-ahead for the typed text (`/v1.1/autocomplete`) — the
  /// suggestion row's completions. Empty offline; local titles stand in then.
  @State private var tvAutocomplete: [SearchAutocompleteEntry] = []
#endif
  @State private var navigationTitleText: String = "Search".localized

  @Environment(\.openURL) private var openURL

  init(catalog: @autoclosure @escaping () -> LibraryCatalog) {
    _catalog = StateObject(wrappedValue: catalog())
  }

  /// Enough empty posters to sketch a couple of rows before the page arrives.
  private static let placeholderCount = 12

  var body: some View {
#if os(tvOS)
    if FeatureFlags.tvUIKitSearch {
      tvBody
    } else {
      standardBody
    }
#else
    standardBody
#endif
  }

#if os(tvOS)
  /// UIKit search (`TVSearchPage`): the system keyboard, suggestion row and scope bar
  /// over the same page collection every tab uses.
  ///
  /// Results are local first: every title the app already holds (`ContentStore` — Home
  /// rows, Library) is matched as you type and painted at once, then the server's
  /// answer fills in whatever the device did not know. Offline, search still finds what
  /// is on the shelves.
  private var tvBody: some View {
    @Bindable var errorHandler = errorHandler
    return RouteStack(tab: .search) {
      TVSearchPage(
        sections: tvSections,
        status: tvStatus,
        text: searchFieldText,
        placeholder: "Search".localized,
        suggestions: tvSuggestions,
        onTextChange: { searchFieldText = $0 },
        onCommit: { SearchHistory.record($0) },
        onSelect: { _, item in
          switch item {
          case .card(let card):
            SearchHistory.record(searchFieldText)
            navigationState.push(.detailsById(card.itemID))
          case .person(let person):
            guard let match = tvPeople.first(where: { $0.id == person.id }) else { return }
            SearchHistory.record(searchFieldText)
            navigationState.push(.person(match))
          case .chip, .placeholder:
            break
          }
        },
        onChipOption: { chip, option in
          TVSearchFilters.apply(chip: chip, option: option, to: catalog, searching: !trimmedQuery.isEmpty)
        },
        onNearEnd: { _ in
          guard let last = catalog.items.last else { return }
          catalog.loadMoreContent(after: last)
        },
        contextMenuProvider: { card in
          MediaCardContextMenus.entries(for: card,
                                        surface: .shelf,
                                        menu: cardMenu,
                                        pushRoute: { navigationState.push($0) },
                                        openURL: { openURL($0) })
        },
        onRetry: { Task { await catalog.refresh() } }
      )
      // Horizontal and bottom only, never the top: the search container lays its
      // keyboard out below the tab bar from the top safe area — ignoring that put the
      // keyboard, suggestions and scope bar *under* the bar, and the focus engine found
      // nothing below the bar but the results (focus log, 2026-09-24). The sides are the
      // container's own: SwiftUI's 80 pt inset on top of UIKit's doubled the field's
      // indent and clipped the results' rails at 80 / 1840.
      .ignoresSafeArea(.container, edges: [.horizontal, .bottom])
      .handleError(state: $errorHandler.state)
      .task {
        cardMenu.bind(errorHandler: errorHandler)
        if let pending = navigationState.pendingSearch {
          navigationState.pendingSearch = nil
          applyPending(pending)
        } else {
          if let query = DebugLaunch.searchQuery, searchFieldText.isEmpty {
            searchFieldText = query
          }
          await catalog.load()
        }
      }
      .task { await cardMenu.refreshFolders() }
      .mediaCardNewFolderAlert(cardMenu)
      .onChange(of: navigationState.pendingSearch) { _, pending in
        guard let pending else { return }
        navigationState.pendingSearch = nil
        applyPending(pending)
      }
      .onChange(of: searchFieldText) { _, newValue in
        handleSearchFieldChange(newValue)
      }
      .task(id: trimmedQuery) {
        // Type-ahead after a short pause in typing; a new keystroke cancels this task.
        let query = trimmedQuery
        guard !query.isEmpty else { tvAutocomplete = []; return }
        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled else { return }
        let entries = (try? await appContext.contentService.autocomplete(query: query)) ?? []
        guard !Task.isCancelled else { return }
        tvAutocomplete = entries
      }
    }
  }

  private var trimmedQuery: String {
    searchFieldText.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// Every title the device already knows, matched on title and original title.
  /// Episode stills are skipped — their caption is an episode, not a title.
  private var localMatches: [MediaCard] {
    let query = trimmedQuery
    guard !query.isEmpty else { return [] }
    var seen = Set<Int>()
    var out: [MediaCard] = []
    for state in appContext.contentStore.rows.values {
      for card in state.cards where !card.isLandscape && !card.opensCollection {
        guard !seen.contains(card.itemID), card.matchesSearch(query) else { continue }
        seen.insert(card.itemID)
        out.append(card)
      }
    }
    return out
  }

  /// Local matches first, then whatever the server adds — while nothing narrows the
  /// search. A filter or a sort is the server's answer alone: the shelves' cards carry
  /// no genres or countries to filter on, and they would break the server's order.
  private var tvResults: [MediaCard] {
    let server = catalog.items.map { MediaCard($0) }
    guard !trimmedQuery.isEmpty,
          !catalog.filter.hasActiveFilters, catalog.searchSort == nil else { return server }
    // Local first in order, but a title the server also returned takes the server's
    // card: a shelf card carries no year or genres, and its line under the title was
    // empty (2026-09-26).
    let fromServer = Dictionary(server.map { ($0.itemID, $0) }, uniquingKeysWith: { first, _ in first })
    var seen = Set<Int>()
    var merged: [MediaCard] = []
    for card in localMatches + server where !seen.contains(card.itemID) {
      seen.insert(card.itemID)
      merged.append(fromServer[card.itemID] ?? card)
    }
    return merged
  }

  /// People whose name holds the query, from the credits of what the server returned —
  /// the search endpoint matches `cast` and `director`, so a name typed into the field
  /// is as likely to be a person as a title. Directors first, then cast, in result order.
  private var tvPeople: [MediaPerson] {
    let query = trimmedQuery
    guard !query.isEmpty else { return [] }
    let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
    var seen = Set<String>()
    var out: [MediaPerson] = []
    for role in [MediaPerson.Role.director, .actor] {
      for item in catalog.items {
        let credits = role == .director ? item.director : item.cast
        // A word of the name starts with the query ("ма" → Мадс, not Томас) — the same
        // prefix rule kino.pub's type-ahead uses.
        for name in credits.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) })
        // A multi-word query ("мадс мик") matches the name as a whole.
        where !name.isEmpty && (query.contains(" ")
          ? name.range(of: query, options: options) != nil
          : name.split(separator: " ").contains(where: {
              $0.range(of: query, options: options.union(.anchored)) != nil
            })) {
          guard seen.insert(name.lowercased()).inserted else { continue }
          out.append(MediaPerson(name: name, role: role))
        }
      }
    }
    return Array(out.prefix(Self.topPeopleLimit))
  }

  private static let topPeopleLimit = 3
  /// Two rows of three on screen, a few more a Right away.
  private static let topCardsLimit = 12

  /// The best matches as wide text cards, two rows deep, with the people whose name
  /// matched after the first two titles. No row title — the cards say what they are,
  /// and the rows under them get the height.
  private func topCards(from results: [MediaCard]) -> TVPageSection? {
    let people = tvPeople.map { person in
      TVPageItem.person(TVUIKitPerson(
        id: person.id,
        name: person.name,
        nameComponents: TVUIKitPerson.nameComponents(from: person.name),
        caption: (person.role == .director ? "Director" : "Actor").localized,
        photoURL: person.photoURL
      ))
    }
    let titles = results.prefix(Self.topCardsLimit - people.count).map(TVPageItem.card)
    let items = Array(titles.prefix(2)) + people + Array(titles.dropFirst(2))
    guard !items.isEmpty else { return nil }
    // Two rows only once one row is full: two matches are a row of two, not a column.
    let columns = 3
    return .cards(id: "top", title: nil, columns: columns, rows: items.count > columns ? 2 : 1,
                  match: trimmedQuery, items: items)
  }

  private var tvSections: [TVPageSection] {
    let results = tvResults
    let filters = TVSearchFilters.row(catalog: catalog, searching: !trimmedQuery.isEmpty)
    if results.isEmpty {
      // The filter row stays over "No Results" / a failed load: a filter or sort that
      // emptied the page is undone from there (`TVPageStatus` shows under chip rows).
      return catalog.isLoading
        ? [filters, .placeholder(id: "results", title: nil, kind: .poster, columns: 6, flow: .grid)]
        : [filters]
    }
    // Browsing (empty field): the catalog in the chosen order, as one grid.
    guard !trimmedQuery.isEmpty else {
      return [filters, .posters(id: "browse", title: nil, flow: .grid, caption: .always, cards: results)]
    }
    // Films and series both in the results: rails by kind, the way the TV app files
    // them. Only one kind (the type filter narrowed it, or that is all there is): one
    // grid under the cards.
    let cards = topCards(from: results)
    let movies = results.filter { !$0.isSeries }
    let series = results.filter(\.isSeries)
    guard !movies.isEmpty, !series.isEmpty else {
      return [filters, cards, .posters(id: "results", title: nil, flow: .grid, caption: .always, cards: results)]
        .compactMap { $0 }
    }
    return [
      filters,
      cards,
      movies.isEmpty ? nil : TVPageSection.posters(id: "movies", title: "Movies".localized, caption: .always, cards: movies),
      series.isEmpty ? nil : TVPageSection.posters(id: "series", title: "Series".localized, caption: .always, cards: series)
    ].compactMap { $0 }
  }

  private var tvStatus: TVPageStatus {
    let empty = tvResults.isEmpty
    if catalog.loadFailed && empty {
      return .failed(message: catalog.loadError?.userFacingMessage
                       ?? "Check your connection and try again.".localized,
                     retryTitle: "Try Again".localized)
    }
    if empty && !catalog.isLoading && !trimmedQuery.isEmpty { return .message("No Results".localized) }
    return .content
  }

  /// Empty field: recent queries, then starters. Typing: recents that still match,
  /// then kino.pub's own type-ahead — or, offline, titles the device knows that start
  /// with what was typed.
  private var tvSuggestions: [TVSearchSuggestion] {
    let query = trimmedQuery
    let recents = SearchHistory.recent
    guard !query.isEmpty else {
      let starters = SearchStarters.queries.filter { starter in
        !recents.contains { $0.caseInsensitiveCompare(starter) == .orderedSame }
      }
      return (recents.map { TVSearchSuggestion($0, kind: .recent) }
        + starters.map { TVSearchSuggestion($0, kind: .suggested) }).prefix(8).map { $0 }
    }
    let matchingRecents = recents.filter {
      $0.localizedCaseInsensitiveContains(query) && $0.caseInsensitiveCompare(query) != .orderedSame
    }
    let completions = tvAutocomplete.isEmpty
      ? localMatches.map(\.title).filter {
          $0.range(of: query, options: [.caseInsensitive, .diacriticInsensitive, .anchored]) != nil
        }
      : tvAutocomplete.map(\.title)
    var seen = Set<String>([query.lowercased()])
    let items = matchingRecents.map { TVSearchSuggestion($0, kind: .recent) }
      + completions.map { TVSearchSuggestion($0, kind: .suggested) }
    return items.filter { seen.insert($0.text.lowercased()).inserted }.prefix(6).map { $0 }
  }
#endif

  private var standardBody: some View {
    @Bindable var errorHandler = errorHandler
    return RouteStack(tab: .search) {
      Group {
        if catalog.loadFailed && catalog.items.isEmpty {
          // First page failed — full-screen retry. A failed page further down keeps
          // the grid and only adds an inline retry at its bottom.
          UnavailableView(title: "Couldn't Load",
                          systemImage: "wifi.exclamationmark",
                          message: catalog.loadError?.userFacingMessage ?? "Check your connection and try again.".localized,
                          retryTitle: "Try Again",
                          onRetry: {
            Task { await catalog.refresh() }
          })
        } else {
          ContentItemsListView(
            items: $catalog.items,
            onLoadMoreContent: { item in
              catalog.loadMoreContent(after: item)
            },
            navigationLinkProvider: { item in
              SearchRoutesLinkProvider().link(for: item)
            },
            contextMenuProvider: { item in
              MediaCardContextMenus.entries(
                for: item,
                menu: cardMenu,
                pushRoute: { navigationState.push($0) },
                openURL: { openURL($0) }
              )
            },
            placeholderCount: showsPlaceholders ? Self.placeholderCount : 0,
            emptyMessage: showsEmptyMessage ? "No Results" : nil,
            pagination: catalog.paginationState,
            onRetryPagination: {
              catalog.retryPagination()
            }
          ) {
            // No in-content Back on tvOS. Search is a normal tab there, so the way out
            // is up into the tab bar — a chevron row above the grid is a phone idiom
            // that also steals the first focus target on every entry.
            //
            // Filters scroll away with the grid on iOS/tvOS. On macOS they live in
            // the toolbar accessory bar under the principal search field.
#if !os(macOS)
            if !catalog.isSearching {
              LibraryFiltersBar(catalog: catalog)
            }
#endif
          }
        }
      }
#if os(macOS)
      // Finder/Photos: compact trailing toolbar field + suggestion menu; not under-tab chrome.
      .macToolbarSearch()
      .navigationTitle("Search")
#else
      .searchable(text: $searchFieldText, placement: .automatic)
      .searchSuggestions {
        // Only while the field is empty: once there is a query, the results below are
        // the better answer and a menu over them is in the way.
        if searchFieldText.isEmpty {
          Section("Try Searching") {
            ForEach(SearchStarters.queries, id: \.self) { starter in
              Text(starter).searchCompletion(starter)
            }
          }
        }
      }
      .platformNavigationTitle(navigationTitleText)
#endif
      .toolbar {
#if os(macOS)
        // Filters under the trailing search field (accessory), not icon menus.
        ToolbarItem(placement: .accessoryBar(id: MacToolbarChrome.accessoryID)) {
          if !catalog.isSearching {
            LibraryFiltersBar(catalog: catalog)
              .frame(maxWidth: .infinity)
          } else {
            Color.clear
              .frame(height: MacToolbarChrome.accessoryMinHeight)
              .frame(maxWidth: .infinity)
          }
        }
#endif
#if !os(tvOS)
        // Leave Search → previous tab. Only at Search root so NavigationStack can own
        // system back/forward once a title is pushed. tvOS has no equivalent — you go
        // back up to the tab bar there.
        if navigationState.canReturnFromSearch && navigationState.searchRoutes.isEmpty {
          ToolbarItem(placement: searchReturnPlacement) {
            Button {
              navigationState.returnFromSearch()
            } label: {
              Label(backLabel, systemImage: "chevron.backward")
            }
          }
        }
#endif
      }
      .handleError(state: $errorHandler.state)
      .task {
        cardMenu.bind(errorHandler: errorHandler)
        if let pending = navigationState.pendingSearch {
          navigationState.pendingSearch = nil
          applyPending(pending)
        } else {
          await catalog.load()
        }
      }
      .task { await cardMenu.refreshFolders() }
      .mediaCardNewFolderAlert(cardMenu)
      .onChange(of: navigationState.pendingSearch) { _, pending in
        guard let pending else { return }
        navigationState.pendingSearch = nil
        applyPending(pending)
      }
#if os(macOS)
      .onChange(of: navigationState.macSearchFieldText) { _, newValue in
        handleSearchFieldChange(newValue)
      }
#else
      .onChange(of: searchFieldText) { _, newValue in
        handleSearchFieldChange(newValue)
      }
#endif
    }
  }

  private var searchReturnPlacement: ToolbarItemPlacement {
#if os(macOS)
    // Leading toolbar — same strip as system back/forward once the stack has depth.
    .navigation
#else
    .topBarLeading
#endif
  }

  private var backLabel: String {
    guard let tab = navigationState.searchReturnTab else { return "Back".localized }
    switch tab {
    case .home: return "For You".localized
    case .movies: return "Movies".localized
    case .series: return "Series".localized
    case .library: return "Library".localized
    case .watchlist: return "Watchlist".localized
    case .recentlyWatched: return "Recently Watched".localized
    case .bookmarks, .bookmark: return "Bookmarks".localized
    default: return "Back".localized
    }
  }

  private func applyPending(_ pending: PendingSearch) {
    filterFieldAnchor = pending.title
#if os(macOS)
    navigationState.macSearchFieldText = pending.title
#else
    searchFieldText = pending.title
#endif
    navigationTitleText = pending.title
    catalog.applyExternalFilter(pending.filter)
  }

  private func handleSearchFieldChange(_ newValue: String) {
    if let anchor = filterFieldAnchor {
      guard newValue != anchor else { return }
      filterFieldAnchor = nil
      navigationTitleText = "Search".localized
      catalog.clearFilters()
      catalog.query = newValue
      return
    }
    catalog.query = newValue
    if newValue.trimmingCharacters(in: .whitespaces).isEmpty {
      navigationTitleText = "Search".localized
    }
  }

  private var showsPlaceholders: Bool {
    catalog.items.isEmpty && catalog.isLoading
  }

  private var showsEmptyMessage: Bool {
    catalog.items.isEmpty && catalog.isSearching && !catalog.isLoading
  }
}

#if os(tvOS)
/// The pull-downs above tvOS search results: type, genre, country, years, the other
/// filters, and the sort at the trailing end. System `UIButton` menus
/// (`TVPageChip.menu`); every pick is a `LibraryFilter` change. What the server applies
/// (verified live 2026-09-26, docs/providers/kinopub/video.md): type, genre, country (a
/// comma is OR), year and rating ranges (`conditions[]`), quality ("at least"),
/// finished. AC3 and "no adverts" are filtered on the device from fields every result
/// carries. Language, voiceover, age and subtitles are not offered: the mobile API
/// ignores every form of them tried.
///
/// Type, genre and country are multi-select — a pick toggles and the menu stays up.
/// Every type is on by default (no `type` sent); no genre, no country by default.
enum TVSearchFilters {
  static let type = "type", genre = "genre", country = "country", years = "years"
  static let facets = "facets", sort = "sort"
  private static let any = "any"
  private static let reset = "reset"
  /// Sort option id for the server's own relevance order (search only).
  private static let relevance = "relevance"

  /// Types whose titles have episodes — where "finished only" means something.
  private static let episodic: Set<MediaType> = [.serial, .docuserial, .tvshow]

  /// The types on — every type when the filter names none.
  static func selectedTypes(_ filter: LibraryFilter) -> Set<MediaType> {
    if !filter.contentTypes.isEmpty { return filter.contentTypes }
    if let single = filter.contentType { return [single] }
    return Set(MediaType.allCases)
  }

  /// "Драма", or "Драма +2" for several.
  private static func summary(_ titles: [String], none: String) -> String {
    guard let first = titles.first else { return none }
    return titles.count == 1 ? first : "\(first) +\(titles.count - 1)"
  }

  private static func option(_ id: String, _ title: String, _ selected: Bool) -> TVPageChip.MenuNode {
    .option(.init(id: id, title: title), isSelected: selected)
  }

  @MainActor
  static func row(catalog: LibraryCatalog, searching: Bool) -> TVPageSection {
    let filter = catalog.filter
    let types = selectedTypes(filter)
    let allTypes = types.count == MediaType.allCases.count

    // Type — "Все" is part of the list, not a section above it.
    let typeChip = TVPageChip(
      id: type,
      title: allTypes ? "All".localized
        : summary(MediaType.allCases.filter(types.contains).map { $0.titleKey.localized }, none: "All".localized),
      menu: .init(nodes: [option(any, "All".localized, allTypes)]
                    + MediaType.allCases.map { option($0.rawValue, $0.titleKey.localized, types.contains($0)) },
                  keepsPresented: true),
      isActive: !allTypes
    )

    // Genre — only the sets the chosen types use. One set: a flat list under "Любой".
    // Several: "Любой" and a submenu per set, each titled with what is picked in it.
    let kinds = GenreKind.allCases.filter { kind in types.contains { $0.genreKind == kind } }
    let picked = Set(filter.genreIDs)
    let byKind = kinds.map { kind in (kind, catalog.genres.filter { $0.kind == kind }) }.filter { !$0.1.isEmpty }
    let anyGenre = option(any, "Any_Masculine".localized, picked.isEmpty)
    let genreNodes: [TVPageChip.MenuNode]
    if byKind.count <= 1 {
      genreNodes = [anyGenre] + (byKind.first?.1 ?? []).map { option("\($0.id)", $0.title, picked.contains($0.id)) }
    } else {
      genreNodes = [anyGenre] + byKind.map { kind, genres in
        let chosen = genres.filter { picked.contains($0.id) }.map(\.title)
        return .submenu(title: kind.title,
                        subtitle: chosen.isEmpty ? nil : summary(chosen, none: ""),
                        children: genres.map { option("\($0.id)", $0.title, picked.contains($0.id)) })
      }
    }
    let genreChip = TVPageChip(
      id: genre,
      title: summary(catalog.genres.filter { picked.contains($0.id) }.map(\.title), none: "Genre".localized),
      menu: .init(nodes: genreNodes, keepsPresented: true),
      isActive: !picked.isEmpty
    )

    // Country — kino.pub's popularity order, "Любая" first.
    let countries = filter.countryIDs
    let countryChip = TVPageChip(
      id: country,
      title: summary(catalog.countries.filter { countries.contains($0.id) }.map(\.title), none: "Country".localized),
      menu: .init(nodes: [option(any, "Any_Feminine".localized, countries.isEmpty)]
                    + catalog.countries.map { option("\($0.id)", $0.title, countries.contains($0.id)) },
                  keepsPresented: true),
      isActive: !countries.isEmpty
    )

    let yearsChip = TVPageChip(
      id: years,
      title: yearsTitle(filter),
      menu: .init(nodes: yearNodes(filter)),
      isActive: filter.yearFrom != nil || filter.yearTo != nil
    )

    let facetsChip = TVPageChip(
      id: facets,
      title: "Filters".localized,
      systemImage: "line.3.horizontal.decrease",
      menu: .init(nodes: facetNodes(filter, episodic: !types.isDisjoint(with: episodic))),
      isActive: filter.hasClientSideFacets || filter.finishedOnly || filter.minimumQuality != nil
        || filter.kinopoiskMin != nil || filter.kinopoiskMax != nil
        || filter.imdbMin != nil || filter.imdbMax != nil
    )

    let sortChip: TVPageChip
    if searching {
      let current = catalog.searchSort
      sortChip = TVPageChip(
        id: sort,
        title: current.map { $0.titleKey.localized } ?? "Relevance".localized,
        systemImage: "arrow.up.arrow.down",
        menu: .init(options: [.init(id: relevance, title: "Relevance".localized)]
                      + MediaSortOrder.allCases.map { .init(id: $0.rawValue, title: $0.titleKey.localized) },
                    selectedID: current?.rawValue ?? relevance),
        alignment: .trailing
      )
    } else {
      sortChip = TVPageChip(
        id: sort,
        title: filter.sort.titleKey.localized,
        systemImage: "arrow.up.arrow.down",
        menu: .init(options: MediaSortOrder.allCases.map { .init(id: $0.rawValue, title: $0.titleKey.localized) },
                    selectedID: filter.sort.rawValue),
        alignment: .trailing
      )
    }
    return .chips(id: "filters", title: nil,
                  chips: [typeChip, genreChip, countryChip, yearsChip, facetsChip, sortChip])
  }

  // MARK: Years

  private static var currentYear: Int { Calendar.current.component(.year, from: Date()) }
  /// kino.pub's catalogue starts in 1912.
  private static let firstYear = 1912

  /// The last few years one by one, then decades — from the decade's first year, to its
  /// last.
  private static func yearChoices(ends: Bool) -> [Int] {
    let recent = (0..<5).map { currentYear - $0 }
    let lastDecade = (currentYear / 10) * 10
    let decades = stride(from: lastDecade, through: 1910, by: -10).map { ends ? $0 + 9 : $0 }
      .filter { $0 < recent.last! && $0 >= firstYear - 9 }
    return recent + decades.map { max($0, firstYear) }
  }

  private static func yearsTitle(_ filter: LibraryFilter) -> String {
    switch (filter.yearFrom, filter.yearTo) {
    case let (from?, to?): return from == to ? "\(from)" : "\(from)–\(to)"
    case let (from?, nil): return String(format: "from %lld".localized, from)
    case let (nil, to?): return String(format: "to %lld".localized, to)
    default: return "Years".localized
    }
  }

  private static func yearNodes(_ filter: LibraryFilter) -> [TVPageChip.MenuNode] {
    func bound(_ prefix: String, _ title: String, _ value: Int?, ends: Bool) -> TVPageChip.MenuNode {
      let anyTitle = "Any_Masculine".localized
      return .submenu(title: title,
                      subtitle: value.map(String.init) ?? anyTitle,
                      children: [option("\(prefix).\(any)", anyTitle, value == nil)]
                        + yearChoices(ends: ends).map { option("\(prefix).\($0)", "\($0)", value == $0) })
    }
    return [bound("from", "Years_From".localized, filter.yearFrom, ends: false),
            bound("to", "Years_To".localized, filter.yearTo, ends: true)]
  }

  // MARK: Filters

  private static let ratingSteps = [5, 6, 7, 8, 9]

  private static func ratingSummary(_ min: Double?, _ max: Double?) -> String? {
    switch (min.map { Int($0) }, max.map { Int($0) }) {
    case let (lo?, hi?): return "\(lo)–\(hi)"
    case let (lo?, nil): return "\(lo)+"
    case let (nil, hi?): return "≤\(hi)"
    default: return nil
    }
  }

  /// Ratings (Kinopoisk and IMDb, each from–to) and quality as submenus; AC3, no
  /// adverts and — when an episodic type is on — "finished only" as checkmarks in the
  /// list itself; Reset last.
  private static func facetNodes(_ filter: LibraryFilter, episodic: Bool) -> [TVPageChip.MenuNode] {
    let unset = "Doesn't Matter".localized
    func range(_ prefix: String, _ title: String, _ min: Double?, _ max: Double?) -> TVPageChip.MenuNode {
      func side(_ edge: String, _ sideTitle: String, _ value: Double?) -> TVPageChip.MenuNode {
        .section(title: sideTitle,
                 children: [option("\(prefix).\(edge).\(any)", unset, value == nil)]
                   + ratingSteps.map { option("\(prefix).\(edge).\($0)", "\($0)", value.map(Int.init) == $0) })
      }
      return .submenu(title: title, subtitle: ratingSummary(min, max) ?? unset,
                      children: [side("min", "Range_From".localized, min), side("max", "Range_To".localized, max)])
    }
    let kp = ratingSummary(filter.kinopoiskMin, filter.kinopoiskMax)
    let imdb = ratingSummary(filter.imdbMin, filter.imdbMax)
    let ratingsSubtitle = [kp.map { "\("Filter_KP_Short".localized) \($0)" }, imdb.map { "IMDb \($0)" }].compactMap { $0 }.joined(separator: " · ")
    let ratings = TVPageChip.MenuNode.submenu(
      title: "Ratings".localized,
      subtitle: ratingsSubtitle.isEmpty ? unset : ratingsSubtitle,
      children: [range("kp", "Filter_Kinopoisk".localized, filter.kinopoiskMin, filter.kinopoiskMax),
                 range("imdb", "IMDb".localized, filter.imdbMin, filter.imdbMax)]
    )
    let quality = TVPageChip.MenuNode.submenu(
      title: "Quality".localized,
      subtitle: filter.minimumQuality.map { String(format: "%@ and up".localized, $0.title) } ?? unset,
      children: [option("q.\(any)", unset, filter.minimumQuality == nil)]
        + [VideoQuality.hd720, .fullHD1080, .uhd4K].map {
          option("q.\($0.rawValue)", String(format: "%@ and up".localized, $0.title), filter.minimumQuality == $0)
        }
    )
    var toggles: [TVPageChip.MenuNode] = [
      option("ac3", "AC3 Audio".localized, filter.wantAC3),
      option("noads", "No Adverts".localized, filter.withoutAdverts)
    ]
    if episodic {
      toggles.append(option("finished", "Finished Only".localized, filter.finishedOnly))
    }
    var nodes: [TVPageChip.MenuNode] = [ratings, quality, .section(title: nil, children: toggles)]
    if filter.hasActiveFilters {
      nodes.append(.section(title: nil, children: [
        .option(.init(id: reset, title: "Reset Filters".localized, isDestructive: true), isSelected: false)
      ]))
    }
    return nodes
  }

  // MARK: Picks

  @MainActor
  static func apply(chip: String, option: String, to catalog: LibraryCatalog, searching: Bool) {
    let isAny = option == any
    switch chip {
    case type:
      catalog.update { filter in
        var types = selectedTypes(filter)
        if isAny {
          types = Set(MediaType.allCases)
        } else if let picked = MediaType(rawValue: option) {
          if types.contains(picked) { types.remove(picked) } else { types.insert(picked) }
          // The last type cannot go: nothing selected is not a search.
          guard !types.isEmpty else { return }
        }
        filter.contentType = nil
        filter.contentTypes = types.count == MediaType.allCases.count ? [] : types
        // Genres of a set no chosen type uses no longer apply; nor does "finished"
        // without an episodic type.
        let kinds = Set(types.map(\.genreKind))
        let applicable = Set(catalog.genres.filter { $0.kind.map(kinds.contains) ?? true }.map(\.id))
        filter.genreIDs = filter.genreIDs.filter(applicable.contains)
        filter.genreID = nil
        if types.isDisjoint(with: episodic) { filter.finishedOnly = false }
      }
    case genre:
      catalog.update { filter in
        filter.genreID = nil
        guard !isAny, let id = Int(option) else { filter.genreIDs = []; return }
        if let index = filter.genreIDs.firstIndex(of: id) {
          filter.genreIDs.remove(at: index)
        } else {
          filter.genreIDs.append(id)
        }
      }
    case country:
      catalog.update { filter in
        filter.countryID = nil
        guard !isAny, let id = Int(option) else { filter.countryIDs = []; return }
        if filter.countryIDs.contains(id) { filter.countryIDs.remove(id) } else { filter.countryIDs.insert(id) }
      }
    case years:
      let parts = option.split(separator: ".").map(String.init)
      guard parts.count == 2 else { return }
      let value = Int(parts[1])
      catalog.update { filter in
        filter.years = nil
        if parts[0] == "from" { filter.yearFrom = value } else { filter.yearTo = value }
        // A crossed range reads as "that one year".
        if let from = filter.yearFrom, let to = filter.yearTo, from > to {
          if parts[0] == "from" { filter.yearTo = from } else { filter.yearFrom = to }
        }
      }
    case facets:
      applyFacet(option, to: catalog)
    case sort:
      if searching {
        catalog.updateSearchSort(option == relevance ? nil : MediaSortOrder(rawValue: option))
      } else if let order = MediaSortOrder(rawValue: option) {
        catalog.update { $0.sort = order }
      }
    default:
      break
    }
  }

  @MainActor
  private static func applyFacet(_ option: String, to catalog: LibraryCatalog) {
    switch option {
    case reset:
      catalog.clearFilters()
      return
    case "ac3":
      catalog.update { $0.wantAC3.toggle() }
      return
    case "noads":
      catalog.update { $0.withoutAdverts.toggle() }
      return
    case "finished":
      catalog.update { $0.finishedOnly.toggle() }
      return
    default:
      break
    }
    let parts = option.split(separator: ".").map(String.init)
    if parts.count == 2, parts[0] == "q" {
      catalog.update { $0.minimumQuality = Int(parts[1]).flatMap(VideoQuality.init(rawValue:)) }
      return
    }
    // "kp.min.7", "imdb.max.any"
    guard parts.count == 3 else { return }
    let value = Double(parts[2])
    catalog.update { filter in
      switch (parts[0], parts[1]) {
      case ("kp", "min"): filter.kinopoiskMin = value
      case ("kp", "max"): filter.kinopoiskMax = value
      case ("imdb", "min"): filter.imdbMin = value
      case ("imdb", "max"): filter.imdbMax = value
      default: break
      }
      // A crossed range reads as "exactly that".
      if let lo = filter.kinopoiskMin, let hi = filter.kinopoiskMax, lo > hi {
        if parts[1] == "min" { filter.kinopoiskMax = lo } else { filter.kinopoiskMin = hi }
      }
      if let lo = filter.imdbMin, let hi = filter.imdbMax, lo > hi {
        if parts[1] == "min" { filter.imdbMax = lo } else { filter.imdbMin = hi }
      }
    }
  }
}

extension GenreKind {
  var title: String {
    switch self {
    case .movie: "Movies & Series".localized
    case .docu: "Documentary".localized
    case .tvshow: "TV Show".localized
    case .music: "Concert".localized
    }
  }
}
#endif

/// Recent queries, newest first, on this device only. The system keeps no search
/// history of its own; HIG asks for recents among the suggestions and for a way to
/// clear them (Settings › Storage clears `UserDefaults` too — a dedicated control is
/// still to do).
enum SearchHistory {
  private static let key = "search.recentQueries"
  private static let limit = 8

  static var recent: [String] {
    UserDefaults.standard.stringArray(forKey: key) ?? []
  }

  static func record(_ query: String) {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.count >= 2 else { return }
    var list = recent.filter { $0.caseInsensitiveCompare(trimmed) != .orderedSame }
    list.insert(trimmed, at: 0)
    UserDefaults.standard.set(Array(list.prefix(limit)), forKey: key)
  }

  static func clear() {
    UserDefaults.standard.removeObject(forKey: key)
  }
}

private extension MediaCard {
  /// Title or original title contains the query, ignoring case and diacritics
  /// ("ё" finds "е", "Вильнев" finds "Вильнёв").
  func matchesSearch(_ query: String) -> Bool {
    let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
    if title.range(of: query, options: options) != nil { return true }
    if let subtitle, subtitle.range(of: query, options: options) != nil { return true }
    return false
  }
}

/// What an empty search field offers before anything has been typed.
///
/// Recents can only answer once there *are* recents, so a first-run field had nothing
/// to say until the user guessed a query and pressed Return. These are examples, not
/// analytics: `/v1/items/search` matches `title`, `director` and `cast`, so a name is
/// as good a starting point as a title, and each one lands on a real, populated page.
enum SearchStarters {
  static let queries: [String] = [
    "Нолан",
    "Тарантино",
    "Вильнёв",
    "Киану Ривз",
    "Дюна",
    "Во все тяжкие"
  ]
}

struct SearchView_Previews: PreviewProvider {
  @StateObject static var navState = NavigationState()

  static var previews: some View {
    SearchView(catalog: LibraryCatalog(itemsService: VideoContentServiceMock(),
                                       authState: AuthState(authService: AuthorizationServiceMock(),
                                                            accessTokenService: AccessTokenServiceMock()),
                                       errorHandler: ErrorHandler()))
    .environmentObject(navState)
  }
}
