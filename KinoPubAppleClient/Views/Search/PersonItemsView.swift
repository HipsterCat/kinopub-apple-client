//
//  PersonItemsView.swift
//  KinoPubAppleClient
//

import SwiftUI
import KinoPubUI
import KinoPubBackend
import KinoPubMetadata

/// Everything kino.pub has under one name, reached from the credits on an item page.
/// The web client calls this a search with `mode=actor`; it is the same `/v1/items`
/// listing as the library, narrowed to a person. On tvOS the header scrolls with
/// the poster grid: photo, name, role, and room for a biography, then sort and the
/// type pull-down. Elsewhere the same filters sit over the shared list.
///
/// TMDB `combined_credits` fill titles Kinopub does not carry — same chronological
/// grid as the Kinopub listing, with a «Нет на Кинопабе» badge (not a second rail).
/// Matched against the **loaded** Kinopub window only — no page prefetch, no false
/// unavailable for titles that may still appear later. Catalog queries use
/// `MediaPerson.catalogNames` / `also_known_as`, not display localization alone.
struct PersonItemsView: View {

  private let person: MediaPerson
  private let linkProvider: NavigationLinkProvider
  private let metadataService: MetadataService

  @Environment(ErrorHandler.self) var errorHandler
  @Environment(NavigationState.self) var navigationState
#if !os(tvOS)
  @Environment(\.dismiss) private var dismiss
  /// The margin the credits grid below actually landed on. Padding this page's hero and
  /// section header by a constant of their own is what put them off the first column.
  @Environment(\.shelfGridInset) private var gridInset
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.mediaGridLayout) private var gridLayout
#endif
  @Environment(\.openURL) private var openURL
  @StateObject private var catalog: LibraryCatalog
  @StateObject private var cardMenu = MediaCardMenuCoordinator()
  @State private var personMetadata = PersonMetadata()
  @State private var externalCards: [MediaCard] = []
  @State private var resolvedPerson: MediaPerson
#if !os(tvOS)
  @State private var bioExpanded = false
  @State private var showingFilters = false
  @State private var containerWidth: CGFloat = 1920
#endif

  init(person: MediaPerson,
       linkProvider: NavigationLinkProvider,
       metadataService: MetadataService,
       catalog: @autoclosure @escaping () -> LibraryCatalog) {
    self.person = person
    self.linkProvider = linkProvider
    self.metadataService = metadataService
    _catalog = StateObject(wrappedValue: catalog())
    _resolvedPerson = State(initialValue: person)
  }

  var body: some View {
    catalogBody
    .background(Color.Piratic.background)
#if os(macOS)
    // The header spells the name out in large type already: no second large title.
    .macPageTitle(Text(resolvedPerson.name), isBlank: true)
#else
    .platformNavigationTitle(resolvedPerson.name)
#endif
#if !os(tvOS)
    .navigationSubtitle(LibraryBrowserSubtitle.text(for: catalog))
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        personOverflowMenu
      }
      // Sort + layout only — Type / Genre / Country / Years are not implemented for
      // person `cast=` / `director=` listings (Sasha, 2026-11-26).
      LibraryFiltersToolbar(catalog: catalog, chrome: .sort, showingFilters: $showingFilters)
    }
    .catalogGridChrome()
#endif
#if !os(tvOS)
    // Loading only — error/empty live *under* the filter bar, not over it.
    .overlay {
      if catalog.isLoading && catalog.items.isEmpty && externalCards.isEmpty {
        LoadingIndicatorView(delay: .milliseconds(700))
      }
    }
#endif
    .animation(.easeInOut(duration: 0.3), value: catalog.isLoading)
    .animation(.easeInOut(duration: 0.3), value: catalog.loadFailed)
    .task {
      cardMenu.bind(errorHandler: errorHandler)
      await catalog.load()
      seedSourceTitle()
      await enrichPersonMetadata()
    }
    .task { await cardMenu.refreshFolders() }
    // Rebuild the TMDB unavailable set whenever the loaded Kinopub window moves —
    // page append, refresh, or filter/sort — never against a stale first page alone.
    .onChange(of: catalog.items.map(\.id)) { _, _ in rebuildExternalCards() }
    .onChange(of: catalog.hasMorePages) { _, _ in rebuildExternalCards() }
    .onChange(of: catalog.isLoading) { _, _ in rebuildExternalCards() }
    .onChange(of: catalog.isLoadingMore) { _, _ in rebuildExternalCards() }
    .mediaCardNewFolderAlert(cardMenu)
  }

#if !os(tvOS)
  private var showsEmptyMessage: Bool {
    !catalog.isLoading && !catalog.loadFailed
      && catalog.items.isEmpty && externalCards.isEmpty
  }
#endif

  /// Kinopub + TMDB-only cards in one year-ordered timeline.
  private var timelineCards: [MediaCard] {
    let descending = catalog.filter.sort != .year || catalog.filter.sortDescending
    return PersonFilmography.mergedTimeline(
      kinopubItems: catalog.items,
      externalCards: externalCards,
      descending: descending,
      images: metadataService.images
    )
  }

  @ViewBuilder
  private var catalogBody: some View {
#if os(tvOS)
    tvCatalog
      .ignoresSafeArea(.container, edges: [.horizontal, .bottom])
#else
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        hero
        creditsHeader
        if catalog.loadFailed && catalog.items.isEmpty {
          UnavailableView(
            title: "Couldn't Load",
            systemImage: "wifi.exclamationmark",
            message: catalog.loadError?.userFacingMessage ?? "Check your connection and try again.".localized,
            retryTitle: "Try Again",
            onRetry: {
              Task { await catalog.refresh() }
            },
            secondaryTitle: "Back",
            onSecondary: { dismiss() }
          )
          .padding(.top, 24)
        } else if showsEmptyMessage {
          UnavailableView(title: "No Results", systemImage: "magnifyingglass")
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
        } else if gridLayout == .list {
          timelineList
        } else {
          timelineGrid
        }
        PaginationFooter(state: catalog.paginationState, onRetry: { catalog.retryPagination() })
      }
    }
    .remembersScroll()
    .environment(\.shelfGridInset, shelfMetrics.gridInset(in: containerWidth))
    .onGeometryChange(for: CGFloat.self) { proxy in
      proxy.size.width
    } action: { width in
      if width > 0 { containerWidth = width }
    }
#endif
  }

#if !os(tvOS)
  private var shelfMetrics: ShelfMetrics {
    .posters(width: containerWidth, typeSize: dynamicTypeSize)
  }

  private var gridColumns: [GridItem] {
    Array(
      repeating: GridItem(.flexible(), spacing: shelfMetrics.gutter, alignment: .top),
      count: shelfMetrics.columns
    )
  }

  private var timelineGrid: some View {
    LazyVGrid(columns: gridColumns, spacing: shelfMetrics.gutter) {
      ForEach(timelineCards) { card in
        timelineCell(card)
      }
    }
    .safeAreaPadding(.horizontal, shelfMetrics.gridInset(in: containerWidth))
    .padding(.vertical, 8)
  }

  private var timelineList: some View {
    LazyVStack(alignment: .leading, spacing: 0) {
      ForEach(timelineCards) { card in
        timelineCell(card, listRow: true)
        Divider().opacity(0.35)
      }
    }
    .safeAreaPadding(.horizontal, shelfMetrics.gridInset(in: containerWidth))
    .padding(.vertical, 8)
  }

  @ViewBuilder
  private func timelineCell(_ card: MediaCard, listRow: Bool = false) -> some View {
    let kinopubItem = catalog.items.first { $0.id == card.itemID }
    if let kinopubItem {
      NavigationLink(value: linkProvider.link(for: kinopubItem)) {
        timelineLabel(card, listRow: listRow)
          .onAppear { catalog.loadMoreContent(after: kinopubItem) }
      }
      .modifier(TimelineCardButtonStyle(listRow: listRow))
      .modifier(MediaCardContextMenuModifier(
        isEnabled: true,
        entriesProvider: {
          MediaCardContextMenus.entries(
            for: kinopubItem,
            menu: cardMenu,
            pushRoute: { navigationState.push($0) },
            openURL: { openURL($0) }
          )
        },
        previewCard: card,
        previewSurface: .shelf
      ))
    } else {
      // TMDB-only — no Kinopub detail to open.
      timelineLabel(card, listRow: listRow)
        .onAppear {
          guard let last = catalog.items.last,
                timelineCards.suffix(6).contains(where: { $0.id == card.id }) else { return }
          catalog.loadMoreContent(after: last)
        }
    }
  }

  @ViewBuilder
  private func timelineLabel(_ card: MediaCard, listRow: Bool) -> some View {
    if listRow {
      CatalogMediaRow(card: card)
    } else {
      MediaCardView(card: card, caption: .always)
    }
  }
#endif

#if os(tvOS)
  private var tvCatalog: some View {
    TVPage(
      sections: tvSections,
      status: tvStatus,
      accessibilityID: "kinopub.page.person",
      onSelect: { _, item in
        guard let card = item.card,
              let media = catalog.items.first(where: { $0.id == card.itemID }),
              let route = linkProvider.link(for: media) as? Route else { return }
        navigationState.push(route)
      },
      onChipOption: { chip, option in
        TVSearchFilters.apply(chip: chip, option: option, to: catalog)
      },
      onChipSelection: { chip, selection in
        TVSearchFilters.applySelection(chip: chip, selection: selection, to: catalog)
      },
      onNearEnd: { section in
        guard section.id == "credits", let last = catalog.items.last else { return }
        catalog.loadMoreContent(after: last)
      },
      contextMenuProvider: { card in
        guard card.unavailableNotice == nil else { return [] }
        return MediaCardContextMenus.entries(
          for: card,
          surface: .shelf,
          menu: cardMenu,
          pushRoute: { navigationState.push($0) },
          openURL: { openURL($0) }
        )
      },
      onRetry: { Task { await catalog.refresh() } },
      prefersFirstPosterFocus: true
    )
  }

  /// Header, then sort and the type pull-down, then **one** chronological credits grid
  /// (Kinopub + TMDB-only interleaved by year — no second rail).
  private var tvSections: [TVPageSection] {
    let header = TVPageSection.masthead(id: "person-header", personMasthead)
    // Sort only — Type chip is not implemented for person listings (Sasha, 2026-11-26).
  let controls = TVSearchFilters.controls(catalog: catalog, includeType: false)
    let creditsTitle = resolvedPerson.role == .actor ? "Acting".localized : "Directing".localized
    let cards = timelineCards
    if cards.isEmpty && catalog.isLoading {
      return [header, controls, .placeholder(id: "credits", title: creditsTitle, kind: .poster, columns: 6, flow: .grid)]
    }
    guard !cards.isEmpty else { return [header, controls] }
    return [header, controls, .posters(id: "credits", title: creditsTitle, flow: .grid, caption: .always,
                                       loadsMore: catalog.hasMorePages, cards: cards)]
  }

  private var personMasthead: TVPageMasthead {
    let photoURL = resolvedPerson.photoURL
      ?? personMetadata.photo
      ?? ActorImageProvider.photoURL(for: resolvedPerson.name)
    return TVPageMasthead(style: .person,
                          title: resolvedPerson.name,
                          detail: personDetail,
                          biography: biography,
                          photoURL: photoURL)
  }

  /// Role, then place and birthday when metadata has them. The biography is its own
  /// line under this, so this stays one short line.
  private var personDetail: String {
    var parts = [resolvedPerson.role.titleKey.localized]
    if let metaLine, !metaLine.isEmpty { parts.append(metaLine) }
    return parts.joined(separator: "  ")
  }

  private var tvStatus: TVPageStatus {
    // Keep status for true empty/error with chrome still showing — TVPage pins it
    // below masthead + chips so filters stay reachable.
    if catalog.items.isEmpty && externalCards.isEmpty && catalog.loadFailed {
      return .failed(message: catalog.loadError?.userFacingMessage
                       ?? "Check your connection and try again.".localized,
                     retryTitle: "Try Again".localized)
    }
    if catalog.items.isEmpty && externalCards.isEmpty && !catalog.isLoading {
      return .message((catalog.filter.hasActiveFilters
                       ? "Nothing Matches These Filters"
                       : "No Results").localized)
    }
    return .content
  }
#endif

#if !os(tvOS)
  // MARK: - Hero

  private var hero: some View {
    HStack(alignment: .top, spacing: Self.heroSpacing) {
      // Prefer the rail URL already on screen — upgrading w185 → w342 only
      // swaps the cache key and blinks the avatar for a sharper copy.
      let photoURL = resolvedPerson.photoURL
        ?? personMetadata.photo
        ?? ActorImageProvider.photoURL(for: resolvedPerson.name)
      CastAvatarView(name: resolvedPerson.name, photoURL: photoURL)

      VStack(alignment: .leading, spacing: 8) {
        Text(resolvedPerson.name)
          .font(Self.nameFont)
          .foregroundStyle(Color.Piratic.text)

        Text(resolvedPerson.role.titleKey.localized)
          .font(Self.roleFont)
          .foregroundStyle(Color.Piratic.subtitle)

        if let metaLine = metaLine, !metaLine.isEmpty {
          Text(metaLine)
            .font(Self.metaFont)
            .foregroundStyle(Color.Piratic.subtitle)
        }

        if let biography, !biography.isEmpty {
          bioBlock(biography)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(.horizontal, gridInset)
    .padding(.top, Self.verticalPadding)
    .padding(.bottom, 8)
  }

  @ViewBuilder
  private func bioBlock(_ text: String) -> some View {
    let truncated = text.count > Self.bioPreviewLimit && !bioExpanded
    VStack(alignment: .leading, spacing: 4) {
      Text(truncated ? String(text.prefix(Self.bioPreviewLimit)) + "…" : text)
        .font(Self.bioFont)
        .foregroundStyle(Color.Piratic.subtitle)
        .fixedSize(horizontal: false, vertical: true)

      if text.count > Self.bioPreviewLimit {
        Button(bioExpanded ? "Less" : "More") {
          withAnimation(.easeOut(duration: 0.2)) {
            bioExpanded.toggle()
          }
        }
        .font(Self.bioFont.weight(.semibold))
      }
    }
  }

  // MARK: - Credits row

  /// Sort chips only — person listings do not implement Type / Genre / Country / Years.
  private var creditsHeader: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .firstTextBaseline, spacing: Self.heroSpacing) {
        SectionHeader(
          "Credits",
          count: timelineCards.isEmpty ? nil : "\(timelineCards.count)"
        )

        Spacer(minLength: Self.heroSpacing)
      }
      .padding(.horizontal, gridInset)
      .padding(.vertical, Self.verticalPadding)

#if !os(macOS)
      LibraryFiltersBar(catalog: catalog, chrome: .sort)
#endif
    }
  }

  /// Open this person on Kinopoisk / TMDB — same «…» affordance as the title page.
  @ViewBuilder
  private var personOverflowMenu: some View {
    let links = personExternalLinks
    if !links.isEmpty {
      Menu {
        ForEach(links, id: \.name) { link in
          Button(String(format: "Open %@".localized, link.name)) {
            openURL(link.url)
          }
        }
      } label: {
        Label("More", systemImage: "ellipsis")
      }
#if os(macOS)
      .menuIndicator(.hidden)
      .help("More")
#endif
    }
  }

  /// TMDB when we have an id; Kinopoisk via name search until `staffId` lands on
  /// `MediaPerson` (KinopoiskSource note — deliberately deferred).
  private var personExternalLinks: [(name: String, url: URL)] {
    var links: [(name: String, url: URL)] = []
    let queryName = LocalePreferredText.preferRuEn(
      [resolvedPerson.name] + resolvedPerson.catalogNames
    ) ?? resolvedPerson.name
    if var components = URLComponents(string: "https://www.kinopoisk.ru/index.php") {
      components.queryItems = [URLQueryItem(name: "kp_query", value: queryName)]
      if let url = components.url {
        links.append((ExternalLink.Site.kinopoisk.name, url))
      }
    }
    if let id = resolvedPerson.tmdbPersonId,
       let url = URL(string: "https://www.themoviedb.org/person/\(id)") {
      links.append(("TMDB", url))
    }
    return links
  }
#endif

#if !os(tvOS)
  /// Poster vs list button chrome for the shared filmography timeline.
  private struct TimelineCardButtonStyle: ViewModifier {
    let listRow: Bool
    @ViewBuilder
    func body(content: Content) -> some View {
      if listRow {
        content.buttonStyle(.plain)
      } else {
        content.buttonStyle(MediaCardButtonStyle())
      }
    }
  }
#endif

  private var biography: String? {
    personMetadata.biography.flatMap { $0.isEmpty ? nil : $0 }
  }

  private var metaLine: String? {
    var parts: [String] = []
    if let birthday = personMetadata.birthday {
      parts.append(Self.birthdayFormatter.string(from: birthday))
    }
    if let place = personMetadata.placeOfBirth, !place.isEmpty {
      parts.append(place)
    }
    return parts.isEmpty ? nil : parts.joined(separator: " · ")
  }

  private static let birthdayFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .none
    return formatter
  }()

  /// Put the title the viewer navigated from at the front of the filmography when
  /// `cast=` spelling missed it.
  private func seedSourceTitle() {
    guard let id = resolvedPerson.sourceItemID,
          let item = ListedItemCache.shared.item(id: id) else { return }
    catalog.ensureSeedItem(item)
  }

  /// TMDB bio + also_known_as (retry Kinopub queries) + combined_credits (external cards).
  private func enrichPersonMetadata() async {
    guard let tmdbId = resolvedPerson.tmdbPersonId else {
      // Still demote a Hangul/CJK-only display name when catalog spellings have RU/EN.
      if let preferred = LocalePreferredText.preferRuEn(
        [resolvedPerson.name] + resolvedPerson.catalogNames
      ), preferred != resolvedPerson.name {
        resolvedPerson = resolvedPerson.withDisplayName(preferred)
      }
      rebuildExternalCards()
      return
    }
    let beforeNames = resolvedPerson.queryNames
    let meta = await metadataService.person(id: tmdbId)
    personMetadata = meta
    var extras = meta.alsoKnownAs
    if let canonical = meta.name { extras.insert(canonical, at: 0) }
    var enriched = resolvedPerson.appendingCatalogNames(extras)
    // Display: RU then EN — never leave Hangul/CJK first when a RU/EN form exists.
    if let preferred = LocalePreferredText.preferRuEn(
      [enriched.name, meta.name].compactMap { $0 } + meta.alsoKnownAs + enriched.catalogNames
    ) {
      enriched = enriched.withDisplayName(preferred)
    }
    resolvedPerson = enriched
    // Empty or thin Kinopub result with new spellings — try again with also_known_as.
    let gainedNames = enriched.queryNames.contains { !beforeNames.map { $0.lowercased() }.contains($0.lowercased()) }
    if gainedNames, catalog.items.isEmpty || catalog.items.count < 2 {
      var next = catalog.filter
      next.person = enriched
      catalog.filter = next
      await catalog.refresh()
      seedSourceTitle()
    }
    rebuildExternalCards()
  }

  /// Kinopub listing has nowhere further to go — safe to treat remaining TMDB credits
  /// outside the year window as unavailable too.
  private var kinopubListingComplete: Bool {
    !catalog.isLoading && !catalog.isLoadingMore && !catalog.hasMorePages
  }

  private func rebuildExternalCards() {
    let complete = kinopubListingComplete
    let window: PersonFilmography.MatchWindow
    if catalog.filter.sort == .year {
      window = .yearSorted(items: catalog.items,
                           complete: complete,
                           descending: catalog.filter.sortDescending)
    } else {
      window = .completeOnly(complete)
    }
    externalCards = PersonFilmography.externalCards(
      credits: personMetadata.credits,
      kinopubItems: catalog.items,
      role: resolvedPerson.role,
      window: window
    )
  }

  /// Built the same way from every navigation stack; only the routes differ.
  static func make(person: MediaPerson,
                   linkProvider: NavigationLinkProvider,
                   context: AppContextProtocol,
                   authState: AuthState,
                   errorHandler: ErrorHandler) -> PersonItemsView {
    PersonItemsView(person: person,
                    linkProvider: linkProvider,
                    metadataService: context.metadataService,
                    catalog: LibraryCatalog(itemsService: context.contentService,
                                            authState: authState,
                                            errorHandler: errorHandler,
                                            filter: LibraryFilter(sort: .year, person: person)))
  }

#if !os(tvOS)
  static let heroSpacing: CGFloat = 16
  static let verticalPadding: CGFloat = 8
  static let bioPreviewLimit = 160
  static let nameFont: Font = .system(size: 24, weight: .bold)
  static let roleFont: Font = .system(size: 14, weight: .regular)
  static let metaFont: Font = .system(size: 13, weight: .regular)
  static let bioFont: Font = .system(size: 14, weight: .regular)
  static let sectionFont: Font = .system(size: 17, weight: .semibold)
#endif
}
