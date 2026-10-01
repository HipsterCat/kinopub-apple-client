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
/// listing as the library, narrowed to a person. On tvOS it is the search catalog:
/// `TVSearchFilters` and the poster grid. Elsewhere the same filters sit over the
/// shared list, under the person's photo and bio.
struct PersonItemsView: View {

  private let person: MediaPerson
  private let linkProvider: NavigationLinkProvider
#if !os(tvOS)
  private let metadataService: MetadataService
#endif

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
#if !os(tvOS)
  @State private var personMetadata = PersonMetadata()
  @State private var bioExpanded = false
#endif

  init(person: MediaPerson,
       linkProvider: NavigationLinkProvider,
       metadataService: MetadataService,
       catalog: @autoclosure @escaping () -> LibraryCatalog) {
    self.person = person
    self.linkProvider = linkProvider
#if os(tvOS)
    // The photo and bio stay on iOS and macOS. tvOS is the search catalog.
    _ = metadataService
#else
    self.metadataService = metadataService
#endif
    _catalog = StateObject(wrappedValue: catalog())
  }

  var body: some View {
    catalogBody
    .background(Color.KinoPub.background)
    .platformNavigationTitle(person.name)
    .overlay {
#if !os(tvOS)
      if catalog.loadFailed {
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
      } else if catalog.isLoading && catalog.items.isEmpty {
        LoadingIndicatorView(delay: .milliseconds(700))
      }
#endif
    }
    .animation(.easeInOut(duration: 0.3), value: catalog.isLoading)
    .animation(.easeInOut(duration: 0.3), value: catalog.loadFailed)
    .task {
      cardMenu.bind(errorHandler: errorHandler)
      await catalog.load()
    }
    .task { await cardMenu.refreshFolders() }
    .mediaCardNewFolderAlert(cardMenu)
#if !os(tvOS)
    .task(id: person.tmdbPersonId) {
      guard let id = person.tmdbPersonId else { return }
      personMetadata = await metadataService.person(id: id)
    }
#endif
  }

#if !os(tvOS)
  private var showsEmptyMessage: Bool {
    !catalog.isLoading && !catalog.loadFailed && catalog.items.isEmpty
  }
#endif

  @ViewBuilder
  private var catalogBody: some View {
#if os(tvOS)
    // The photo stays; the catalog under it is search's — pull-down chips, poster grid.
    VStack(alignment: .leading, spacing: 0) {
      personHeader
      tvCatalog
    }
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
    }
#endif
  }

#if os(tvOS)
  /// The face from the cast rail, beside the name. Not a focus stop — the catalog below
  /// is the page.
  private var personHeader: some View {
    HStack(alignment: .center, spacing: 28) {
      TVUIKitPersonAvatar(name: person.name,
                          photoURL: person.photoURL ?? ActorImageProvider.photoURL(for: person.name),
                          diameter: 220)
        .frame(width: 220, height: 220)
      VStack(alignment: .leading, spacing: 8) {
        Text(person.name)
          .font(.title)
          .foregroundStyle(Color.KinoPub.text)
        Text(person.role.titleKey.localized)
          .font(.title3)
          .foregroundStyle(Color.KinoPub.subtitle)
      }
    }
    .padding(.horizontal, TVHIGGrid.sideInset)
    .padding(.top, 16)
    .padding(.bottom, 8)
    .accessibilityElement(children: .combine)
  }

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
        MediaCardContextMenus.entries(
          for: card,
          surface: .shelf,
          menu: cardMenu,
          pushRoute: { navigationState.push($0) },
          openURL: { openURL($0) }
        )
      },
      onRetry: { Task { await catalog.refresh() } }
    )
  }

  private var tvSections: [TVPageSection] {
    let filters = TVSearchFilters.row(catalog: catalog, searching: false)
    if catalog.items.isEmpty && catalog.isLoading {
      return [filters, .placeholder(id: "credits", title: nil, kind: .poster, columns: 6, flow: .grid)]
    }
    let cards = catalog.items.map { MediaCard($0) }
    guard !cards.isEmpty else { return [filters] }
    return [filters, .posters(id: "credits", title: nil, flow: .grid, caption: .always,
                              loadsMore: catalog.hasMorePages, cards: cards)]
  }

  private var tvStatus: TVPageStatus {
    if catalog.items.isEmpty && catalog.loadFailed {
      return .failed(message: catalog.loadError?.userFacingMessage
                       ?? "Check your connection and try again.".localized,
                     retryTitle: "Try Again".localized)
    }
    if catalog.items.isEmpty && !catalog.isLoading {
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
      let photoURL = person.photoURL
        ?? personMetadata.photo
        ?? ActorImageProvider.photoURL(for: person.name)
      CastAvatarView(name: person.name, photoURL: photoURL)

      VStack(alignment: .leading, spacing: 8) {
        Text(person.name)
          .font(Self.nameFont)
          .foregroundStyle(Color.KinoPub.text)

        Text(person.role.titleKey.localized)
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

      LibraryFiltersBar(catalog: catalog)
    }
  }
#endif

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
                                            filter: LibraryFilter(person: person)))
  }

#if !os(tvOS)
  private static let birthdayFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .medium
    f.timeStyle = .none
    return f
  }()

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
