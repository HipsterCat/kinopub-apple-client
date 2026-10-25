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
  @AppStorage(HistorySectioning.storageKey) private var historySectioning: String = HistorySectioning.day.rawValue
#if os(tvOS)
  @FocusState private var sidebarFocused: Bool
  @State private var sidebarLayout = LibrarySidebarLayout()
#endif

  /// Library History is by day (Sasha, 2026-10-10) — Сегодня / Вчера / the date.
  private var sectioning: HistorySectioning {
    model.selection == .history ? .day : (HistorySectioning(rawValue: historySectioning) ?? .day)
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
      libraryColumns
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .task {
      cardMenu.bind(errorHandler: errorHandler)
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
    .alert("Rename", isPresented: renamePresented) {
      TextField("Folder name", text: $model.renameFolderName)
      Button("Rename") { model.confirmRenameFolder() }
      Button("Cancel", role: .cancel) { model.folderToRename = nil }
    }
    .alert("Delete Folder", isPresented: deletePresented) {
      Button("Delete Folder", role: .destructive) { model.confirmDeleteFolder() }
      Button("Cancel", role: .cancel) { model.folderToDelete = nil }
    } message: {
      if let folder = model.folderToDelete {
        Text(String(format: "Delete Folder Confirmation".localized, folder.title))
      }
    }
    .handleError(state: $errorHandler.state)
  }

  private var renamePresented: Binding<Bool> {
    Binding(get: { model.folderToRename != nil },
            set: { if !$0 { model.folderToRename = nil } })
  }

  private var deletePresented: Binding<Bool> {
    Binding(get: { model.folderToDelete != nil },
            set: { if !$0 { model.folderToDelete = nil } })
  }

#if os(tvOS)
  private var libraryColumns: some View {
    // The grid keeps its own side inset on both edges, so from the sidebar's rows to the
    // first column is that one inset, as from the last column to the screen's edge. The
    // sidebar's trailing margin is only the room its focused row grows into, so the
    // columns overlap by it.
    HStack(alignment: .top, spacing: -sidebarLayout.focusRoom) {
        sidebar
        detail
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .focusSection()
          .onExitCommand { sidebarFocused = true }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .ignoresSafeArea(.container, edges: [.horizontal])
  }
#else
  private var libraryColumns: some View {
    HStack(alignment: .top, spacing: 0) {
      sidebar
      detail
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }
#endif

  // MARK: - Sidebar

#if os(macOS)
  private var sidebar: some View {
    List(selection: selectionBinding) {
      ForEach(LibrarySection.leadingFixed, id: \.self) { section in
        row(for: section)
          .tag(section)
      }

      ForEach(model.folders, id: \.id) { folder in
        row(for: .folder(folder.id))
          .tag(LibrarySection.folder(folder.id))
          .contextMenu {
            Button("Rename") { model.promptRenameFolder(id: folder.id) }
            Button("Delete Folder", role: .destructive) {
              model.promptDeleteFolder(id: folder.id)
            }
          }
      }

      Button {
        model.promptNewFolder()
      } label: {
        Label("Create Bookmark", systemImage: "plus")
      }
      .buttonStyle(.plain)

      ForEach(LibrarySection.trailingFixed, id: \.self) { section in
        row(for: section)
          .tag(section)
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
  /// section — a second section would put a header between them. Width hugs the
  /// widest row as the table draws it, up to a share of the screen.
  private var sidebar: some View {
    LibrarySidebar(
      rows: model.sections.map { section in
        LibrarySidebarRow(section: section,
                          title: model.title(for: section),
                          count: model.count(for: section),
                          systemImage: section.systemImage)
      },
      selection: model.selection,
      layout: $sidebarLayout,
      onSelect: { section in
        guard model.selection != section else { return }
        model.select(section)
      },
      onRename: { model.promptRenameFolder(id: $0) },
      onDelete: { model.promptDeleteFolder(id: $0) }
    )
    .frame(width: sidebarLayout.width)
    .frame(maxHeight: .infinity)
    .focusSection()
    .focused($sidebarFocused)
    .defaultFocus($sidebarFocused, true, priority: .userInitiated)
  }
#endif

  private func row(for section: LibrarySection) -> some View {
    HStack {
      if let image = section.systemImage {
        Label(model.title(for: section), systemImage: image)
          .lineLimit(1)
          .font(.system(.footnote, weight: .regular))
          .foregroundStyle(model.selection == section ? .primary : .secondary)
      } else {
        Text(model.title(for: section))
          .lineLimit(1)
          .font(.system(.footnote, weight: .regular))
          .foregroundStyle(model.selection == section ? .primary : .secondary)
      }
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
      sideInset: 0,
      accessibilityID: "kinopub.page.library",
      onSelect: { _, item in
        guard case .card(let card) = item else { return }
        if card.primaryAction == .play {
          cardMenu.play(card) { navigationState.push($0) }
        } else {
          navigationState.push(.detailsById(card.itemID))
        }
      },
      onChipOption: { chip, option in
        switch chip {
        case TVSearchFilters.followingUnwatched:
          catalog.followingScope = .unwatched
        case TVSearchFilters.followingAll:
          catalog.followingScope = .all
        case TVSearchFilters.folderActions:
          guard case .folder(let id) = model.selection else { return }
          switch option {
          case TVSearchFilters.folderRename: model.promptRenameFolder(id: id)
          case TVSearchFilters.folderDelete: model.promptDeleteFolder(id: id)
          default: break
          }
        case TVSearchFilters.folderRename:
          if case .folder(let id) = model.selection { model.promptRenameFolder(id: id) }
        case TVSearchFilters.folderDelete:
          if case .folder(let id) = model.selection { model.promptDeleteFolder(id: id) }
        default:
          TVSearchFilters.apply(chip: chip, option: option, to: catalog)
        }
      },
      onChipSelection: { chip, selection in
        TVSearchFilters.applySelection(chip: chip, selection: selection, to: catalog)
      },
      onNearEnd: { section in
        // Only the end of the list: History is a section per day, and the last card of
        // every day on screen used to ask for the next page.
        guard section.loadsMore, let last = catalog.cards.last else { return }
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
      // First Menu from a grid row below the top returns there; at the top it
      // passes through to the sidebar (`onExitCommand` on the detail column).
      returnsToTopOnMenu: true,
      // Another section is another list: it opens at its top.
      contentID: model.selection.persistenceID
    )
    .ignoresSafeArea(.container, edges: [.vertical, .trailing])
  }

  private var libraryHeaderActions: [TVPageChip] {
    TVSearchFilters.libraryHeaderChips(catalog: catalog, section: model.selection)
  }

  private var librarySections: [TVPageSection] {
    let cards = catalog.cards
    let sectionID = "library.\(model.selection.persistenceID)"
    let title = model.headerTitle(for: model.selection, cards: cards)
    let actions = libraryHeaderActions
    guard !cards.isEmpty else {
      let empty = catalog.isLoading
        ? TVPageSection.placeholder(id: sectionID, title: title, kind: .poster, columns: 6, flow: .grid)
        : TVPageSection.posters(id: sectionID, title: title, flow: .grid,
                                caption: .always, headerActions: actions, cards: [])
      return [empty.withHeaderActions(actions)]
    }
    let grouped: [(id: String, title: String?, cards: [MediaCard])]
    if model.selection == .history {
      grouped = sectioning.sections(for: cards).map { ($0.id, $0.title, $0.cards) }
    } else if model.selection == .watchlist {
      grouped = LibrarySectionCatalog.followingPageGroups(from: cards, scope: catalog.followingScope).map {
        ($0.id, $0.isWatched ? "Library_WatchedSeries".localized : nil, $0.cards)
      }
    } else {
      grouped = []
    }
    let groups: [(id: String, title: String?, cards: [MediaCard])] = grouped.isEmpty
      ? [(sectionID, title, cards)]
      : grouped
    let lastID = groups.last?.id
    let usesOwnCounts = !grouped.isEmpty
    return groups.enumerated().map { index, group in
      let loadsMore = group.id == lastID && catalog.hasMorePages
      // Named groups (History days) keep that name.
      // Everywhere else the count is the title — never title + count.
      let headerTitle = usesOwnCounts ? (group.title ?? title) : title
      let headerActions = index == 0 ? actions : []
      return group.cards.first?.isLandscape == true
        ? .stills(id: group.id, title: headerTitle, columns: 4, flow: .grid,
                  caption: .always, loadsMore: loadsMore, headerActions: headerActions,
                  cards: group.cards)
        : .posters(id: group.id, title: headerTitle, flow: .grid,
                   caption: .always, loadsMore: loadsMore, headerActions: headerActions,
                   cards: group.cards)
    }
  }

  private var libraryStatus: TVPageStatus {
    let cards = catalog.cards
    if cards.isEmpty && catalog.loadFailed {
      return .failed(message: catalog.loadError?.userFacingMessage
                       ?? "Check your connection and try again.".localized,
                     retryTitle: "Try Again".localized)
    }
    if let empty = paneEmpty(visibleCount: visibleLibraryCards.count) {
      return .unavailable(title: empty.titleKey,
                          systemImage: empty.systemImage,
                          message: empty.messageKey.localized)
    }
    return .content
  }

  /// Cards the grid actually draws. Subscriptions on Unwatched hides caught-up series,
  /// so the pane can be empty while `catalog.cards` is not.
  private var visibleLibraryCards: [MediaCard] {
    let cards = catalog.cards
    guard model.selection == .watchlist else { return cards }
    return LibrarySectionCatalog.followingPageGroups(from: cards, scope: catalog.followingScope)
      .flatMap(\.cards)
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
    } else if let empty = paneEmpty(visibleCount: catalog.cards.count) {
      paneUnavailable(empty)
    } else if catalog.cards.isEmpty {
      LoadingIndicatorView()
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

  /// Loaded, and the grid has nothing to draw. Not a failure — that keeps its retry.
  private func paneEmpty(visibleCount: Int) -> LibraryPaneEmpty? {
    guard !catalog.isLoading, catalog.isLoaded, !catalog.loadFailed else { return nil }
    return LibraryPaneEmpty.make(section: model.selection,
                                 cardCount: catalog.cards.count,
                                 visibleCount: visibleCount,
                                 followingScope: catalog.followingScope,
                                 filtersActive: catalog.filter.hasActiveFilters)
  }

  private func paneUnavailable(_ empty: LibraryPaneEmpty) -> some View {
    UnavailableView(title: LocalizedStringKey(stringLiteral: empty.titleKey),
                    systemImage: empty.systemImage,
                    message: empty.messageKey.localized)
  }
}

#if os(tvOS)
/// What the sidebar tells the columns beside it: how wide it is, and how much of that is
/// the trailing margin a focused row grows into rather than rows.
struct LibrarySidebarLayout: Equatable {
  var width: CGFloat = 280
  var focusRoom: CGFloat = 0
}

private struct LibrarySidebarRow: Equatable {
  let section: LibrarySection
  let title: String
  /// Trailing value. Nil on the rows that have no honest total.
  let count: String?
  let systemImage: String?
}

private struct LibrarySidebar: UIViewControllerRepresentable {
  let rows: [LibrarySidebarRow]
  let selection: LibrarySection
  @Binding var layout: LibrarySidebarLayout
  let onSelect: (LibrarySection) -> Void
  let onRename: (Int) -> Void
  let onDelete: (Int) -> Void

  func makeUIViewController(context: Context) -> LibrarySidebarController {
    LibrarySidebarController()
  }

  func updateUIViewController(_ controller: LibrarySidebarController, context: Context) {
    controller.onSelect = onSelect
    controller.onRename = onRename
    controller.onDelete = onDelete
    controller.onLayoutChange = { newLayout in
      if abs(layout.width - newLayout.width) > 0.5 || abs(layout.focusRoom - newLayout.focusRoom) > 0.5 {
        layout = newLayout
      }
    }
    controller.setRows(rows, selection: selection)
  }
}

/// Plain `UITableView`. `selectionFollowsFocus` is unavailable on tvOS, so focus
/// updates call `selectRow` — the same selection Enter uses. The cell's own
/// selection style is left alone. The first row is selected until focus moves.
private final class LibrarySidebarController: UITableViewController {
  var onSelect: (LibrarySection) -> Void = { _ in }
  var onRename: (Int) -> Void = { _ in }
  var onDelete: (Int) -> Void = { _ in }
  var onLayoutChange: (LibrarySidebarLayout) -> Void = { _ in }
  private var rows: [LibrarySidebarRow] = []
  private var selection: LibrarySection?
  /// Until the table has actually held focus, the preferred row is the selected one
  /// (the first, by default). After that, `remembersLastFocusedIndexPath` answers —
  /// returning a path on every move would pin focus to that row.
  private var hasFocusedOnce = false

  private static let minWidth: CGFloat = 220
  /// Past this share of the screen a row stops widening the sidebar and its title
  /// scrolls while focused instead.
  private static let maxScreenShare: CGFloat = 0.25

  override func viewDidLoad() {
    super.viewDidLoad()
    // `UITableViewController` clears the selection in `viewWillAppear` by default,
    // which is why the sidebar opened with nothing selected.
    clearsSelectionOnViewWillAppear = false
    tableView.remembersLastFocusedIndexPath = true
    // The rows start on the side inset, as the grid's columns end on it. Left to
    // itself the table adds its own minimum margin on top of the safe area.
    tableView.insetsLayoutMarginsFromSafeArea = false
    tableView.register(LibrarySidebarCell.self, forCellReuseIdentifier: LibrarySidebarCell.reuseIdentifier)
    tableView.reloadData()
    applySelection()
    publishWidth()
  }

  func setRows(_ rows: [LibrarySidebarRow], selection: LibrarySection) {
    let rowsChanged = rows != self.rows
    self.rows = rows
    self.selection = selection
    guard isViewLoaded else { return }
    if rowsChanged {
      tableView.reloadData()
      publishWidth()
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

  override func viewSafeAreaInsetsDidChange() {
    super.viewSafeAreaInsetsDidChange()
    publishWidth()
  }

  /// The table's margins and the widest row as a cell of this table lays it out — the
  /// font, the icon slot and the padding are the system's, so they are measured, not
  /// added up from numbers of ours.
  private func publishWidth() {
    let room = systemMinimumLayoutMargins.trailing
    let leading = max(view.safeAreaInsets.left, TVHIGGrid.sideInset)
    tableView.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 0, leading: leading,
                                                                 bottom: 0, trailing: room)
    let sizing = LibrarySidebarCell(style: .default, reuseIdentifier: nil)
    let widest = rows.map { titleWidth(of: $0, in: sizing) }.max() ?? 0
    let font = Self.titleFont(in: sizing)
    // The 25% cap limits the title. The count is a column after it, so a number never
    // steals letters from a title that already fit — «All Bookmarks» stays whole, and
    // a long folder name still marquees inside the cap.
    let countColumn = rows.map { Self.countColumnWidth(for: $0, font: font) }.max() ?? 0
    let screen = view.window?.screen.bounds.width ?? 1920
    let capped = min(max(ceil(leading + widest + room), Self.minWidth), (screen * Self.maxScreenShare).rounded())
    onLayoutChange(LibrarySidebarLayout(width: capped + countColumn, focusRoom: room))
  }

  /// The title and symbol. The count is the cell's accessory, laid out beside this.
  private func titleWidth(of row: LibrarySidebarRow, in sizing: LibrarySidebarCell) -> CGFloat {
    sizing.contentConfiguration = Self.content(for: row, in: sizing)
    return sizing.contentView.systemLayoutSizeFitting(
      CGSize(width: UIView.layoutFittingCompressedSize.width, height: UIView.layoutFittingCompressedSize.height),
      withHorizontalFittingPriority: .fittingSizeLevel,
      verticalFittingPriority: .fittingSizeLevel
    ).width
  }

  private static func titleFont(in cell: UITableViewCell) -> UIFont {
    content(for: LibrarySidebarRow(section: .history, title: " ", count: nil, systemImage: nil),
            in: cell).textProperties.font
  }

  /// Width the trailing number takes, including the gap before it. Zero when the row
  /// has no count.
  private static func countColumnWidth(for row: LibrarySidebarRow, font: UIFont) -> CGFloat {
    guard let count = row.count, !count.isEmpty else { return 0 }
    return ceil((count as NSString).size(withAttributes: [.font: font]).width) + 12
  }

  private static func content(for row: LibrarySidebarRow, in cell: UITableViewCell) -> UIListContentConfiguration {
    var content = cell.defaultContentConfiguration()
    content.text = row.title
    // One line: the marquee runs on single-line labels only.
    content.textProperties.numberOfLines = 1
    content.image = row.systemImage.flatMap { UIImage(systemName: $0) }
    // The symbol follows the row's text style at medium scale, so it grows with Dynamic Type.
    // Its slot is the system's standard one, which lines its leading edge up with a folder
    // label's (Sasha, 2026-10-17).
    content.imageProperties.preferredSymbolConfiguration = UIImage.SymbolConfiguration(textStyle: .headline, scale: .medium)
    content.imageProperties.reservedLayoutSize = CGSize(width: UIListContentConfiguration.ImageProperties.standardDimension,
                                                        height: UIListContentConfiguration.ImageProperties.standardDimension)
    return content
  }

  /// The count sits in the cell's accessory slot, so it keeps its width and the title
  /// is what truncates. A value cell's secondary text does the opposite once the row
  /// is tight: the number compresses to nothing.
  private static func countAccessory(for row: LibrarySidebarRow, font: UIFont) -> UILabel? {
    guard let count = row.count, !count.isEmpty else { return nil }
    let label = UILabel()
    label.text = count
    label.font = font
    label.adjustsFontForContentSizeCategory = true
    label.textColor = .secondaryLabel
    label.setContentCompressionResistancePriority(.required, for: .horizontal)
    label.sizeToFit()
    return label
  }

  override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    rows.count
  }

  override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = tableView.dequeueReusableCell(withIdentifier: LibrarySidebarCell.reuseIdentifier, for: indexPath)
    let row = rows[indexPath.row]
    let content = Self.content(for: row, in: cell)
    cell.contentConfiguration = content
    cell.accessoryView = Self.countAccessory(for: row, font: content.textProperties.font)
    cell.accessibilityIdentifier = "kinopub.library.section.\(row.section.persistenceID)"
    return cell
  }

  override func tableView(_ tableView: UITableView,
                          contextMenuConfigurationForRowAt indexPath: IndexPath,
                          point: CGPoint) -> UIContextMenuConfiguration? {
    guard rows.indices.contains(indexPath.row),
          case .folder(let id) = rows[indexPath.row].section else { return nil }
    return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
      UIMenu(children: [
        UIAction(title: "Rename".localized, image: UIImage(systemName: "pencil")) { _ in
          self?.onRename(id)
        },
        UIAction(title: "Delete Folder".localized, image: UIImage(systemName: "trash"),
                 attributes: .destructive) { _ in
          self?.onDelete(id)
        }
      ])
    }
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

/// The system cell, with the system's marquee on its title: a folder named wider than the
/// sidebar ends in an ellipsis at rest and scrolls while its row is focused, as tvOS's own
/// lists do. `UIListContentConfiguration` has no switch for it, so it is set on the label
/// the configuration draws into.
private final class LibrarySidebarCell: UITableViewCell {
  override func updateConfiguration(using state: UICellConfigurationState) {
    super.updateConfiguration(using: state)
    // The symbol is secondary at rest and takes the title's colour when the row is focused
    // or selected — the system's colour for that state, whatever the platter behind it.
    // The accessory count follows: grey on grey does not read on the light platter.
    if var content = contentConfiguration as? UIListContentConfiguration {
      let active = state.isFocused || state.isSelected
      let tint = active ? content.updated(for: state).textProperties.resolvedColor() : .secondaryLabel
      if content.imageProperties.tintColor != tint {
        content.imageProperties.tintColor = tint
        contentConfiguration = content
      }
      if let count = accessoryView as? UILabel, count.textColor != tint {
        count.textColor = tint
      }
    }
    enableMarquee(in: contentView)
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    enableMarquee(in: contentView)
  }

  private func enableMarquee(in view: UIView) {
    for subview in view.subviews {
      if let label = subview as? UILabel {
        if !label.enablesMarqueeWhenAncestorFocused { label.enablesMarqueeWhenAncestorFocused = true }
      } else {
        enableMarquee(in: subview)
      }
    }
  }
}

private extension UITableViewCell {
  static var reuseIdentifier: String {
    String(reflecting: self)
  }
}
#endif
#endif
