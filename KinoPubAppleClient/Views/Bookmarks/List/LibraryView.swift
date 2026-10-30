//
//  LibraryView.swift
//  KinoPubAppleClient
//

import SwiftUI
import KinoPubUI
import KinoPubBackend

/// The Library tab on iPhone and iPad (Sasha's layout, 2026-10-30): a list of places —
/// History and each bookmark folder with its own count — then Continue Watching as a
/// rail, then every bookmark as a poster grid with the folder, type and sort pickers the
/// rest of the app filters with. Watching (the followed serials) is a tab of its own.
struct LibraryView: View {
  @Environment(NavigationState.self) var navigationState
  @Environment(ErrorHandler.self) var errorHandler
  @EnvironmentObject var authState: AuthState
  @Environment(\.appContext) var appContext
  @Environment(\.openURL) private var openURL
  @Environment(\.dynamicTypeSize) private var typeSize
  @StateObject private var cardMenu = MediaCardMenuCoordinator()

  @StateObject private var catalog: PersonalLibraryCatalog
  /// All Bookmarks, or one folder: the same catalog the Mac and TV Library sections use.
  @StateObject private var bookmarks: LibrarySectionCatalog
  @State private var bookmarksSection: LibrarySection = .allBookmarks
  @State private var width: CGFloat = 390

  /// iPhone: Settings behind a gear in the bar, not a tab of its own.
  private let settings: AnyView?
  @State private var showsSettings = false

  init(catalog: @autoclosure @escaping () -> PersonalLibraryCatalog,
       bookmarks: @autoclosure @escaping () -> LibrarySectionCatalog,
       settings: AnyView? = nil) {
    _catalog = StateObject(wrappedValue: catalog())
    _bookmarks = StateObject(wrappedValue: bookmarks())
    self.settings = settings
  }

  var body: some View {
    @Bindable var errorHandler = errorHandler
    RouteStack(tab: .library) {
      page
        .platformNavigationTitle("Library")
        .background(Color.KinoPub.background)
        .task {
          cardMenu.bind(errorHandler: errorHandler)
          await catalog.fetch()
        }
        .task(id: bookmarksSection) { await bookmarks.activate(bookmarksSection) }
        .task { await cardMenu.refreshFolders() }
        .refreshable {
          await catalog.refresh()
          await bookmarks.refresh()
        }
        .mediaCardNewFolderAlert(cardMenu)
        .handleError(state: $errorHandler.state)
#if os(iOS)
        .toolbar {
          if settings != nil {
            ToolbarItem(placement: .primaryAction) {
              Button {
                showsSettings = true
              } label: {
                Label("Settings", systemImage: "gear")
              }
            }
          }
        }
        .sheet(isPresented: $showsSettings) {
          settings
        }
#endif
    }
  }

  private var metrics: ShelfMetrics { .posters(width: width, typeSize: typeSize) }

  private var page: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 28) {
        places
        if let continueRow {
          MediaPosterShelf<Int>(
            title: "Continue Watching".localized,
            cards: continueRow.cards,
            destination: Route.continueWatching,
            navigationLinkProvider: { card in BookmarksRoutes.detailsById(card.itemID) },
            onPlay: { card in cardMenu.play(card) { navigationState.push($0) } },
            contextMenuProvider: { card in contextEntries(card) },
            caption: .always
          )
        }
        allBookmarks
      }
      .padding(.vertical, 8)
    }
    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { if $0 > 0 { width = $0 } }
  }

  // MARK: - Places

  /// History, then every bookmark folder with what it holds — each opens its own page.
  private var places: some View {
    VStack(spacing: 0) {
      placeRow(title: "History".localized, systemImage: "clock.arrow.circlepath",
               count: nil, route: .history)
      ForEach(catalog.folders.filter { $0.count != "0" }, id: \.id) { folder in
        Divider().padding(.leading, metrics.inset + 40)
        placeRow(title: folder.title, systemImage: "bookmark",
                 count: folder.count, route: .bookmark(folder))
      }
    }
  }

  private func placeRow(title: String, systemImage: String, count: String?, route: Route) -> some View {
    NavigationLink(value: route) {
      HStack(spacing: 16) {
        Image(systemName: systemImage)
          .font(.title3)
          .foregroundStyle(.tint)
          .frame(width: 24)
        Text(title)
          .foregroundStyle(Color.KinoPub.text)
        Spacer()
        if let count {
          Text(count)
            .foregroundStyle(Color.KinoPub.subtitle)
        }
        Image(systemName: "chevron.forward")
          .font(.footnote.weight(.semibold))
          .foregroundStyle(.tertiary)
      }
      .font(.body)
      .padding(.vertical, 12)
      .padding(.horizontal, metrics.inset)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  private var continueRow: MediaRow? {
    catalog.rows.first { $0.id == "continue" }
  }

  // MARK: - All Bookmarks

  private var allBookmarks: some View {
    VStack(alignment: .leading, spacing: 6) {
      SectionHeader(title: "Library_AllBookmarks".localized, leadingInset: metrics.inset)
      HStack(spacing: 8) {
        folderMenu
        LibraryFiltersBar(catalog: bookmarks)
      }
      .padding(.leading, metrics.inset)
      bookmarksGrid
    }
  }

  /// All Bookmarks or one folder — the grid's source, as the Mac sidebar picks it.
  private var folderMenu: some View {
    Menu {
      Picker("Library_AllBookmarks".localized, selection: $bookmarksSection) {
        Text("All").tag(LibrarySection.allBookmarks)
        ForEach(catalog.folders, id: \.id) { folder in
          Text(folder.title).tag(LibrarySection.folder(folder.id))
        }
      }
    } label: {
      Label(folderTitle, systemImage: "chevron.down")
        .labelStyle(.titleAndIcon)
    }
    .modifier(LibraryFilterGlassStyle(isProminent: bookmarksSection != .allBookmarks))
  }

  private var folderTitle: String {
    guard case .folder(let id) = bookmarksSection,
          let folder = catalog.folders.first(where: { $0.id == id }) else { return "All".localized }
    return folder.title
  }

  @ViewBuilder
  private var bookmarksGrid: some View {
    if bookmarks.cards.isEmpty {
      if bookmarks.isLoading || !bookmarks.isLoaded {
        ProgressView().frame(maxWidth: .infinity).padding()
      } else {
        Text("No Results")
          .foregroundStyle(Color.KinoPub.subtitle)
          .frame(maxWidth: .infinity)
          .padding()
      }
    } else {
      LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: metrics.gutter, alignment: .top),
                               count: metrics.columns),
                spacing: metrics.gutter) {
        ForEach(bookmarks.cards) { card in
          NavigationLink(value: Route.detailsById(card.itemID)) {
            MediaCardView(card: card, caption: .always)
              .onAppear { bookmarks.loadMoreContent(after: card) }
          }
          .buttonStyle(MediaCardButtonStyle())
          .modifier(MediaCardContextMenuModifier(isEnabled: true,
                                                 entriesProvider: { contextEntries(card) }))
        }
      }
      .padding(.horizontal, metrics.inset)
      PaginationFooter(state: bookmarks.paginationState, onRetry: { bookmarks.retryPagination() })
    }
  }

  private func contextEntries(_ card: MediaCard) -> [MediaCardContextEntry] {
    MediaCardContextMenus.entries(
      for: card,
      surface: .shelf,
      menu: cardMenu,
      pushRoute: { navigationState.push($0) },
      openURL: { openURL($0) }
    )
  }
}
