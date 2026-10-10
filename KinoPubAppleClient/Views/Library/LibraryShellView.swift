//
//  LibraryShellView.swift
//  KinoPubAppleClient
//

import SwiftUI
import KinoPubUI
import KinoPubBackend
#if os(tvOS)
import UIKit
#endif

#if os(macOS) || os(tvOS)
/// Library: sidebar of sections, grid of the selected one. Sections are a product
/// decision — `ROADMAP.md`.
///
/// Both platforms lay the sidebar out as **content**, not as window/system chrome, so
/// the tab bar keeps the full width above it. On tvOS that also keeps focus honest:
/// each column is its own `focusSection`, so Left out of the grid lands in the list and
/// Right comes back, without a `NavigationSplitView` deciding when to collapse.
///
/// On tvOS the sidebar is a `UITableView` — one section, the system's own focus
/// and selection. Focus moving onto a row switches the grid. The first row is the
/// default selection; `remembersLastFocusedIndexPath` restores that row when focus
/// comes back from the grid.
struct LibraryShellView: View {
  @Environment(NavigationState.self) var navigationState
  @Environment(ErrorHandler.self) var errorHandler
  @Environment(\.appContext) var appContext
  @Environment(\.openURL) private var openURL

  @StateObject private var model: LibraryModel
  @StateObject private var catalog: LibrarySectionCatalog
  @StateObject private var cardMenu = MediaCardMenuCoordinator()
  @AppStorage(HistoryGrouping.storageKey) private var historyGrouping: String = HistoryGrouping.none.rawValue
  @AppStorage(HistorySectioning.storageKey) private var historySectioning: String = HistorySectioning.month.rawValue
#if os(tvOS)
  @FocusState private var sidebarFocused: Bool
#endif

  private var sectioning: HistorySectioning {
    HistorySectioning(rawValue: historySectioning) ?? .month
  }

  init(model: @autoclosure @escaping () -> LibraryModel,
       catalog: @autoclosure @escaping () -> LibrarySectionCatalog) {
    _model = StateObject(wrappedValue: model())
    _catalog = StateObject(wrappedValue: catalog())
  }

  var body: some View {
    @Bindable var errorHandler = errorHandler
    // Deliberately NOT a `NavigationSplitView`. On macOS that makes the sidebar window
    // chrome: it runs full height beside the title bar, so the tab bar and the search
    // field get pushed into the detail half and the traffic lights end up sitting on
    // the sidebar. Here the sidebar is content — the chrome spans the full width above
    // it — which is also why there is no collapse control left to remove.
    //
    // The stack wraps sidebar AND detail together, not just detail: every other tab's
    // `NavigationStack` spans its whole content area, so a pushed title's detail page
    // covers the full tab. A stack scoped to only the detail pane would leave that
    // pane's width beside a sidebar that never goes anywhere — section switching is
    // separate state (`model.selection`), not a stack push, so it is unaffected by
    // where the stack sits.
    RouteStack(tab: .library) {
      HStack(alignment: .top, spacing: 0) {
        sidebar
        detail
          .frame(maxWidth: .infinity, maxHeight: .infinity)
#if os(tvOS)
          .focusSection()
          .onExitCommand { sidebarFocused = true }
#endif
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .task {
      cardMenu.bind(errorHandler: errorHandler)
#if os(tvOS)
      // The sidebar's default selection is its first row. A remembered section is
      // what macOS restores; tvOS starts at the top of the list.
      if let first = model.sections.first {
        model.select(first)
      }
#endif
      await model.load()
    }
    .task { await cardMenu.refreshFolders() }
    .task(id: historyGrouping) {
      guard model.selection == .history, catalog.isLoaded else { return }
      await catalog.refresh()
    }
    // Section switches are cheap when the cache is warm — `activate` paints from the
    // store first and only refetches past the TTL.
    .task(id: model.selection) {
      await catalog.activate(model.selection)
    }
    // Back at the Library's own root from a pushed title (and whatever it opened): the
    // grid underneath never went away, so nothing above runs again. Activating repaints
    // from the store and refetches what went stale meanwhile — a title watched to the
    // end invalidates the watching rows (`LibrarySectionCatalog.rowsWatchingChanges`).
    .onChange(of: navigationState.libraryRoutes.isEmpty) { _, atRoot in
      guard atRoot else { return }
      Task { await catalog.activate(model.selection) }
    }
    // Only Recently Watched has anything to arrange, so the View menu's items go dim
    // on every other section rather than staying live and doing nothing.
    .focusedSceneValue(\.showsListArrangement, model.selection == .history)
#if os(iOS)
    // Only Recently Watched has anything to arrange, so the control only appears there.
    // macOS reaches the same two options through the View menu.
    .toolbar {
      if model.selection == .history {
        ToolbarItem(placement: .topBarTrailing) {
          Menu {
          Menu {
              Picker("Group By", selection: $historyGrouping) {
                ForEach(HistoryGrouping.allCases) { option in
                  Text(LocalizedStringKey(option.titleKey)).tag(option.rawValue)
                }
              }
            } label: {
              Label("Group By", systemImage: "rectangle.stack")
            }
            Menu {
              Picker("Group By Date", selection: $historySectioning) {
                ForEach(HistorySectioning.allCases) { option in
                  Text(LocalizedStringKey(option.titleKey)).tag(option.rawValue)
                }
              }
            } label: {
              Label("Group By Date", systemImage: "calendar")
            }
          } label: {
            Label("View Options", systemImage: "line.3.horizontal.decrease.circle")
          }
        }
      }
    }
#endif
    .alert("New Bookmark", isPresented: $model.isCreatingFolder) {
      TextField("Folder name", text: $model.newFolderName)
      Button("Create") { model.confirmNewFolder() }
      Button("Cancel", role: .cancel) { model.isCreatingFolder = false }
    }
    .handleError(state: $errorHandler.state)
  }

  // MARK: - Sidebar

#if os(macOS)
  private var sidebar: some View {
    List(selection: selectionBinding) {
      Section {
        ForEach(LibrarySection.fixed, id: \.self) { section in
          row(for: section)
            .tag(section)
        }
      }

      Section("Bookmarks") {
        ForEach(model.folders, id: \.id) { folder in
          row(for: .folder(folder.id))
            .tag(LibrarySection.folder(folder.id))
            .contextMenu {
              Button("Delete Bookmark", role: .destructive) {
                model.deleteFolder(id: folder.id)
              }
            }
        }

        Button {
          model.promptNewFolder()
        } label: {
          Label("Create Bookmark", systemImage: "plus")
        }
        .buttonStyle(.plain)
      }
    }
    // No material behind the sidebar: it shares the window's background with the grid
    // so the two columns read as one surface, not as chrome bolted onto content.
    .scrollContentBackground(.hidden)
    .listStyle(.sidebar)
    .frame(width: 240)
  }

  /// `List` writes straight to the binding, so persistence has to hang off the setter
  /// rather than off a button action — there is no button.
  private var selectionBinding: Binding<LibrarySection?> {
    Binding(
      get: { model.selection },
      set: { newValue in
        guard let newValue else { return }  // clicking empty space must not clear the pane
        model.select(newValue)
      }
    )
  }
#endif

#if os(tvOS)
  /// One flat table. Fixed sections and bookmark folders are rows of that single
  /// section — a second section would put a header between them.
  private var sidebar: some View {
    LibrarySidebar(
      rows: model.sections.map { section in
        LibrarySidebarRow(section: section, title: model.title(for: section))
      },
      selection: model.selection,
      onSelect: { section in
        guard model.selection != section else { return }
        model.select(section)
      }
    )
    .frame(width: 380)
    .frame(maxHeight: .infinity)
    .focusSection()
    .focused($sidebarFocused)
    .defaultFocus($sidebarFocused, true, priority: .userInitiated)
  }
#endif

  private func row(for section: LibrarySection) -> some View {
    HStack {
      Label(model.title(for: section), systemImage: section.systemImage)
        .lineLimit(1)
        .font(.system(.footnote, weight: .regular))
        .foregroundStyle(model.selection == section ? .primary : .secondary)
      if let count = model.count(for: section) {
        Spacer()
        Text(count)
          .foregroundStyle(.tertiary)
          .monospacedDigit()
          .font(.system(.caption, weight: .regular))

      }
    }
  }

  // MARK: - Detail

  @ViewBuilder
  private var detail: some View {
    if model.selection == .downloads {
      // Downloads brings its own stack and its own route list — local files, not a
      // card grid, so it does not go through `LibrarySectionCatalog`. That inner stack
      // is still scoped to this pane (unchanged) — nothing downloads pushes today is
      // the kind of full-bleed page that needs to cover the sidebar.
      DownloadsView(catalog: DownloadsCatalog(downloadsDatabase: appContext.downloadedFilesDatabase,
                                              downloadManager: appContext.downloadManager))
    } else {
      sectionContent
        .platformNavigationTitle(model.title(for: model.selection))
#if os(macOS)
        .macToolbarSearch()
#endif
    }
  }

#if os(tvOS)
  /// The same page collection as the tabs, in grid flow: the same cards at the same
  /// class size, wrapping instead of running off the edge. Recently Watched keeps its
  /// month (or week) sections as titled grids.
  private var sectionContent: some View {
    TVPage(
      sections: librarySections,
      status: libraryStatus,
      sideInset: TVHIGGrid.gutter,
      accessibilityID: "kinopub.page.library",
      onSelect: { _, item in
        guard case .card(let card) = item else { return }
        if card.primaryAction == .play {
          cardMenu.play(card) { navigationState.push($0) }
        } else {
          navigationState.push(.detailsById(card.itemID))
        }
      },
      onNearEnd: { _ in
        guard let last = catalog.cards.last else { return }
        catalog.loadMoreContent(after: last)
      },
      contextMenuProvider: { card in
        MediaCardContextMenus.entries(for: card,
                                      surface: .shelf,
                                      menu: cardMenu,
                                      pushRoute: { navigationState.push($0) },
                                      openURL: { openURL($0) })
      },
      onRetry: { Task { await catalog.refresh() } },
      // Menu from the grid returns to the sidebar (`onExitCommand` above). The table
      // remembers the row that had focus. Menu there reaches the tab bar.
      returnsToTopOnMenu: false
    )
    // Under the tab bar (native scroll-edge fade via `setContentScrollView`) and out
    // to the trailing screen edge. Leading inset is the gutter past the sidebar, not
    // another 80 pt of page margin on top of 420 pt of list.
    .ignoresSafeArea(.container, edges: [.vertical])
  }

  private var librarySections: [TVPageSection] {
    let cards = catalog.cards
    guard !cards.isEmpty else {
      return catalog.isLoading
        ? [.placeholder(id: "library", title: nil, kind: .poster, columns: 6, flow: .grid)]
        : []
    }
    let grouped = model.selection == .history ? sectioning.sections(for: cards) : []
    let groups: [(id: String, title: String?, cards: [MediaCard])] = grouped.isEmpty
      ? [("library", nil, cards)]
      : grouped.map { ($0.id, $0.title, $0.cards) }
    // The next page lands in the last group, so only that one ends on the loading row.
    let lastID = groups.last?.id
    return groups.map { group in
      let loadsMore = group.id == lastID && catalog.hasMorePages
      return group.cards.first?.isLandscape == true
        ? .stills(id: group.id, title: group.title, columns: 4, flow: .grid, caption: .always,
                  loadsMore: loadsMore, cards: group.cards)
        // Titles always under the posters, as in search — and with them the row gap
        // that leaves the captions clear air (`TVPageLayout.captionedRowGap`).
        : .posters(id: group.id, title: group.title, flow: .grid, caption: .always,
                   loadsMore: loadsMore, cards: group.cards)
    }
  }

  private var libraryStatus: TVPageStatus {
    let cards = catalog.cards
    if cards.isEmpty && catalog.loadFailed {
      return .failed(message: catalog.loadError?.userFacingMessage
                       ?? "Check your connection and try again.".localized,
                     retryTitle: "Try Again".localized)
    }
    if cards.isEmpty && !catalog.isLoading && catalog.isLoaded {
      return .message("No Results".localized)
    }
    return .content
  }
#else
  @ViewBuilder
  private var sectionContent: some View {
    if catalog.cards.isEmpty && catalog.isLoading {
      LoadingIndicatorView()
    } else if catalog.cards.isEmpty && catalog.loadFailed {
      UnavailableView(title: "Couldn't Load",
                      systemImage: "wifi.exclamationmark",
                      message: catalog.loadError?.userFacingMessage ?? "Check your connection and try again.".localized,
                      retryTitle: "Try Again",
                      onRetry: { Task { await catalog.refresh() } })
    } else if catalog.cards.isEmpty {
      UnavailableView(title: "No Results", systemImage: model.selection.systemImage)
    } else {
      MediaCardsListView(
        cards: catalog.cards,
        onLoadMoreContent: { card in catalog.loadMoreContent(after: card) },
        navigationLinkProvider: { card in Route.detailsById(card.itemID) },
        contextMenuProvider: { card in
          MediaCardContextMenus.entries(
            for: card,
            surface: .shelf,
            menu: cardMenu,
            pushRoute: { navigationState.push($0) },
            openURL: { openURL($0) }
          )
        },
        sections: model.selection == .history
          ? sectioning.sections(for: catalog.cards)
          : [],
        pagination: catalog.paginationState,
        onRetryPagination: { catalog.retryPagination() }
      )
    }
  }
#endif
}

#if os(tvOS)
private struct LibrarySidebarRow: Equatable {
  let section: LibrarySection
  let title: String
}

private struct LibrarySidebar: UIViewControllerRepresentable {
  let rows: [LibrarySidebarRow]
  let selection: LibrarySection
  let onSelect: (LibrarySection) -> Void

  func makeUIViewController(context: Context) -> LibrarySidebarController {
    LibrarySidebarController()
  }

  func updateUIViewController(_ controller: LibrarySidebarController, context: Context) {
    controller.onSelect = onSelect
    controller.setRows(rows, selection: selection)
  }
}

/// Plain `UITableView`. `selectionFollowsFocus` is unavailable on tvOS, so focus
/// updates call `selectRow` — the same selection Enter uses. The cell's own
/// selection style is left alone. The first row is selected until focus moves.
private final class LibrarySidebarController: UITableViewController {
  var onSelect: (LibrarySection) -> Void = { _ in }
  private var rows: [LibrarySidebarRow] = []
  private var selection: LibrarySection?
  /// Until the table has actually held focus, the preferred row is the selected one
  /// (the first, by default). After that, `remembersLastFocusedIndexPath` answers —
  /// returning a path on every move would pin focus to that row.
  private var hasFocusedOnce = false

  override func viewDidLoad() {
    super.viewDidLoad()
    // `UITableViewController` clears the selection in `viewWillAppear` by default,
    // which is why the sidebar opened with nothing selected.
    clearsSelectionOnViewWillAppear = false
    tableView.remembersLastFocusedIndexPath = true
    tableView.register(UITableViewCell.self, forCellReuseIdentifier: UITableViewCell.reuseIdentifier)
    tableView.reloadData()
    applySelection()
  }

  func setRows(_ rows: [LibrarySidebarRow], selection: LibrarySection) {
    let rowsChanged = rows != self.rows
    self.rows = rows
    self.selection = selection
    guard isViewLoaded else { return }
    if rowsChanged {
      tableView.reloadData()
    }
    applySelection()
  }

  /// Selects `selection`, or the first row when that is still the default.
  /// Leaving the table (focus in the grid) does not call this, so the row stays
  /// selected behind the content it is showing.
  private func applySelection() {
    guard isViewLoaded, !rows.isEmpty else { return }
    let row: Int
    if let selection, let index = rows.firstIndex(where: { $0.section == selection }) {
      row = index
    } else {
      row = 0
    }
    let indexPath = IndexPath(row: row, section: 0)
    guard tableView.indexPathForSelectedRow != indexPath else { return }
    tableView.selectRow(at: indexPath, animated: false, scrollPosition: .none)
  }

  override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    rows.count
  }

  override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = tableView.dequeueReusableCell(withIdentifier: UITableViewCell.reuseIdentifier, for: indexPath)
    let row = rows[indexPath.row]
    cell.textLabel?.text = row.title
    cell.accessibilityIdentifier = "kinopub.library.section.\(row.section.persistenceID)"
    return cell
  }

  override func indexPathForPreferredFocusedView(in tableView: UITableView) -> IndexPath? {
    guard !hasFocusedOnce, !rows.isEmpty else { return nil }
    let row = selection.flatMap { section in rows.firstIndex { $0.section == section } } ?? 0
    return IndexPath(row: row, section: 0)
  }

  override func tableView(_ tableView: UITableView,
                           didUpdateFocusIn context: UITableViewFocusUpdateContext,
                           with coordinator: UIFocusAnimationCoordinator) {
    guard context.nextFocusedIndexPath != context.previouslyFocusedIndexPath else { return }
    guard let indexPath = context.nextFocusedIndexPath, rows.indices.contains(indexPath.row) else { return }
    hasFocusedOnce = true
    let section = rows[indexPath.row].section
    selection = section
    if tableView.indexPathForSelectedRow != indexPath {
      tableView.selectRow(at: indexPath, animated: false, scrollPosition: .none)
    }
    onSelect(section)
  }
}

private extension UITableViewCell {
  static var reuseIdentifier: String {
    String(reflecting: self)
  }
}
#endif
#endif
