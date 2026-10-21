//
//  HomeCatalog.swift
//  KinoPubAppleClient
//

import Foundation
import KinoPubBackend
import KinoPubMedia
import KinoPubMetadata
import KinoPubUI
import OSLog
import KinoPubLogging
import Combine

/// Builds Watch Now / Movies / Series poster shelves from the same Hot / Fresh /
/// Popular shortcuts. Watch Now (`contentType == nil`) also carries Continue
/// Watching and Collections; a typed catalog is those shortcuts for one
/// `MediaType` only. Empty rows are dropped rather than shown blank.
@MainActor
class HomeCatalog: ObservableObject {

  struct Shortcut: Sendable {
    let shortcut: MediaShortcut
    let contentType: MediaType
    let title: String

    var id: String { "\(shortcut.rawValue)-\(contentType.rawValue)" }
  }

  /// The catalog rows below "Continue watching", in display order.
  static let shortcuts: [Shortcut] = [
    Shortcut(shortcut: .hot, contentType: .movie, title: "Hot Movies"),
    Shortcut(shortcut: .hot, contentType: .serial, title: "Hot Series"),
    Shortcut(shortcut: .fresh, contentType: .movie, title: "Fresh Movies"),
    Shortcut(shortcut: .fresh, contentType: .serial, title: "Fresh Series"),
    Shortcut(shortcut: .popular, contentType: .movie, title: "Popular Movies"),
    Shortcut(shortcut: .popular, contentType: .serial, title: "Popular Series")
  ]

  /// Watch Now shows every shortcut; Movies / Series keep the same order, one type.
  static func shortcuts(for contentType: MediaType?) -> [Shortcut] {
    guard let contentType else { return shortcuts }
    return shortcuts.filter { $0.contentType == contentType }
  }

  /// `nil` is Watch Now. `.movie` / `.serial` are the Movies and Series tabs.
  let contentType: MediaType?

  /// The shortcut rows this catalog actually fetches and paints.
  var activeShortcuts: [Shortcut] { Self.shortcuts(for: contentType) }

  /// Configurable Home section specification backed by `/v1/items` filters, bookmarks,
  /// live TV channels, or collections.
  struct HomeSectionSpec: Sendable, Identifiable {
    enum Source: Sendable {
      case filter(LibraryFilter)
      case topBookmarks
      case liveTV
      case collections
    }

    let id: String
    let title: String
    let source: Source

    func resolvedFilter(excludeConcerts: Bool) -> LibraryFilter? {
      guard case .filter(var filter) = source else { return nil }
      if excludeConcerts, filter.kinds.isEmpty {
        if filter.contentTypes.isEmpty, let single = filter.contentType {
          if single != .concert {
            filter.contentTypes = [single]
          }
        } else if filter.contentTypes.isEmpty {
          filter.contentTypes = [.movie, .serial, .documovie, .docuserial, .tvshow]
        } else {
          filter.contentTypes.remove(.concert)
        }
      }
      return filter
    }
  }

  static let homeSectionSpecsByID: [String: HomeSectionSpec] = {
    var dict: [String: HomeSectionSpec] = [:]
    let specs: [HomeSectionSpec] = [
      HomeSectionSpec(
        id: "new-arrivals",
        title: "Новинки Кинопаба",
        source: .filter(LibraryFilter(sort: .recentlyAdded))
      ),
      HomeSectionSpec(
        id: "recently-updated",
        title: "Недавно обновлённые",
        source: .filter({
          var f = LibraryFilter(sort: .recentlyUpdated)
          f.contentTypes = [.serial, .docuserial, .tvshow]
          return f
        }())
      ),
      HomeSectionSpec(
        id: "weekly-top",
        title: "Топ недели",
        source: .filter(LibraryFilter(sort: .views, period: .week))
      ),
      HomeSectionSpec(
        id: "must-see-hits",
        title: "Хиты месяца",
        source: .filter(LibraryFilter(sort: .views, period: .month))
      ),
      HomeSectionSpec(
        id: "binge-worthy",
        title: "Сериалы на запой (по подписчикам)",
        source: .filter({
          var f = LibraryFilter(sort: .watchers)
          f.contentTypes = [.serial, .docuserial]
          return f
        }())
      ),
      HomeSectionSpec(
        id: "top-rated",
        title: "Высокий рейтинг IMDb",
        source: .filter({
          var f = LibraryFilter(sort: .imdbRating)
          f.yearFrom = 2020
          return f
        }())
      ),
      HomeSectionSpec(
        id: "community-top",
        title: "Выбор Кинопаба",
        source: .filter(LibraryFilter(sort: .rating, period: .year))
      ),
      HomeSectionSpec(
        id: "latest-4k",
        title: "Последние 4K UHD релизы",
        source: .filter({
          var f = LibraryFilter(sort: .recentlyAdded)
          f.minimumQuality = .uhd4K
          return f
        }())
      ),
      HomeSectionSpec(
        id: "top-bookmarks",
        title: "Топовые закладки",
        source: .topBookmarks
      ),
      HomeSectionSpec(
        id: "live-tv",
        title: "Спортивные и ТВ-каналы",
        source: .liveTV
      ),
      HomeSectionSpec(
        id: "tv-shows",
        title: "Передачи и стендап",
        source: .filter({
          var f = LibraryFilter(sort: .recentlyUpdated)
          f.kinds = [.tvShows]
          return f
        }())
      ),
      HomeSectionSpec(
        id: "anime-hits",
        title: "Аниме (по подписчикам)",
        source: .filter({
          var f = LibraryFilter(sort: .watchers)
          f.kinds = [.anime]
          return f
        }())
      ),
      HomeSectionSpec(
        id: "docu-picks",
        title: "Документальные хиты",
        source: .filter({
          var f = LibraryFilter(sort: .views, period: .year)
          f.kinds = [.documentaries]
          return f
        }())
      ),
      HomeSectionSpec(
        id: HomeCatalog.collectionsRowID,
        title: "Collections".localized,
        source: .collections
      ),

      // MARK: Movies tab sections (`contentType == .movie`)
      HomeSectionSpec(
        id: "movies-new",
        title: "Новинки кино",
        source: .filter(LibraryFilter(contentType: .movie, sort: .recentlyAdded))
      ),
      HomeSectionSpec(
        id: "movies-weekly-top",
        title: "Топ фильмов недели",
        source: .filter(LibraryFilter(contentType: .movie, sort: .views, period: .week))
      ),
      HomeSectionSpec(
        id: "movies-monthly-hits",
        title: "Главные хиты месяца",
        source: .filter(LibraryFilter(contentType: .movie, sort: .views, period: .month))
      ),
      HomeSectionSpec(
        id: "movies-4k",
        title: "Новые релизы в 4K UHD",
        source: .filter({
          var f = LibraryFilter(contentType: .movie, sort: .recentlyAdded)
          f.minimumQuality = .uhd4K
          return f
        }())
      ),
      HomeSectionSpec(
        id: "movies-top-imdb",
        title: "Высокий рейтинг IMDb",
        source: .filter({
          var f = LibraryFilter(contentType: .movie, sort: .imdbRating)
          f.yearFrom = 2020
          return f
        }())
      ),
      HomeSectionSpec(
        id: "movies-community",
        title: "Выбор зрителей Кинопаба",
        source: .filter(LibraryFilter(contentType: .movie, sort: .rating, period: .year))
      ),
      HomeSectionSpec(
        id: "movies-scifi",
        title: "Фантастика и Фэнтези",
        source: .filter(LibraryFilter(contentType: .movie, sort: .views, genreIDs: [4, 5], period: .year))
      ),
      HomeSectionSpec(
        id: "movies-thriller",
        title: "Остросюжетные триллеры и детективы",
        source: .filter(LibraryFilter(contentType: .movie, sort: .views, genreIDs: [7, 13, 17], period: .year))
      ),
      HomeSectionSpec(
        id: "movies-action",
        title: "Экшен и Приключения",
        source: .filter(LibraryFilter(contentType: .movie, sort: .views, genreIDs: [2, 8], period: .year))
      ),
      HomeSectionSpec(
        id: "movies-comedy",
        title: "Комедии для хорошего вечера",
        source: .filter(LibraryFilter(contentType: .movie, sort: .views, genreIDs: [1], period: .year))
      ),
      HomeSectionSpec(
        id: "movies-drama",
        title: "Сильные драмы и биографии",
        source: .filter({
          var f = LibraryFilter(contentType: .movie, sort: .imdbRating, genreIDs: [9, 3])
          f.yearFrom = 2018
          return f
        }())
      ),
      HomeSectionSpec(
        id: "movies-horror",
        title: "Хорроры и Мистика",
        source: .filter(LibraryFilter(contentType: .movie, sort: .views, genreIDs: [12, 11], period: .year))
      ),
      HomeSectionSpec(
        id: "movies-family",
        title: "Мультфильмы и Семейное кино",
        source: .filter(LibraryFilter(contentType: .movie, sort: .views, genreIDs: [23, 6], period: .year))
      ),
      HomeSectionSpec(
        id: "movies-docu",
        title: "Документальные фильмы",
        source: .filter(LibraryFilter(contentType: .documovie, sort: .views, period: .year))
      ),
      HomeSectionSpec(
        id: "movies-standup",
        title: "Стендап-спешлы",
        source: .filter({
          var f = LibraryFilter(sort: .recentlyAdded)
          f.kinds = [.standup]
          return f
        }())
      ),

      // MARK: Series & Shows tab sections (`contentType == .serial`)
      HomeSectionSpec(
        id: "series-updated",
        title: "Новые серии на этой неделе",
        source: .filter(LibraryFilter(contentType: .serial, sort: .recentlyUpdated))
      ),
      HomeSectionSpec(
        id: "series-new",
        title: "Новые сериалы и премьеры",
        source: .filter(LibraryFilter(contentType: .serial, sort: .recentlyAdded))
      ),
      HomeSectionSpec(
        id: "series-watchers",
        title: "Главные сериалы по подписчикам",
        source: .filter(LibraryFilter(contentType: .serial, sort: .watchers))
      ),
      HomeSectionSpec(
        id: "series-weekly-top",
        title: "Топ сериалов недели",
        source: .filter(LibraryFilter(contentType: .serial, sort: .views, period: .week))
      ),
      HomeSectionSpec(
        id: "series-finished",
        title: "Завершённые сериалы целиком",
        source: .filter({
          var f = LibraryFilter(contentType: .serial, sort: .watchers)
          f.finishedOnly = true
          return f
        }())
      ),
      HomeSectionSpec(
        id: "series-top-imdb",
        title: "Золотой фонд IMDb",
        source: .filter({
          var f = LibraryFilter(contentType: .serial, sort: .imdbRating)
          f.yearFrom = 2015
          return f
        }())
      ),
      HomeSectionSpec(
        id: "series-4k",
        title: "Сериалы в 4K UHD",
        source: .filter({
          var f = LibraryFilter(contentType: .serial, sort: .recentlyUpdated)
          f.minimumQuality = .uhd4K
          return f
        }())
      ),
      HomeSectionSpec(
        id: "series-crime",
        title: "Детективы, Триллеры и Криминал",
        source: .filter(LibraryFilter(contentType: .serial, sort: .watchers, genreIDs: [13, 7, 17]))
      ),
      HomeSectionSpec(
        id: "series-scifi",
        title: "Фантастика и Фэнтези",
        source: .filter(LibraryFilter(contentType: .serial, sort: .watchers, genreIDs: [4, 5]))
      ),
      HomeSectionSpec(
        id: "series-drama",
        title: "Престижные драмы",
        source: .filter(LibraryFilter(contentType: .serial, sort: .watchers, genreIDs: [9]))
      ),
      HomeSectionSpec(
        id: "series-comedy",
        title: "Комедийные сериалы и ситкомы",
        source: .filter(LibraryFilter(contentType: .serial, sort: .watchers, genreIDs: [1]))
      ),
      HomeSectionSpec(
        id: "series-anime",
        title: "Аниме-сериалы",
        source: .filter(LibraryFilter(contentType: .serial, sort: .watchers, genreIDs: [25]))
      ),
      HomeSectionSpec(
        id: "series-dorama",
        title: "Дорамы",
        source: .filter(LibraryFilter(contentType: .serial, sort: .watchers, genreIDs: [107]))
      ),
      HomeSectionSpec(
        id: "series-docu",
        title: "Документальные сериалы",
        source: .filter(LibraryFilter(contentType: .docuserial, sort: .views, period: .year))
      ),
      HomeSectionSpec(
        id: "series-tvshows",
        title: "Телешоу и Передачи",
        source: .filter(LibraryFilter(contentType: .tvshow, sort: .recentlyUpdated))
      ),
    ]
    for spec in specs {
      dict[spec.id] = spec
    }
    return dict
  }()

  /// Ordered, visible section specs for this catalog (`Watch Now`, `Movies`, or `Series`)
  /// according to `SectionVisibilityStore`, windowed by `visibleSectionLimit`.
  private var allVisibleSectionMetas: [HomeSectionMeta] {
    switch contentType {
    case .movie:
      return SectionVisibilityStore.shared.visibleMovieSections
    case .serial:
      return SectionVisibilityStore.shared.visibleSeriesSections
    default:
      return SectionVisibilityStore.shared.visibleHomeSections
    }
  }

  var activeHomeSections: [HomeSectionSpec] {
    let all = allVisibleSectionMetas.compactMap { Self.homeSectionSpecsByID[$0.id] }
    return Array(all.prefix(visibleSectionLimit))
  }

  var hasMoreSections: Bool {
    visibleSectionLimit < allVisibleSectionMetas.count
  }

  @Published public private(set) var visibleSectionLimit: Int = 8
  @Published public private(set) var liveChannels: [TVChannel] = []

  func loadMoreSections() {
    visibleSectionLimit += 4
    Task { await fetch() }
  }

  /// Typed Movies / Series catalogs have their own section lists and hero banner,
  /// while Continue Watching and Collections live on Watch Now (`contentType == nil`).
  var includesWatchNowExtras: Bool { contentType == nil }
  var supportsHeroBanner: Bool { contentType == nil || contentType == .movie || contentType == .serial }

  static let continueWatchingRowID = "continue-watching"
  static let collectionsRowID = "collections"
  static let liveTVRowID = "live-tv"
  static let topBookmarksRowID = "top-bookmarks"

  /// How far a horizontal shelf has been paged, per row id.
  ///
  /// Home rows used to be one page each, forever: `fetch(… page: nil)` and the
  /// `pagination` block thrown away. This is the state that was missing — without it
  /// there is nowhere to record "page 3 of 40" or "a request is already in flight",
  /// and a near-end signal has nothing to act on.
  private struct PageCursor {
    var loaded: Int
    var total: Int
    var isLoading = false
    var didFail = false

    var hasMore: Bool { loaded < total }
  }

  /// `@Published` so a shelf redraws its tail tile when paging starts, fails or runs
  /// out — the cursor was private state until it had something to say on screen.
  @Published private var cursors: [String: PageCursor] = [:]

  /// What the shelf for `rowID` should be showing at its trailing edge.
  func paginationState(rowID: String, loadedCount: Int) -> PaginationState {
    guard rowID != Self.continueWatchingRowID, let cursor = cursors[rowID] else {
      // Continue Watching is not paginated, so it is never mid-load and never "all of
      // it" — it is simply a list.
      return .idle
    }
    if cursor.isLoading { return PaginationState(phase: .loading, loadedCount: loadedCount) }
    if cursor.didFail { return PaginationState(phase: .failed, loadedCount: loadedCount) }
    if !cursor.hasMore { return PaginationState(phase: .complete, loadedCount: loadedCount) }
    return .idle
  }

  /// The tail tile's retry. Clears the failure so `loadMore` stops declining.
  func retryPagination(rowID: String) {
    cursors[rowID]?.didFail = false
    loadMore(rowID: rowID)
  }

  /// Empty until the first fetch lands — the screen shows a spinner rather than
  /// stand-in artwork, the way the Apple TV app waits.
  @Published public private(set) var rows: [MediaRow] = []
  /// Up to six contained banner cards sampled from the catalog shelves below.
  @Published public private(set) var bannerCards: [MediaCard] = [] {
    didSet { resolveBannerDetails() }
  }
  /// The banner cards re-read from the details payload, by card id. A shelf's payload
  /// has no seasons, so its card cannot say "12 episodes"; the details one can, and it
  /// carries the IMDb id the logo lookup needs. Until it lands the shelf card draws.
  @Published public private(set) var bannerDetails: [Int: MediaCard] = [:]
  /// Title logos for the banner cards, by card id. Missing keys are still in
  /// flight (``.pending``) — the lettered name waits for a confirmed miss.
  @Published public private(set) var bannerLogos: [Int: TitleLogoResolution] = [:]
  @Published public private(set) var isLoaded: Bool = false
  /// True when every shelf failed and there is nothing cached to show — the view
  /// swaps the blank screen for a retry state. Cached rows always win over this flag.
  @Published public private(set) var loadFailed: Bool = false
  /// The failure behind `loadFailed`, so the retry state can say what actually went
  /// wrong (an expired session is not a connection problem).
  @Published public private(set) var loadError: Error?

  private var authState: AuthState
  private var errorHandler: ErrorHandler
  private var itemsService: VideoContentService
  private var actionsService: UserActionsService
  private var collectionsService: CollectionsService
  private var store: ContentStore
  private var localProgressStore: LocalWatchProgressStore
  private let metadataService: MetadataService
  /// Banner cards whose details and logo were already asked for, found or not.
  private var bannerLookups: Set<Int> = []
  /// In-flight detail+logo tasks, cancelled when the banner set changes or on refresh.
  private var bannerTasks: [Int: Task<Void, Never>] = [:]
  private var bag = Set<AnyCancellable>()

  init(itemsService: VideoContentService,
       authState: AuthState,
       errorHandler: ErrorHandler,
       actionsService: UserActionsService = AppContext.shared.actionsService,
       collectionsService: CollectionsService = AppContext.shared.collectionsService,
       store: ContentStore = AppContext.shared.contentStore,
       localProgressStore: LocalWatchProgressStore = AppContext.shared.localProgressStore,
       metadataService: MetadataService = AppContext.shared.metadataService,
       contentType: MediaType? = nil) {
    self.itemsService = itemsService
    self.authState = authState
    self.errorHandler = errorHandler
    self.actionsService = actionsService
    self.collectionsService = collectionsService
    self.store = store
    self.localProgressStore = localProgressStore
    self.metadataService = metadataService
    self.contentType = contentType
    NotificationCenter.default.publisher(for: .localWatchProgressDidChange)
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in
        self?.assembleRows()
      }
      .store(in: &bag)
    NotificationCenter.default.publisher(for: .contentStoreDidInvalidateWatch)
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in
        Task { await self?.refreshContinueWatching() }
      }
      .store(in: &bag)
    NotificationCenter.default.publisher(for: .homeSectionsConfigurationDidChange)
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in
        guard let self else { return }
        self.store.invalidate(family: .catalog)
        self.cursors.removeAll()
        self.assembleRows()
        Task { await self.fetch() }
      }
      .store(in: &bag)
  }

  /// Paints whatever's cached immediately (instant on a warm cache, still empty on a
  /// cold one — same first-launch behaviour as before), then refreshes in the
  /// background only the rows whose TTL expired. A return trip within the TTL costs
  /// zero requests.
  func fetch() async {
    guard authState.userState == .authorized else {
      subscribeForAuth()
      return
    }

    assembleRows()
    isLoaded = !rows.isEmpty
    seedCursorsFromStore()

    let collectionsNeedMigration = includesWatchNowExtras
      && store.cards(.collections).contains { !$0.opensCollection }
    let homeSections = activeHomeSections
    let excludeConcerts = SectionVisibilityStore.shared.excludeConcertsOnHome

    await withTaskGroup(of: Void.self) { group in
      if includesWatchNowExtras {
        group.addTask { [store] in
          await store.refreshIfStale(.continueWatching) { [weak self] in
            guard let self else { throw CancellationError() }
            return try await self.fetchContinueWatchingCards().map(RowItem.card)
          }
        }
      }
      for spec in homeSections {
        switch spec.source {
        case .filter:
          group.addTask { [store] in
            await store.refreshIfStale(.homeSection(spec.id)) { [weak self] in
              guard let self else { throw CancellationError() }
              return try await self.fetchHomeSectionItems(spec, excludeConcerts: excludeConcerts)
            }
          }
        case .topBookmarks:
          group.addTask { [store] in
            await store.refreshIfStale(.homeSection(spec.id)) { [weak self] in
              guard let self else { throw CancellationError() }
              return try await self.fetchTopBookmarksCards().map(RowItem.card)
            }
          }
        case .liveTV:
          group.addTask { [weak self] in
            guard let self else { return }
            await self.fetchLiveChannelsIfNeeded()
          }
        case .collections:
          group.addTask { [store] in
            if collectionsNeedMigration {
              await store.refresh(.collections) { [weak self] in
                guard let self else { throw CancellationError() }
                return try await self.fetchCollectionsPreviewCards().map(RowItem.card)
              }
            } else {
              await store.refreshIfStale(.collections) { [weak self] in
                guard let self else { throw CancellationError() }
                return try await self.fetchCollectionsPreviewCards().map(RowItem.card)
              }
            }
          }
        }
      }
      for shortcut in activeShortcuts {
        group.addTask { [store] in
          await store.refreshIfStale(.shortcut(shortcut.shortcut, shortcut.contentType)) { [weak self] in
            guard let self else { throw CancellationError() }
            return try await self.fetchShortcutItems(shortcut)
          }
        }
      }
    }

    seedCursorsFromStore()
    assembleRows()
    isLoaded = true
    // Catalog shelves always have content when the network cooperates, so an empty
    // screen with at least one failed shelf means an outage, not an empty account.
    let firstShortcutError = activeShortcuts.lazy
      .compactMap { self.store.lastError(.shortcut($0.shortcut, $0.contentType)) }
      .first
    let firstSectionError = homeSections.lazy
      .compactMap { self.store.lastError(.homeSection($0.id)) }
      .first
    let firstError = firstShortcutError ?? firstSectionError
    loadFailed = rows.isEmpty && firstError != nil
    loadError = rows.isEmpty ? firstError : nil
  }

  // MARK: - Paging a horizontal shelf

  /// The user scrolled a shelf to its last loaded card. Fetches the next page and
  /// appends it, or does nothing when there is nothing left.
  ///
  /// **Continue Watching never pages.** It is not one endpoint with pages: it is a
  /// merge of `watching/movies`, `watching/serials` (twice) and `history`, ordered by
  /// what the user touched last. "Page 2" of that has no meaning on the server.
  func loadMore(rowID: String) {
    guard rowID != Self.continueWatchingRowID,
          rowID != Self.topBookmarksRowID,
          rowID != Self.liveTVRowID else { return }
    guard var cursor = cursors[rowID], cursor.hasMore, !cursor.isLoading, !cursor.didFail
    else { return }

    cursor.isLoading = true
    cursors[rowID] = cursor
    let next = cursor.loaded + 1

    Task { [weak self] in
      guard let self else { return }
      defer { self.cursors[rowID]?.isLoading = false }
      do {
        let items = try await self.fetchPage(next, ofRow: rowID)
        guard !items.isEmpty else {
          // Server says there is another page and hands back nothing: stop asking,
          // rather than retrying on every scroll to the end for the rest of the session.
          self.cursors[rowID]?.total = self.cursors[rowID]?.loaded ?? next
          return
        }
        self.store.appendItems(items, for: try self.storeKey(forRow: rowID))
        self.cursors[rowID]?.loaded = next
        self.cursors[rowID]?.didFail = false
        self.assembleRows()
      } catch {
        // The cursor stays where it was, so a retry asks for the same page again. It is
        // flagged rather than silently retried on the next scroll: a failed page that
        // looks like the end of the catalogue is the thing being fixed here.
        self.cursors[rowID]?.didFail = true
        Logger.app.debug("HomeCatalog: page \(next) of \(rowID) failed: \(error)")
      }
    }
  }

  private func fetchPage(_ page: Int, ofRow rowID: String) async throws -> [RowItem] {
    if rowID == Self.collectionsRowID {
      let data = try await collectionsService.fetchCollections(page: page, sort: "views-")
      if let total = data.pagination?.total {
        cursors[rowID]?.total = max(total, 1)
      }
      return data.collections.map { RowItem.card(CollectionMediaCard.make(from: $0)) }
    }
    if let spec = Self.homeSectionSpecsByID[rowID],
       let filter = spec.resolvedFilter(excludeConcerts: SectionVisibilityStore.shared.excludeConcertsOnHome) {
      let data = try await itemsService.fetchItems(filter: filter, page: page)
      cursors[rowID]?.total = max(data.pagination.total, 1)
      return data.items.map(Self.item(for:))
    }
    guard let shortcut = Self.shortcuts.first(where: { $0.id == rowID }) else { return [] }
    let data = try await itemsService.fetch(shortcut: shortcut.shortcut,
                                            contentType: shortcut.contentType,
                                            page: page)
    cursors[rowID]?.total = max(data.pagination.total, 1)
    return data.items.map(Self.item(for:))
  }

  /// Warm cache skips `fetchShortcutItems`, so the cursor that paging reads was
  /// never written. Reconstruct it from the cards already in the store: Home rails
  /// use the server default of 20 per page, and a later `fetchPage` overwrites
  /// `total` with the real pagination. Without this, Movies/Series (and Watch Now
  /// after a TTL-fresh relaunch) would paint page 1 and never ask for more.
  private func seedCursorsFromStore() {
    let defaultPerPage = 20
    for shortcut in activeShortcuts {
      guard cursors[shortcut.id] == nil else { continue }
      let count = store.cards(.shortcut(shortcut.shortcut, shortcut.contentType)).count
      guard count > 0 else { continue }
      let loaded = max(1, (count + defaultPerPage - 1) / defaultPerPage)
      cursors[shortcut.id] = PageCursor(loaded: loaded, total: loaded + 1)
    }
    for spec in activeHomeSections {
      guard cursors[spec.id] == nil else { continue }
      switch spec.source {
      case .filter:
        let count = store.cards(.homeSection(spec.id)).count
        guard count > 0 else { continue }
        let loaded = max(1, (count + defaultPerPage - 1) / defaultPerPage)
        cursors[spec.id] = PageCursor(loaded: loaded, total: loaded + 1)
      case .collections:
        let count = store.cards(.collections).count
        guard count > 0 else { continue }
        let loaded = max(1, (count + defaultPerPage - 1) / defaultPerPage)
        cursors[Self.collectionsRowID] = PageCursor(loaded: loaded, total: loaded + 1)
      case .topBookmarks, .liveTV:
        break
      }
    }
  }

  private func storeKey(forRow rowID: String) throws -> RowKey {
    if rowID == Self.collectionsRowID { return .collections }
    if Self.homeSectionSpecsByID[rowID] != nil { return .homeSection(rowID) }
    guard let shortcut = Self.shortcuts.first(where: { $0.id == rowID }) else {
      throw CancellationError()
    }
    return .shortcut(shortcut.shortcut, shortcut.contentType)
  }

  /// Pull-to-refresh: forces every row to refetch regardless of TTL.
  func refresh() async {
    errorHandler.reset()
    loadFailed = false
    loadError = nil
    cancelBannerLookups()
    if includesWatchNowExtras {
      store.invalidate(family: .watch)
    }
    store.invalidate(family: .catalog)
    // A refresh returns every shelf to page 1, so the cursors have to go back with it —
    // otherwise a row that had reached page 5 would ask for page 6 of a one-page row.
    cursors.removeAll()
    await fetch()
  }

  /// Re-apply local resume onto the cached Continue Watching row. Cheap: no
  /// network. Home's `.task` does not re-run when returning from the player
  /// (`NavigationStack` root stays mounted), so this is also the appear path.
  func repaintFromLocalProgress() {
    assembleRows()
  }

  /// Force a Continue Watching refetch and paint. Used when coming to the
  /// foreground and when a watch-family invalidate fires — `refreshIfStale`
  /// plus a 60 s TTL is why the row kept showing the last snapshot while the
  /// network log still filled with requests (shelves, banner details, metadata).
  func refreshContinueWatching() async {
    guard includesWatchNowExtras, authState.userState == .authorized else {
      assembleRows()
      return
    }
    await store.refresh(.continueWatching) { [weak self] in
      guard let self else { throw CancellationError() }
      return try await self.fetchContinueWatchingCards().map(RowItem.card)
    }
    assembleRows()
  }

  private func assembleRows() {
    var assembled: [MediaRow] = []
    if includesWatchNowExtras {
      let continueWatchingCards = paintedContinueWatchingCards()
      if !continueWatchingCards.isEmpty {
        assembled.append(MediaRow(id: Self.continueWatchingRowID,
                                  title: "Continue Watching".localized,
                                  cards: continueWatchingCards))
      }
    }

    var appendedAnyConfiguredSection = false
    for spec in activeHomeSections {
      switch spec.source {
      case .filter:
        let cards = store.cards(.homeSection(spec.id))
        guard !cards.isEmpty else { continue }
        appendedAnyConfiguredSection = true
        assembled.append(MediaRow(id: spec.id,
                                  title: spec.title,
                                  cards: cards))
      case .topBookmarks:
        let cards = store.cards(.homeSection(spec.id))
        guard !cards.isEmpty else { continue }
        appendedAnyConfiguredSection = true
        assembled.append(MediaRow(id: spec.id,
                                  title: spec.title,
                                  cards: cards))
      case .liveTV:
        // Live TV renders as a dedicated 16:9 channel logo rail (`liveChannels`) on tvOS.
        break
      case .collections:
        let collectionsCards = store.cards(.collections)
        if !collectionsCards.isEmpty {
          appendedAnyConfiguredSection = true
          assembled.append(MediaRow(id: Self.collectionsRowID,
                                    title: spec.title,
                                    cards: collectionsCards,
                                    destination: Route.collections))
        }
      }
    }

    // Fallback to classic shortcut rows if no filter-backed sections have populated
    // (for example in offline/fixture environments that only seed `.shortcut` keys).
    if !appendedAnyConfiguredSection {
      for shortcut in activeShortcuts {
        let cards = store.cards(.shortcut(shortcut.shortcut, shortcut.contentType))
        guard !cards.isEmpty else { continue }
        assembled.append(MediaRow(id: shortcut.id,
                                  title: shortcut.title.localized,
                                  cards: cards,
                                  destination: Route.shortcutItems(shortcut.shortcut,
                                                                   shortcut.contentType,
                                                                   title: shortcut.title.localized)))
      }
      if includesWatchNowExtras {
        let collectionsCards = store.cards(.collections)
        if !collectionsCards.isEmpty,
           !assembled.contains(where: { $0.id == Self.collectionsRowID }) {
          assembled.append(MediaRow(id: Self.collectionsRowID,
                                    title: "Collections".localized,
                                    cards: collectionsCards,
                                    destination: Route.collections))
        }
      }
    }
    rows = assembled
    refreshBannerCards(from: assembled)
#if os(tvOS)
    // Watch Now is what the Top Shelf mirrors; a typed catalog is not.
    if includesWatchNowExtras, authState.userState == .authorized {
      TopShelfPublisher.publish(rows: assembled, store: store)
    }
#endif
  }

  private func paintedContinueWatchingCards() -> [MediaCard] {
    Self.paintedContinueWatchingCards(store: store, localProgressStore: localProgressStore)
  }

  /// Read-time overlay: `ContentStore` still holds the last server snapshot (and its
  /// TTL). Local progress paints the bar, hides a just-finished film, and steps a
  /// series to the next episode without rewriting `rows-v2.json` on every player tick.
  ///
  /// Static because it is **the** Continue Watching list, not Home's copy of it: the
  /// player's Up Next tab reads the same cards.
  static func paintedContinueWatchingCards(store: ContentStore,
                                           localProgressStore: LocalWatchProgressStore) -> [MediaCard] {
    let stored = store.cards(.continueWatching)
    let entries = localProgressStore.allEntries()
    let locals = entries.map { entry in
      ContinueWatchingLocalOverlay.Local(
        itemID: entry.id,
        isSeries: entry.item.isEpisodicType || entry.season != nil,
        season: entry.season,
        episode: entry.episode,
        isFinished: entry.watch.isFinished,
        isResumable: entry.watch.isResumable,
        progress: entry.watch.resumeFraction,
        updatedAt: entry.updatedAt,
        // The read-time half of the same rule the fetch applies: a title the server has
        // not listed may draw its own card only once it is past the entry floor.
        canInsert: entry.watch.earnsContinueWatchingCard
      )
    }
    let plan = ContinueWatchingLocalOverlay.plan(
      cards: stored.map {
        ContinueWatchingLocalOverlay.Card(itemID: $0.itemID,
                                          isSeries: $0.isSeries,
                                          season: $0.season,
                                          video: $0.video,
                                          seasonCount: $0.seasonCount,
                                          progress: $0.progress)
      },
      locals: locals
    )
    let storedByID = Dictionary(stored.map { ($0.itemID, $0) }, uniquingKeysWith: { _, last in last })
    let entryByID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
    return plan.order.compactMap { id -> MediaCard? in
      let base: MediaCard?
      if plan.insertIDs.contains(id), let entry = entryByID[id] {
        base = Self.card(for: WatchingItem(mediaItem: entry.item),
                         detail: nil,
                         history: nil,
                         finishedEpisodes: [:],
                         local: entry,
                         isInHistory: true,
                         isInWatchlist: false,
                         cached: nil)
      } else {
        base = storedByID[id]
      }
      guard let base else { return nil }
      guard let mutation = plan.mutations[id] else { return base }
      return base.withContinueWatching(progress: mutation.progress,
                                       season: mutation.season,
                                       video: mutation.video,
                                       overlayLabel: mutation.overlayLabel)
    }
  }

  /// v1 hack: up to six unique titles drawn at random from the catalog shelves
  /// (not Continue Watching). Prefer cards that already carry wide artwork.
  /// Keeps the previous selection when most of it is still in the pool so a
  /// background refresh does not reshuffle the banner under the remote.
  /// Skipped entirely when `FeatureFlags.homeBannerEnabled` is off — no sampling and
  /// therefore no wide-poster fetches from `HomeBannerCardView`.
  private func refreshBannerCards(from rows: [MediaRow]) {
    guard supportsHeroBanner, FeatureFlags.homeBannerEnabled else {
      if !bannerCards.isEmpty { bannerCards = [] }
      return
    }

    let continueWatchingTopIDs = Set(
      rows.first(where: { $0.id == Self.continueWatchingRowID })?
        .cards.prefix(4).map(\.itemID) ?? []
    )

    var seen = Set<Int>()
    var pool: [MediaCard] = []
    for row in rows where row.id != Self.continueWatchingRowID && row.id != Self.collectionsRowID {
      for card in row.cards where !card.isWatched && seen.insert(card.id).inserted {
        pool.append(card)
      }
    }

    let preferred = pool.filter { $0.backdropURL != nil }
    let baseSource = preferred.isEmpty ? pool : preferred

    // Soft-weight candidates: avoid duplicating the first 4 Continue Watching cards right
    // below the banner when there are enough candidates, and boost bookmarked/followed items.
    let deDuped = baseSource.filter { !continueWatchingTopIDs.contains($0.itemID) }
    let source = deDuped.count >= 4 ? deDuped : baseSource
    let sourceIDs = Set(source.map(\.id))

    let kept = bannerCards.filter { sourceIDs.contains($0.id) }
    if kept.count >= min(3, source.count), !source.isEmpty {
      var next = kept
      if next.count < 6 {
        let missing = source.filter { card in !next.contains(where: { $0.id == card.id }) }
        next.append(contentsOf: missing.shuffled().prefix(6 - next.count))
      }
      bannerCards = Array(next.prefix(6))
      return
    }

    let bookmarked = source.filter {
      ($0.viewerState.isBookmarked == true) || ($0.viewerState.isFollowing == true)
    }
    let others = source.filter {
      ($0.viewerState.isBookmarked != true) && ($0.viewerState.isFollowing != true)
    }
    let combined = (bookmarked.shuffled().prefix(2) + others.shuffled()).prefix(6)
    bannerCards = Array(combined)
  }

  /// One details call and one metadata lookup per banner title — the same calls (and
  /// caches) a detail page makes, so opening a banner title afterwards costs nothing
  /// more. The logo waits for the details card: a cached shelf card may predate the
  /// IMDb id and would skip the lookup. Stale tasks are cancelled when the banner
  /// set changes; failed ids retry on the next `refresh()`.
  private func resolveBannerDetails() {
    let live = Set(bannerCards.map(\.id))
    for id in bannerTasks.keys where !live.contains(id) {
      bannerTasks[id]?.cancel()
      bannerTasks.removeValue(forKey: id)
    }
    bannerLookups = bannerLookups.intersection(live)

    for card in bannerCards where bannerLookups.insert(card.id).inserted {
      let id = card.id
      if bannerLogos[id] == nil { bannerLogos[id] = .pending }
      bannerTasks[id] = Task { [weak self, itemsService, metadataService] in
        let item = try? await itemsService.fetchDetails(for: "\(card.itemID)", excludeLinks: true).item
        guard let self, !Task.isCancelled, self.bannerCards.contains(where: { $0.id == id }) else { return }
        let detailed = item.map { MediaCard($0) }
        if let detailed { self.bannerDetails[id] = detailed }
        guard let identity = MediaIdentity(card: detailed ?? card) else {
          self.bannerLogos[id] = .missing
          return
        }
        let url = await metadataService.metadata(for: identity).titleLogoURL
        guard !Task.isCancelled, self.bannerCards.contains(where: { $0.id == id }) else { return }
        self.bannerLogos[id] = url.map { .url($0) } ?? .missing
      }
    }
  }

  private func cancelBannerLookups() {
    bannerTasks.values.forEach { $0.cancel() }
    bannerTasks.removeAll()
    bannerLookups.removeAll()
    bannerLogos.removeAll()
  }

  // MARK: - Continue watching actions

  /// Clears history for the title and drops it from the row immediately — the store
  /// mutation is the source of truth `assembleRows()` reads back, so no local `rows`
  /// bookkeeping is needed here anymore.
  func hide(_ card: MediaCard) {
    store.removeCard(id: card.id, from: .continueWatching)
    localProgressStore.clear(id: card.itemID)
    assembleRows()
    Task {
      do {
        try await actionsService.clearHistoryForItem(id: card.itemID)
      } catch {
        errorHandler.setError(error)
        store.invalidate(family: .watch)
        await fetch()
      }
    }
  }

  /// Marks the resume point's episode (or the film) watched, then removes the card —
  /// Continue Watching has nothing left to offer for a finished title.
  func toggleWatched(_ card: MediaCard) {
    guard let video = card.video else { return }
    store.removeCard(id: card.id, from: .continueWatching)
    localProgressStore.clear(id: card.itemID)
    assembleRows()
    Task {
      do {
        try await actionsService.toggleWatching(id: card.itemID, video: video, season: card.season)
      } catch {
        errorHandler.setError(error)
        store.invalidate(family: .watch)
        await fetch()
      }
    }
  }

  // MARK: - Continue watching

  private func fetchContinueWatchingCards() async throws -> [MediaCard] {
    async let moviesTask = try? itemsService.fetchWatchingMovies().items
    async let allSerialsTask = try? itemsService.fetchWatchingSerials(subscribedOnly: false).items
    async let watchlistTask = try? itemsService.fetchWatchingSerials(subscribedOnly: true).items
    async let historyTask = try? itemsService.fetchHistory(page: nil, perPage: 20).history

    let moviesResult = await moviesTask
    let serialsResult = await allSerialsTask
    let watchlistResult = await watchlistTask
    let historyResult = await historyTask

    // Each source degrades independently (one endpoint down still shows the other
    // three) — but if every single one failed, this is a network outage, not "the
    // user has nothing to continue watching". Throw so the store keeps the last
    // known-good row instead of caching an empty one.
    if moviesResult == nil, serialsResult == nil, watchlistResult == nil, historyResult == nil {
      throw ContinueWatchingFetchError.allSourcesFailed
    }

    let movies = moviesResult ?? []
    let serials = serialsResult ?? []
    let watchlist = watchlistResult ?? []
    let history = historyResult ?? []

    let watchlistIDs = Set(watchlist.map(\.id))
    var lastSeen = ContinueWatchingOrder.lastSeenByItemID(history)
    let newestEntry = Self.newestEntryByItemID(history)
    let finishedEpisodes = Self.finishedEpisodesByItemID(history)
    let historyIDs = Set(history.map(\.item.id))
    let localEntries = localProgressStore.allEntries()
    let localByID = Dictionary(uniqueKeysWithValues: localEntries.map { ($0.id, $0) })
    let cached = store.cards(.continueWatching)
    let cachedByID = Dictionary(cached.map { ($0.itemID, $0) }, uniquingKeysWith: { _, last in last })

    var pool = ContinueWatchingOrder.mergePool(movies: movies, serials: serials, watchlist: watchlist)

    // Titles only present in recent history still belong in "recently started".
    // Drop finished rows (watched to credits) so they don't invite a resume.
    let now = Date()
    for entry in history {
      if let watch = entry.watchProgress, watch.isFinished { continue }
      guard let date = entry.lastSeenDate,
            now.timeIntervalSince(date) <= ContinueWatchingOrder.recentWindow,
            !pool.contains(where: { $0.id == entry.item.id }),
            let item = WatchingItem(historyEntry: entry) else { continue }
      pool.append(item)
    }

    // Locally-started titles the backend doesn't list yet, and only past
    // `enterContinueWatchingSeconds` — a trailer sampled for a minute is not something
    // to carry on with, and a local-only card has nothing to take it back out again.
    // Recency still counts for titles the server *does* list: touching one is touching
    // it, however briefly.
    // Finished films stay out. Finished series stay only if a server source still
    // lists them — re-inserting would invent E+1 after the title left watching.
    for entry in localEntries {
      if entry.watch.isFinished {
        if entry.item.isEpisodicType || entry.season != nil {
          lastSeen[entry.id] = Date(timeIntervalSince1970: entry.updatedAt)
        }
        continue
      }
      lastSeen[entry.id] = Date(timeIntervalSince1970: entry.updatedAt)
      if !pool.contains(where: { $0.id == entry.id }),
         entry.watch.earnsContinueWatchingCard {
        pool.append(WatchingItem(mediaItem: entry.item))
      }
    }

    // Drop server-listed films that local progress already considers finished.
    // Series stay: finishing an episode is not finishing the title.
    pool.removeAll { item in
      guard let local = localByID[item.id], local.watch.isFinished else { return false }
      return !item.type.contains("serial")
    }

    var position = ContinueWatchingOrder.positionByItemID(history)
    for entry in localEntries {
      position[entry.id] = entry.position
    }
    pool = ContinueWatchingOrder.kept(items: pool,
                                      watchlistIDs: watchlistIDs,
                                      lastSeen: lastSeen,
                                      position: position,
                                      now: now)

    let ordered = Array(ContinueWatchingOrder.ordered(items: pool,
                                                     watchlistIDs: watchlistIDs,
                                                     lastSeen: lastSeen)
                          .prefix(ContinueWatchingOrder.maxItems))

    // What the server's own watching lists carry. Anything else came in from history or
    // this device, and only its details payload says what the server counts as watched.
    let serverListed = Set(movies.map(\.id) + serials.map(\.id) + watchlist.map(\.id))
    // What has to move for a title's payload to be asked for again: the server's counts,
    // its newest history row, this device's play head.
    let versions = Dictionary(uniqueKeysWithValues: ordered.map { item in
      (item.id, [item.watched, item.total, item.new,
                 lastSeen[item.id].map { Int($0.timeIntervalSince1970) },
                 localByID[item.id].map { Int($0.updatedAt) }]
        .map { $0.map(String.init) ?? "-" }.joined(separator: "/"))
    })
    let details = await titleDetails(for: ordered, serverListed: serverListed, versions: versions)

    return ordered.compactMap {
      Self.card(for: $0,
                detail: details[$0.id],
                history: newestEntry[$0.id],
                finishedEpisodes: finishedEpisodes[$0.id] ?? [:],
                local: localByID[$0.id],
                isInHistory: historyIDs.contains($0.id) || localByID[$0.id] != nil,
                isInWatchlist: watchlistIDs.contains($0.id),
                cached: cachedByID[$0.id])
    }
  }

  /// How many titles one refresh may fetch payloads for: the whole row. Anything past it
  /// is a guess from counts (`ContinueWatchingEpisode.forSeries`).
  private static let detailLimit = ContinueWatchingOrder.maxItems

  /// Payloads already fetched this session, with the version they answered
  /// (`fetchContinueWatchingCards`). A refresh reuses one until its title moves. Not on
  /// disk: tvOS purges `Caches/`, and a cold launch asking once is the price.
  private static var detailCache: [Int: (version: String, item: MediaItem)] = [:]

  /// The series behind the cards, because **only the title itself knows where its
  /// seasons end and which episodes the server counts as watched.** Without it the row
  /// offered "S1, E9" on an eight-episode season (nothing to play at all) and re-offered
  /// an episode whose last five minutes were credits.
  ///
  /// **A title the server's watching lists do not carry** — it came in from history or
  /// this device — is always asked for, film or series. Leaving the lists is how the server
  /// says "done", and history only has a play head, which our time window judges
  /// differently from the server's own watched flag: VisionQuest S1E2 at 2434 of 2706 s
  /// was watched on the detail page and "in progress" here (2026-10-16). The payload's
  /// flags are the same answer the detail page gives.
  ///
  /// Every series is asked for too: only its payload knows where seasons end and which
  /// episodes the server counts as watched. A guess from counts offered Invasion
  /// «S3, E30» on a ten-episode season — `watched: 29` is the whole series' count — and
  /// the old rule of trusting a cached card's S/E kept that guess for good. A payload is
  /// reused while its title has not moved (`versions`), so a refresh after nothing
  /// happened costs no request. A listed film needs none: the list is the server saying
  /// it is unfinished.
  private func titleDetails(for items: [WatchingItem],
                            serverListed: Set<Int>,
                            versions: [Int: String]) async -> [Int: MediaItem] {
    var byID: [Int: MediaItem] = [:]
    var ids: [Int] = []
    for item in items {
      let isSeries = item.type.contains("serial")
      if serverListed.contains(item.id), !isSeries { continue }
      if let hit = Self.detailCache[item.id], hit.version == versions[item.id] {
        byID[item.id] = hit.item
        continue
      }
      ids.append(item.id)
      if ids.count >= Self.detailLimit { break }
    }
    guard !ids.isEmpty else { return byID }

    return await withTaskGroup(of: (Int, MediaItem?).self) { group in
      for id in ids {
        group.addTask { [itemsService] in
          let item = try? await itemsService.fetchDetails(
            for: "\(id)",
            excludeLinks: FeatureFlags.seriesDetailsWithoutLinks
          ).item
          // Every `/v1/watching*` call keys on the item id, and an episode only carries
          // it once its season has been stamped — see `Episode.metadata`.
          item?.seasons?.forEach { $0.mediaId = item?.id }
          return (id, item)
        }
      }
      for await (id, item) in group {
        guard let item else { continue }
        byID[id] = item
        if let version = versions[id] { Self.detailCache[id] = (version, item) }
      }
      return byID
    }
  }

  /// Item id → season → the episodes that season's history rows ran to the credits.
  /// The full picture history can give, rather than only its most recent row.
  private static func finishedEpisodesByItemID(_ history: [HistoryEntry]) -> [Int: [Int: Set<Int>]] {
    history.reduce(into: [Int: [Int: Set<Int>]]()) { result, entry in
      guard entry.isEpisode,
            entry.watchProgress?.isFinished == true,
            let season = entry.media?.snumber,
            let number = entry.media?.number else { return }
      result[entry.item.id, default: [:]][season, default: []].insert(number)
    }
  }

  private static func newestEntryByItemID(_ history: [HistoryEntry]) -> [Int: HistoryEntry] {
    history.reduce(into: [Int: HistoryEntry]()) { result, entry in
      guard let date = entry.lastSeenDate else { return }
      if let existing = result[entry.item.id], let seen = existing.lastSeenDate, seen >= date { return }
      result[entry.item.id] = entry
    }
  }

  /// Continue-watching cards are landscape wide covers — episode stills are too
  /// anonymous to recognise a title from across the room. History still supplies the
  /// S/E label and resume bar; local progress fills gaps before the server catches up.
  private static func card(for item: WatchingItem,
                           detail: MediaItem?,
                           history: HistoryEntry?,
                           finishedEpisodes: [Int: Set<Int>],
                           local: LocalWatchEntry?,
                           isInHistory: Bool,
                           isInWatchlist: Bool,
                           cached: MediaCard?) -> MediaCard? {
    let isSeries = item.type.contains("serial")
    let video: Int?
    let season: Int?
    // True while the viewer is mid-video: only then do a progress bar and a "N left"
    // label belong on the card. A film is always "resuming" — there is one video.
    var isResuming = true

    if isSeries {
      // The newest history row is where the viewer *was*, not what to play next: on a
      // finished episode this offered it again, with its full runtime under it.
      if let detail, detail.isSeries {
        // The title's own answer, and the same one the detail page's Play button gives —
        // first episode the server does not count as watched, across season boundaries.
        // `playAgain` means there is no such episode: every one of them is watched, and
        // a finished series has no business in Continue Watching.
        guard detail.playbackAction != .playAgain,
              let (nextSeason, episode) = detail.primaryEpisode else { return nil }
        video = episode.number
        season = nextSeason.number
        isResuming = episode.watchProgress.isResumable
      } else {
        // No payload for this one (request failed, or past the fetch cap): fall back to
        // what history and the counters can say. Which season the viewer is in, and
        // everything history says they finished in it — history is ordered by when a
        // row was played, so the newest row is not the furthest episode.
        let currentSeason = history?.media?.snumber ?? local?.season ?? cached?.season
        let next = ContinueWatchingEpisode.forSeries(
          local: local.map { ($0.season, $0.episode, $0.watch.isFinished) },
          history: history.map { ($0.media?.snumber, $0.media?.number, $0.watchProgress?.isFinished ?? false) },
          finishedInSeason: currentSeason.flatMap { finishedEpisodes[$0] } ?? [],
          watchedCount: item.watched,
          total: item.total
        )
        // Live sources beat the last snapshot's S/E — trusting cache here is why
        // a refetch left the same episode on screen after another device moved on.
        if next.hasEpisode {
          video = next.episode
          season = next.season ?? cached?.season
          isResuming = next.isResuming
        } else if (item.new ?? 0) > 0 {
          video = cached?.video
          season = cached?.season ?? next.season
          isResuming = cached?.progress != nil
        } else {
          return nil
        }
      }
    } else {
      // The film's own flag, when we asked for it: watched is watched, whatever the play
      // head says about the credits.
      if let detail, detail.playbackAction == .playAgain { return nil }
      video = history?.media?.number ?? local?.episode ?? 1
      season = nil
    }

    // The episode the card actually offers, when the payload gave us one — its own
    // progress and runtime, not the previous episode's.
    let offered = detail?.seasons?
      .first { $0.number == season }?.episodes
      .first { $0.number == video }
    let localFraction = local?.watch.resumeFraction
    // Episode resume only — never serial watched/total (that is not a scrubber) — and
    // never the *previous* episode's progress under a fresh one.
    let episodeProgress = isResuming
      ? (offered?.watchProgress.fraction ?? localFraction ?? history?.progress)
      : nil
    let durationSeconds = offered.map(\.duration)
      ?? (isResuming
          ? (cached?.durationSeconds ?? Self.durationSeconds(history: history, local: local))
          : nil)
    // The details payload when it was fetched, else the snapshot the player cached.
    let seasonCount = (detail?.seasons ?? local?.item.seasons)?.count
    let overlay = Self.overlayLabel(isSeries: isSeries, season: season, episode: video,
                                    seasonCount: seasonCount)
    let newCount = item.new.flatMap { $0 > 0 ? $0 : nil }

    return MediaCard(id: item.id,
                     posterURL: item.posters.medium,
                     title: item.localizedTitle,
                     subtitle: item.originalTitle,
                     progress: episodeProgress,
                     badge: newCount.map { "+\($0)" },
                     backdropURL: landscapeImageURL(for: item, history: history, local: local),
                     landscapeImageURL: landscapeImageURL(for: item, history: history, local: local),
                     overlayLabel: overlay,
                     itemID: item.id,
                     video: video,
                     season: season,
                     seasonCount: seasonCount,
                     mediaID: isResuming ? history?.media?.id : nil,
                     isWatched: false,
                     isSeries: isSeries,
                     isInHistory: isInHistory,
                     viewerState: ViewerState(isFollowing: isSeries ? isInWatchlist : nil),
                     durationSeconds: durationSeconds,
                     primaryAction: .play)
  }

  private static func durationSeconds(history: HistoryEntry?, local: LocalWatchEntry?) -> Int? {
    if let duration = history?.media?.duration, duration >= 60 { return duration }
    if let duration = local?.duration, duration >= 60 { return Int(duration) }
    return nil
  }

  /// The title's wide cover, as Library Continue and History show it — not the episode's
  /// thumbnail. kino.pub's thumbnail is a random frame of the episode, often black, and
  /// says nothing about which show it is (Sasha, 2026-10-16). The still is left only for a
  /// title with no wide art at all; a 2:3 poster is never cropped into the 16:9 box. Live,
  /// every title on the row had one (24 of 24 answered 200, 2026-10-16).
  private static func landscapeImageURL(for item: WatchingItem,
                                        history: HistoryEntry?,
                                        local: LocalWatchEntry?) -> String? {
    let posters = history?.item.posters ?? local?.item.posters ?? item.posters
    let still = history?.media?.thumbnail.flatMap { $0.isEmpty ? nil : $0 }
    return MediaCard.titleWideArtwork(posters: posters) ?? still
  }

  /// Says whichever episode the card is actually offering — it used to derive its own
  /// S/E from history and could disagree with the one Play would open.
  private static func overlayLabel(isSeries: Bool, season: Int?, episode: Int?,
                                   seasonCount: Int?) -> String? {
    guard isSeries else { return nil }
    guard let episode else { return nil }
    return EpisodeText(season: season.flatMap { $0 > 0 ? $0 : nil }, number: episode,
                       seasonCount: seasonCount)
      .text(for: .continueWatchingCard)
  }

  // MARK: - Catalog shortcuts & Home sections

  private func fetchShortcutItems(_ shortcut: Shortcut) async throws -> [RowItem] {
    let data = try await itemsService.fetch(shortcut: shortcut.shortcut,
                                             contentType: shortcut.contentType,
                                             page: nil)
    // Page 1 is also where we learn how many there are — the only place the API says so.
    cursors[shortcut.id] = PageCursor(loaded: 1, total: max(data.pagination.total, 1))
    return data.items.map(Self.item(for:))
  }

  private func fetchHomeSectionItems(_ spec: HomeSectionSpec, excludeConcerts: Bool) async throws -> [RowItem] {
    guard let filter = spec.resolvedFilter(excludeConcerts: excludeConcerts) else { return [] }
    let data = try await itemsService.fetchItems(filter: filter, page: nil)
    cursors[spec.id] = PageCursor(loaded: 1, total: max(data.pagination.total, 1))
    return data.items.map(Self.item(for:))
  }

  private func fetchTopBookmarksCards() async throws -> [MediaCard] {
    let folders = try await itemsService.fetchBookmarks().items
    guard !folders.isEmpty else { return [] }
    var seen = Set<Int>()
    var items: [MediaItem] = []
    for folder in folders.prefix(2) {
      guard let page = try? await itemsService.fetchBookmarkItems(id: "\(folder.id)", page: 1) else {
        continue
      }
      for item in page.items where seen.insert(item.id).inserted {
        if item.playbackAction != .playAgain {
          items.append(item)
        }
      }
    }
    return items.prefix(20).map { MediaCard($0) }
  }

  private func fetchLiveChannelsIfNeeded() async {
    guard liveChannels.isEmpty else { return }
    if let channels = try? await itemsService.fetchTVChannels(), !channels.isEmpty {
      liveChannels = Array(channels.prefix(15))
    }
  }

  private static func item(for item: MediaItem) -> RowItem {
    BookmarkMembershipStore.shared.seed(from: item)
    return .title(item)
  }

  // MARK: - Collections

  /// First page of curated collections, as poster tiles — `/v1/collections` ships
  /// each collection's own artwork + counters (no per-collection item fetch).
  private func fetchCollectionsPreviewCards() async throws -> [MediaCard] {
    let data = try await collectionsService.fetchCollections(page: nil, sort: "views-")
    cursors[Self.collectionsRowID] = PageCursor(loaded: 1,
                                                total: max(data.pagination?.total ?? 1, 1))
    // No longer capped at twelve: the row pages like the catalogue shelves now, and a
    // hard cap would have been the thing stopping it. `Route.collections` stays as the
    // full grid for anyone who would rather not scroll sideways.
    return data.collections.map(CollectionMediaCard.make(from:))
  }

  private func subscribeForAuth() {
    authState.$userState.filter({ $0 == .authorized })
      .first()
      .removeDuplicates()
      .sink { [weak self] _ in
        Task { await self?.fetch() }
      }.store(in: &bag)
  }
}

private enum ContinueWatchingFetchError: Error {
  /// All four underlying calls (movies/serials/watchlist/history) failed — a real
  /// outage, not "nothing to continue watching". Signals `ContentStore` to keep the
  /// cached row instead of overwriting it with an empty one.
  case allSourcesFailed
}

private extension MediaIdentity {
  /// From a catalog card: nil when it carries neither an IMDb nor a Kinopoisk id
  /// (cards cached before the ids were stored, collections, episodes).
  init?(card: MediaCard) {
    guard !card.opensCollection, card.imdbID != nil || card.kinopoiskID != nil else { return nil }
    self.init(
      kinopubId: card.itemID,
      imdb: card.imdbID.map(TMDBIDFormatter.imdbString(from:)),
      kinopoisk: card.kinopoiskID,
      title: card.title,
      originalTitle: card.subtitle ?? card.title,
      year: card.year ?? 0,
      isSeries: card.isSeries
    )
  }
}
