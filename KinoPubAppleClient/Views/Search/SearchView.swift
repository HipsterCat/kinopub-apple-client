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
  @Environment(\.scenePhase) private var scenePhase
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
          case .chip(let chip) where chip.id == TVSearchFilters.clear:
            catalog.clearFilters()
          case .chip, .placeholder:
            break
          }
        },
        onChipOption: { chip, option in
          TVSearchFilters.apply(chip: chip, option: option, to: catalog)
        },
        onChipSelection: { chip, selection in
          TVSearchFilters.applySelection(chip: chip, selection: selection, to: catalog)
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
      // Typed text lives for one visit: coming back to the app is the library again —
      // its filters and sort kept, the query gone (recents keep it one press away).
      .onChange(of: scenePhase) { _, phase in
        if phase == .background { searchFieldText = "" }
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
          !catalog.filter.hasActiveFilters else { return server }
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
    if empty && !catalog.isLoading {
      if catalog.filter.hasActiveFilters { return .message("Nothing Matches These Filters".localized) }
      if !trimmedQuery.isEmpty { return .message("No Results".localized) }
    }
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
  /// The round × that clears every filter — first in the row while any is on.
  static let clear = "clear"

  /// The kinds on — empty is "Все".
  static func selectedKinds(_ filter: LibraryFilter) -> Set<CatalogKind> { filter.kinds }

  /// A genre's filter name — the plural ("Военные", "Вестерны") where there is one.
  static func genreTitle(_ genre: MediaGenre) -> String {
    let key = "Genre_\(genre.id)"
    let plural = key.localized
    return plural == key ? genre.title : plural
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
    let kinds = selectedKinds(filter)
    let genreAxis = kinds.contains { $0.axis == .genre }

    // Type — "Все" on top, checked by default (so the menu's checkmark column is there
    // from the start). Types combine freely; below a divider the presets (anime,
    // cartoons, shorts, stand-up) stand alone: a preset is type + genre on the server
    // and cannot be ORed with a type.
    let presets: [CatalogKind] = [.anime, .cartoons, .shorts, .standup]
    let kindOption = { (kind: CatalogKind) in option(kind.rawValue, kind.titleKey.localized, kinds.contains(kind)) }
    let typeChip = TVPageChip(
      id: type,
      title: kindsTitle(kinds),
      menu: .init(nodes: [.section(title: nil, children: [option(any, "All".localized, kinds.isEmpty)]
                                    + CatalogKind.allCases.filter { $0.axis == .type }.map(kindOption)),
                          .section(title: nil, children: presets.map(kindOption))],
                  keepsPresented: true, exclusiveOptionID: any,
                  optionGroups: Dictionary(uniqueKeysWithValues: CatalogKind.allCases.map {
                    ($0.rawValue, $0.axis == .type ? 0 : 1)
                  }),
                  soloGroups: [1]),
      isActive: !kinds.isEmpty
    )

    // Genre — one list, a divider between sets, each set largest first; only the sets
    // the chosen kinds use. Gone while a preset is on: the preset owns the `genre`
    // parameter, and the API has no genre AND (a comma is OR, `genre[]` is a 502).
    let sets = kinds.isEmpty ? Set(GenreKind.allCases) : Set(kinds.flatMap(\.genreKinds))
    let picked = Set(filter.genreIDs)
    let sections = GenreKind.allCases.filter(sets.contains).map { kind in
      GenrePopularity.sorted(catalog.genres.filter { $0.kind == kind })
        .map { option("\($0.id)", genreTitle($0), picked.contains($0.id)) }
    }.filter { !$0.isEmpty }
    let anyGenre = option(any, "Any_Masculine".localized, picked.isEmpty)
    let genreNodes: [TVPageChip.MenuNode] = sections.enumerated().map { index, options in
      .section(title: nil, children: index == 0 ? [anyGenre] + options : options)
    }
    let genreChip = TVPageChip(
      id: genre,
      title: summary(catalog.genres.filter { picked.contains($0.id) }.map(genreTitle), none: "Genre".localized),
      menu: .init(nodes: genreNodes.isEmpty ? [anyGenre] : genreNodes, keepsPresented: true, exclusiveOptionID: any),
      isActive: !picked.isEmpty
    )

    // Country — kino.pub's popularity order, "Любая" first.
    let countries = filter.countryIDs
    let countryChip = TVPageChip(
      id: country,
      title: summary(catalog.countries.filter { countries.contains($0.id) }.map(\.title), none: "Country".localized),
      menu: .init(nodes: [option(any, "Any_Feminine".localized, countries.isEmpty)]
                    + catalog.countries.map { option("\($0.id)", $0.title, countries.contains($0.id)) },
                  keepsPresented: true, exclusiveOptionID: any),
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
      menu: .init(nodes: facetNodes(filter, episodic: kinds.isEmpty || kinds.contains(where: \.isEpisodic))),
      isActive: filter.seriesStatus != nil || filter.minimumQuality != nil
        || filter.kinopoiskMin != nil || filter.kinopoiskMax != nil
        || filter.imdbMin != nil || filter.imdbMax != nil
    )

    // Clearing is one round × at the head of the row, not an entry in each menu.
    var chips: [TVPageChip] = []
    if filter.hasActiveFilters {
      chips.append(TVPageChip(id: clear, title: "Reset Filters".localized, systemImage: "xmark", showsTitle: false))
    }
    chips.append(typeChip)
    if !genreAxis { chips.append(genreChip) }
    chips += [countryChip, yearsChip, facetsChip]
    // Browsing only: a typed query is ranked by the server's relevance, as on the site.
    if !searching {
      chips.append(TVPageChip(
        id: sort,
        title: filter.sort.titleKey.localized,
        systemImage: "arrow.up.arrow.down",
        menu: .init(options: MediaSortOrder.allCases.map { .init(id: $0.rawValue, title: $0.titleKey.localized) },
                    selectedID: filter.sort.rawValue),
        alignment: .trailing
      ))
    }
    return .chips(id: "filters", title: nil, chips: chips)
  }

  /// "Тип", "Фильмы", "Фильмы и сериалы", "Без концертов" (every type but one), or
  /// "Фильмы +2".
  private static func kindsTitle(_ kinds: Set<CatalogKind>) -> String {
    guard !kinds.isEmpty else { return "Type".localized }
    let picked = CatalogKind.allCases.filter(kinds.contains)
    let typeKinds = CatalogKind.allCases.filter { $0.axis == .type }
    if picked.count == typeKinds.count - 1, picked.allSatisfy({ $0.axis == .type }),
       let missing = typeKinds.first(where: { !kinds.contains($0) }) {
      return missing.withoutTitleKey.localized
    }
    if picked.count == 2 {
      return String(format: "%@ and %@".localized, picked[0].titleKey.localized, picked[1].titleKey.localized.lowercased())
    }
    return summary(picked.map { $0.titleKey.localized }, none: "Type".localized)
  }

  // MARK: Years

  private static var currentYear: Int { Calendar.current.component(.year, from: Date()) }
  /// kino.pub's catalogue starts in 1912 — the lower bound, and the default "from".
  private static let firstYear = 1912

  /// Default: 1912 to this year — no condition sent. A bound at its default is `nil`.
  private static func yearsTitle(_ filter: LibraryFilter) -> String {
    switch (filter.yearFrom, filter.yearTo) {
    case let (from?, to?): return from == to ? "\(from)" : "\(from)–\(to)"
    case let (from?, nil): return String(format: "from %lld".localized, from)
    case let (nil, to?): return String(format: "to %lld".localized, to)
    default: return "Filter_Year".localized
    }
  }

  /// "Начиная с ▸" (1912 checked by default, this year first in the list for reach) and
  /// "До ▸" (this year by default). A pick closes the menu and applies at once.
  private static func yearNodes(_ filter: LibraryFilter) -> [TVPageChip.MenuNode] {
    let years = Array((firstYear...currentYear).reversed())
    let from = filter.yearFrom ?? firstYear
    let to = filter.yearTo ?? currentYear
    return [
      .submenu(title: "Years_From".localized, subtitle: "\(from)",
               children: years.map { option("from.\($0)", "\($0)", from == $0) }),
      .submenu(title: "Years_To".localized, subtitle: "\(to)",
               children: years.map { option("to.\($0)", "\($0)", to == $0) })
    ]
  }

  // MARK: Filters

  /// "От" 0…9 up, "До" 10…1 down — the ends of the scale are no bound, so low ratings
  /// are as findable as high ones.
  private static let ratingFloors = Array(0...9)
  private static let ratingCeilings = Array((1...10).reversed())

  /// "5+" (up to the top of the scale) or "7–9".
  private static func ratingRange(_ min: Double?, _ max: Double?) -> String {
    let lo = min.map(Int.init) ?? 0
    let hi = max.map(Int.init) ?? 10
    return hi == 10 ? "\(lo)+" : "\(lo)–\(hi)"
  }

  /// "0+ Кинопоиск, IMDb" while both read the same, else "5+ КП, 7–9 IMDb".
  private static func ratingsSummary(_ filter: LibraryFilter) -> String {
    let kp = ratingRange(filter.kinopoiskMin, filter.kinopoiskMax)
    let imdb = ratingRange(filter.imdbMin, filter.imdbMax)
    return kp == imdb
      ? "\(kp) \("Filter_Kinopoisk".localized), IMDb"
      : "\(kp) \("Filter_KP_Short".localized), \(imdb) IMDb"
  }

  private static let qualities: [VideoQuality] = [.uhd4K, .fullHD1080, .hd720]

  /// "Только 4K", "Full HD 1080p+", "HD 720p+" — each at least that good.
  private static func qualityTitle(_ quality: VideoQuality) -> String {
    switch quality {
    case .uhd4K: "Quality_4K_Only".localized
    case .fullHD1080: "Full HD 1080p+"
    case .hd720: "HD 720p+"
    case .sd480: "SD 480p+"
    }
  }

  /// Ratings (Kinopoisk and IMDb, each from–to) and quality as submenus with their
  /// value as the second line; "finished only" as a checkmark while an episodic type
  /// is on. No dividers, no reset entry — the row's × clears.
  private static func facetNodes(_ filter: LibraryFilter, episodic: Bool) -> [TVPageChip.MenuNode] {
    func range(_ prefix: String, _ name: String, _ min: Double?, _ max: Double?) -> TVPageChip.MenuNode {
      let lo = min.map(Int.init) ?? 0
      let hi = max.map(Int.init) ?? 10
      return .submenu(title: name, subtitle: String(format: "Filter_Range %lld %lld".localized, lo, hi), children: [
        .section(title: "Range_From".localized,
                 children: ratingFloors.map { option("\(prefix).min.\($0)", "\($0)", lo == $0) }),
        .section(title: "Range_To".localized,
                 children: ratingCeilings.map { option("\(prefix).max.\($0)", "\($0)", hi == $0) })
      ])
    }
    let ratings = TVPageChip.MenuNode.submenu(
      title: "Filter_Ratings".localized,
      subtitle: ratingsSummary(filter),
      children: [range("kp", "Filter_Kinopoisk".localized, filter.kinopoiskMin, filter.kinopoiskMax),
                 range("imdb", "IMDb", filter.imdbMin, filter.imdbMax)]
    )
    // No default: nothing checked is any quality; picking the checked one clears it.
    let quality = TVPageChip.MenuNode.submenu(
      title: "Quality".localized,
      subtitle: filter.minimumQuality.map(qualityTitle),
      children: qualities.map { option("q.\($0.rawValue)", qualityTitle($0), filter.minimumQuality == $0) }
    )
    // Only what the server filters: no AC3 / adverts facets (the API ignores both; a
    // client-side filter breaks paging), "finished only" while an episodic type is on.
    var nodes: [TVPageChip.MenuNode] = [ratings, quality]
    // Статус ▸ В эфире / Окончен — one pick, undone by picking it again; no default
    // (nothing sent is any status).
    if episodic {
      nodes.append(.submenu(title: "Filter_Status".localized,
                            subtitle: filter.seriesStatus?.titleKey.localized,
                            children: SeriesStatus.allCases.map {
                              option("status.\($0.rawValue)", $0.titleKey.localized, filter.seriesStatus == $0)
                            }))
    }
    return nodes
  }

  // MARK: Picks

  @MainActor
  static func apply(chip: String, option: String, to catalog: LibraryCatalog) {
    // Type, genre and country are multi-selects: they arrive whole, through
    // `applySelection`, when their menu closes.
    switch chip {
    case years:
      let parts = option.split(separator: ".").map(String.init)
      guard parts.count == 2 else { return }
      guard let picked = Int(parts[1]) else { return }
      catalog.update { filter in
        filter.years = nil
        // A bound at its default (1912 / this year) is no condition at all.
        if parts[0] == "from" {
          filter.yearFrom = picked == firstYear ? nil : picked
        } else {
          filter.yearTo = picked == currentYear ? nil : picked
        }
        // A crossed range reads as "that one year".
        if let from = filter.yearFrom, let to = filter.yearTo, from > to {
          if parts[0] == "from" { filter.yearTo = from } else { filter.yearFrom = to }
        }
      }
    case facets:
      applyFacet(option, to: catalog)
    case sort:
      if let order = MediaSortOrder(rawValue: option) {
        catalog.update { $0.sort = order }
      }
    default:
      break
    }
  }

  /// A multi-select menu closed: its whole selection at once.
  @MainActor
  static func applySelection(chip: String, selection: Set<String>, to catalog: LibraryCatalog) {
    let everything = selection.contains(any) || selection.isEmpty
    switch chip {
    case type:
      catalog.update { filter in
        let kinds = everything ? [] : Set(selection.compactMap(CatalogKind.init(rawValue:)))
        filter.kinds = kinds
        filter.contentType = nil
        filter.contentTypes = []
        // Genres of a set no chosen kind uses no longer apply; nor does "finished"
        // without an episodic kind.
        let sets = kinds.isEmpty ? Set(GenreKind.allCases) : Set(kinds.flatMap(\.genreKinds))
        let applicable = Set(catalog.genres.filter { $0.kind.map(sets.contains) ?? true }.map(\.id))
        // A preset owns the `genre` parameter — its genre chip is gone, and so are picks.
        filter.genreIDs = kinds.contains { $0.axis == .genre } ? [] : filter.genreIDs.filter(applicable.contains)
        filter.genreID = nil
        if !kinds.isEmpty, !kinds.contains(where: \.isEpisodic) { filter.seriesStatus = nil }
      }
    case genre:
      catalog.update { filter in
        filter.genreID = nil
        filter.genreIDs = everything ? [] : selection.compactMap(Int.init).sorted()
      }
    case country:
      catalog.update { filter in
        filter.countryID = nil
        filter.countryIDs = everything ? [] : Set(selection.compactMap(Int.init))
      }
    default:
      break
    }
  }

  @MainActor
  private static func applyFacet(_ option: String, to catalog: LibraryCatalog) {
    let parts = option.split(separator: ".").map(String.init)
    if parts.count == 2, parts[0] == "status" {
      let picked = Int(parts[1]).flatMap(SeriesStatus.init(rawValue:))
      catalog.update { $0.seriesStatus = $0.seriesStatus == picked ? nil : picked }
      return
    }
    if parts.count == 2, parts[0] == "q" {
      let picked = Int(parts[1]).flatMap(VideoQuality.init(rawValue:))
      catalog.update { $0.minimumQuality = $0.minimumQuality == picked ? nil : picked }
      return
    }
    // "kp.min.7", "imdb.max.any"
    guard parts.count == 3, let number = Double(parts[2]) else { return }
    // The ends of the scale are no bound at all.
    let value: Double? = (parts[1] == "min" && number <= 0) || (parts[1] == "max" && number >= 10) ? nil : number
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

extension SeriesStatus {
  var titleKey: String {
    switch self {
    case .airing: "Status_Airing"
    case .finished: "Status_Finished"
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
