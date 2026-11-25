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
/// TMDB `combined_credits` fill titles Kinopub does not carry (dimmed «Not on Kinopub»).
/// Catalog queries use `MediaPerson.catalogNames` / `also_known_as`, not display
/// localization alone — see `internal/actor-filmography-search.md`.
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
    .background(Color.KinoPub.background)
#if os(macOS)
    // The header spells the name out in large type already: no second large title.
    .macPageTitle(Text(resolvedPerson.name), isBlank: true)
#else
    .platformNavigationTitle(resolvedPerson.name)
#endif
#if !os(tvOS)
    .toolbar { LibraryFiltersToolbar(catalog: catalog, showingFilters: $showingFilters) }
    .catalogGridChrome()
    .sheet(isPresented: $showingFilters) {
      LibraryFilterSheet(catalog: catalog)
#if os(macOS)
        .frame(minWidth: 420, minHeight: 560)
#endif
    }
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
    .mediaCardNewFolderAlert(cardMenu)
  }

#if !os(tvOS)
  private var showsEmptyMessage: Bool {
    !catalog.isLoading && !catalog.loadFailed
      && catalog.items.isEmpty && externalCards.isEmpty
  }
#endif

  @ViewBuilder
  private var catalogBody: some View {
#if os(tvOS)
    tvCatalog
      .ignoresSafeArea(.container, edges: [.horizontal, .bottom])
#else
    ContentItemsListView(
      items: $catalog.items,
      onLoadMoreContent: { catalog.loadMoreContent(after: $0) },
      navigationLinkProvider: { linkProvider.link(for: $0) },
      contextMenuProvider: { item in
        MediaCardContextMenus.entries(
          for: item,
          menu: cardMenu,
          pushRoute: { navigationState.push($0) },
          openURL: { openURL($0) }
        )
      },
      emptyMessage: showsEmptyMessage ? "No Results" : nil,
      pagination: catalog.paginationState,
      onRetryPagination: { catalog.retryPagination() }
    ) {
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
      }
      if !externalCards.isEmpty {
        externalCreditsSection
      }
    }
#endif
  }

#if os(tvOS)
  private var tvCatalog: some View {
    TVPage(
      sections: tvSections,
      status: tvStatus,
      accessibilityID: "kinopub.page.person",
      onSelect: { _, item in
        guard let card = item.card else { return }
        // TMDB-only titles have no Kinopub id — Select does nothing.
        guard card.unavailableNotice == nil,
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

  /// Header, then sort and the type pull-down, then the credits grid. The header is
  /// one focus stop (biography opens when it is focused). Entry focus is the first
  /// poster. Default sort is year descending.
  private var tvSections: [TVPageSection] {
    let header = TVPageSection.masthead(id: "person-header", personMasthead)
    let controls = TVSearchFilters.controls(catalog: catalog, includeType: true)
    let creditsTitle = resolvedPerson.role == .actor ? "Acting".localized : "Directing".localized
    let kinopubCards = catalog.items.map { MediaCard($0) }
    let cards = kinopubCards + externalCards
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
          .foregroundStyle(Color.KinoPub.text)

        Text(resolvedPerson.role.titleKey.localized)
          .font(Self.roleFont)
          .foregroundStyle(Color.KinoPub.subtitle)

        if let metaLine = metaLine, !metaLine.isEmpty {
          Text(metaLine)
            .font(Self.metaFont)
            .foregroundStyle(Color.KinoPub.subtitle)
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
        .foregroundStyle(Color.KinoPub.subtitle)
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

  /// The credits are the same `/v1/items` listing as Search narrowed to one name, so
  /// they carry the search catalog's full filter bar — sort, type, genre, country,
  /// years — not a sort menu alone.
  private var creditsHeader: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .firstTextBaseline, spacing: Self.heroSpacing) {
        SectionHeader(
          "Credits",
          count: catalog.items.isEmpty ? nil : "\(catalog.items.count)"
        )

        Spacer(minLength: Self.heroSpacing)
      }
      .padding(.horizontal, gridInset)
      .padding(.vertical, Self.verticalPadding)

#if !os(macOS)
      LibraryFiltersBar(catalog: catalog)
#endif
    }
  }

  private var externalCreditsSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SectionHeader("Not on Kinopub", count: "\(externalCards.count)")
        .padding(.horizontal, gridInset)
        .padding(.top, Self.verticalPadding)
      ScrollView(.horizontal, showsIndicators: false) {
        LazyHStack(spacing: 12) {
          ForEach(externalCards) { card in
            MediaCardView(card: card, caption: .always)
              .frame(width: 120)
          }
        }
        .padding(.horizontal, gridInset)
        .padding(.bottom, 8)
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
      rebuildExternalCards()
      return
    }
    let beforeNames = resolvedPerson.queryNames
    let meta = await metadataService.person(id: tmdbId)
    personMetadata = meta
    var extras = meta.alsoKnownAs
    if let canonical = meta.name { extras.insert(canonical, at: 0) }
    let enriched = resolvedPerson.appendingCatalogNames(extras)
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

  private func rebuildExternalCards() {
    externalCards = PersonFilmography.externalCards(
      credits: personMetadata.credits,
      kinopubItems: catalog.items,
      role: resolvedPerson.role
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
