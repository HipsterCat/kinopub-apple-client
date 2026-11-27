import Foundation
import SwiftUI
import KinoPubBackend
import PiraticKit
import PiraticMetadata
import PiraticUI

// MARK: - Env key

@MainActor private struct AppContextKey: @preconcurrency EnvironmentKey {
  @preconcurrency
  static var defaultValue: AppContextProtocol { AppContext.shared }
}

extension EnvironmentValues {
  @MainActor
  var appContext: AppContextProtocol {
    get { self[AppContextKey.self] }
    set { self[AppContextKey.self] = newValue }
  }
}

// MARK: - AppContextProtocol

protocol MetadataServiceProvider {
  var metadataService: MetadataService { get }
}

protocol TrackPreferencesProvider {
  var trackPreferences: TrackPreferenceStore { get }
}

protocol ContentStoreProvider {
  var contentStore: ContentStore { get }
}

protocol DownloadsCenterProvider {
  var downloadsCenter: DownloadsCenter { get }
}

protocol KinopoiskKeyProviderProvider {
  var kinopoiskKeyProvider: IntegrationKeyProvider { get }
}

protocol AppContextProtocol: AuthorizationServiceProvider
& VideoContentServiceProvider
& ConfigurationProvider
& KeychainStorageProvider
& AccessTokenServiceProvider
& DownloadManagerProvider
& DownloadedFilesDatabaseProvider
& FileSaverProvider
& UserServiceProvider
& UserActionsServiceProvider
& MetadataServiceProvider
& KinopoiskKeyProviderProvider
& ContentStoreProvider
& CollectionsServiceProvider
& DeviceServiceProvider
& LocalWatchProgressProvider
& MediaLibraryProvider
& ViewerStateProvider
& TrackPreferencesProvider
& DownloadsCenterProvider {}

// MARK: - AppContext

struct AppContext: AppContextProtocol {

  var configuration: Configuration
  var authService: AuthorizationService
  var contentService: VideoContentService
  var accessTokenService: AccessTokenService
  var userService: UserService
  var keychainStorage: KeychainStorage
  var fileSaver: FileSaving
  var downloadManager: DownloadManager<DownloadMeta>
  var downloadedFilesDatabase: DownloadedFilesDatabase<DownloadMeta>
  var downloadNotificationManager: DownloadNotificationManager
  var seasonDownloadManager: SeasonDownloadManager
  /// Every download screen's one source: in flight and on disk, both engines.
  var downloadsCenter: DownloadsCenter
  var hlsDownloadsStore: HLSDownloadsStore
  var hlsDownloadManager: HLSAssetDownloadManager
  var actionsService: UserActionsService
  var metadataService: MetadataService
  var kinopoiskKeyProvider: IntegrationKeyProvider
  var contentStore: ContentStore
  var collectionsService: CollectionsService
  var deviceService: DeviceService
  var localProgressStore: LocalWatchProgressStore
  var libraryState: MediaLibraryStore
  /// Which dub and which subtitles each title opens with. Local-only knowledge the
  /// server has no concept of, which is why it does not live on `MediaLibraryStore`.
  var trackPreferences = TrackPreferenceStore.shared

  /// What the viewer has done with a thing — one read over the stores above.
  @MainActor var viewerState: ViewerStateReading {
    ViewerStateReader(library: libraryState, progress: localProgressStore)
  }

  @preconcurrency @MainActor static let shared: AppContext = {
    let configuration = BundleConfiguration()
    let keychainStorage = KeychainStorageImpl()
    let accessTokenService = AccessTokenServiceImpl(storage: keychainStorage)

    // Downloads (mp4 + resume control + iOS HLS). Non-TV only in the UI; Kit stays available.
    let fileSaver = FileSaver()
    let downloadedFilesDatabase = DownloadedFilesDatabase<DownloadMeta>(fileSaver: fileSaver)
    let downloadsControlDatabase = DownloadsControlDatabase<DownloadMeta>(fileSaver: fileSaver)
    let downloadManager = DownloadManager<DownloadMeta>(
      fileSaver: fileSaver,
      database: downloadedFilesDatabase,
      controlDatabase: downloadsControlDatabase
    )
    let downloadNotificationManager = DownloadNotificationManager()
    let seasonDownloadManager = SeasonDownloadManager(notifications: downloadNotificationManager)
    let hlsDownloadsStore = HLSDownloadsStore()
    let hlsDownloadManager = HLSAssetDownloadManager(
      store: hlsDownloadsStore,
      maxResolutionProvider: { StreamQuality.current.maxHeight }
    )
    hlsDownloadManager.onDownloadFinished = { meta in
      if !seasonDownloadManager.handleFinished(meta: meta) {
        downloadNotificationManager.notifyFinished(title: meta.notificationTitle, identifier: "\(meta.id)")
      }
    }
    hlsDownloadManager.onDownloadFailed = { meta in
      downloadNotificationManager.notifyFailed(title: meta.notificationTitle, identifier: "\(meta.id)")
    }
    // Deferred a tick: reattaching to a background AVAssetDownloadURLSession is an XPC round
    // trip to nsurlsessiond (~20-25ms measured, main-thread-only work since AVAssetDownloadURLSession
    // requires a main delegate queue here). Called synchronously this sat directly in front of
    // RootView's first frame, since `AppContext.shared` is resolved on the main thread before
    // any view renders. A paused/interrupted HLS download reattaching a few hundred ms later is
    // imperceptible; blocking every cold launch on it (even with zero downloads to restore) is not.
    let hlsToRestore = hlsDownloadManager
    let filesToReattach = downloadManager
    Task { @MainActor in
      hlsToRestore.restorePendingDownloads()
      // Same for the mp4 session: reconnect, adopt the transfers it kept running, and
      // continue the ones that were running when the app went away.
      filesToReattach.reattachBackgroundTasks()
    }
    downloadManager.onDownloadFinished = { _, meta in
      if !seasonDownloadManager.handleFinished(meta: meta) {
        downloadNotificationManager.notifyFinished(title: meta.notificationTitle, identifier: "\(meta.id)")
      }
    }
    downloadManager.onDownloadFailed = { _, meta, _ in
      downloadNotificationManager.notifyFailed(title: meta.notificationTitle, identifier: "\(meta.id)")
    }

    let apiClient = makeApiClient(with: configuration.baseURL, accessTokenService: accessTokenService)

    let authService = AuthorizationServiceImpl(
      apiClient: apiClient,
      configuration: configuration,
      accessTokenService: accessTokenService
    )

    let metadataConfig = MetadataConfiguration(
      proxyBaseURL: configuration.tmdbProxyBaseURL.flatMap(URL.init(string:))
    )
    // Every vertical cover goes through the worker's poster route, not kino.pub's CDN.
    CoverArtwork.configureWorker(TitleImageRoute(baseURL: metadataConfig.proxyBaseURL),
                                 pixelWidth: ArtworkPixelWidth.poster,
                                 widePixelWidth: ArtworkPixelWidth.wideCard)
    let kinopoiskKeyProvider = IntegrationKeyProvider.kinopoisk
    let metadataService = MetadataService(sources: [
      TMDBSource(configuration: metadataConfig, directAccess: IntegrationKeyProvider.tmdb),
      KinopoiskSource(keyProvider: kinopoiskKeyProvider),
      // Staff stays on this path. The v2 comparison calls the same source with it off.
      KinopoiskProxySource(includeStaff: true),
      // Ratings it relays (Rotten Tomatoes, Metacritic, Letterboxd…) and its reviews.
      // MAL votes here are a fallback — MyAnimeListSource refreshes them from the official API.
      TraktSource(access: TraktMetadataAccess(), language: Bundle.main.preferredLocalizations.first ?? "ru"),
      // Official MAL mean + num_scoring_users (`X-MAL-CLIENT-ID`), 18h cache.
      MyAnimeListSource(access: MyAnimeListMetadataAccess()),
      // The viewer's own OMDb key: box office, awards, and the scores Trakt did not have.
      // After Trakt, which outranks it where both answer.
      OMDbSource(keys: IntegrationKeyProvider.omdb),
      // Douban's score, star breakdown and genre ranks, signed and cached by our worker.
      DoubanSource(configuration: metadataConfig, access: DoubanMetadataAccess()),
      // Last: ids on other sites, Wikipedia, box office — only what the others left empty.
      MyShowsSource(access: MyShowsMetadataAccess()),
      PlexSource(access: PlexMetadataAccess()),
      WikidataSource(access: WikidataMetadataAccess(), language: Bundle.main.preferredLocalizations.first ?? "ru"),
      // Skip times for the player: SkipDB's open data first, TheIntroDB fills the rest.
      SkipDBSource(access: SkipTimesMetadataAccess()),
      TheIntroDBSource(access: SkipTimesMetadataAccess())
    ], images: TitleImageRoute(baseURL: metadataConfig.proxyBaseURL),
      titleCard: TitleCardSource(configuration: metadataConfig))

#if DEBUG && os(tvOS)
    // A fixture swaps the API for stand-ins but keeps the real stores, and the real player
    // records what it plays: the seasonStrip series a UI test played turned up in Continue
    // Watching on the next ordinary launch (2026-10-25). A fixture run's progress stays in
    // memory.
    let isFixtureRun = DetailFixture.isActive || LibraryFixture.isActive || TVChannelsFixture.isActive
    let localProgressStore = isFixtureRun
      ? LocalWatchProgressStore(container: WatchLibrary.makeInMemoryContainer())
      : LocalWatchProgressStore()
    // What fixture runs wrote before they kept to memory: on a simulator that ran the UI
    // tests, the stand-in series still sits in the store.
    if !isFixtureRun {
      DetailFixture.allCases.forEach { localProgressStore.clear(id: $0.itemID) }
    }
#else
    let isFixtureRun = false
    let localProgressStore = LocalWatchProgressStore()
#endif
    let libraryState = MediaLibraryStore(
      downloadManager: downloadManager,
      hlsDownloadManager: hlsDownloadManager,
      hlsStore: hlsDownloadsStore,
      downloadedFilesDatabase: downloadedFilesDatabase
    )
    let downloadsCenter = DownloadsCenter(
      downloadManager: downloadManager,
      hlsManager: hlsDownloadManager,
      hlsStore: hlsDownloadsStore,
      filesDatabase: downloadedFilesDatabase,
      library: libraryState
    )
    seasonDownloadManager.center = downloadsCenter
    // Rows read the viewer's state at paint time, not from the cached cards.
    let viewerState = ViewerStateReader(library: libraryState, progress: localProgressStore)
    let contentStore = MainActor.assumeIsolated { ContentStore(viewer: viewerState) }
    // Every title on the server's followed list is followed: a local mark saying otherwise
    // is stale unless toggled since the request left. Not for fixtures (stand-in ids must
    // not land in the real store) nor unit tests (they own the shared cache).
    let isUnitTestRun = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    if !isFixtureRun, !isUnitTestRun {
      MainActor.assumeIsolated {
        WatchingListCache.shared.onFollowedSerialsFetched = { [libraryState] ids, requestedAt in
          libraryState.reconcileWatchlist(Dictionary(ids.map { ($0, true) }, uniquingKeysWith: { a, _ in a }),
                                          requestedAt: requestedAt, onlyKnown: true)
        }
      }
    }

    let context = AppContext(
      configuration: configuration,
      authService: authService,
      contentService: VideoContentServiceImpl(apiClient: apiClient),
      accessTokenService: accessTokenService,
      userService: UserServiceImpl(apiClient: apiClient),
      keychainStorage: keychainStorage,
      fileSaver: fileSaver,
      downloadManager: downloadManager,
      downloadedFilesDatabase: downloadedFilesDatabase,
      downloadNotificationManager: downloadNotificationManager,
      seasonDownloadManager: seasonDownloadManager,
      downloadsCenter: downloadsCenter,
      hlsDownloadsStore: hlsDownloadsStore,
      hlsDownloadManager: hlsDownloadManager,
      actionsService: UserActionsServiceImpl(apiClient: apiClient),
      metadataService: metadataService,
      kinopoiskKeyProvider: kinopoiskKeyProvider,
      contentStore: contentStore,
      collectionsService: CollectionsServiceImpl(apiClient: apiClient),
      deviceService: DeviceServiceImpl(apiClient: apiClient),
      localProgressStore: localProgressStore,
      libraryState: libraryState
    )
#if DEBUG && os(tvOS)
    // `-PIRATICDetailFixture`: the detail page against local stand-ins (UI tests).
    if DetailFixture.isActive {
      return DetailFixture.context(replacingServicesOf: context)
    }
    // `-PIRATICLibraryFixture`: the Library against a stand-in API.
    if LibraryFixture.isActive {
      return LibraryFixture.context(replacingServicesOf: context)
    }
    // `-PIRATICTVChannelsFixture`: the TV tab against a stand-in API.
    if TVChannelsFixture.isActive {
      return TVChannelsFixture.context(replacingServicesOf: context)
    }
#endif
    return context
  }()

  // MARK: - API Client building

  /// kino.pub's API hosts and the one in use (Settings › Network shows them). Sticky
  /// across launches; `BaseURL` from Info.plist is first.
  static let apiHosts = APIHostPool(primary: URL(string: BundleConfiguration().baseURL))

  private static func makeApiClient(with baseURL: String, accessTokenService: AccessTokenService) -> APIClient {
    var session: URLSessionProtocol = URLSessionImpl(session: .shared)
#if DEBUG
    // `-PIRATICFailAPIHost api.service-kp.com` (`:502` for a gateway answer instead of an
    // unreachable host): exercises the fallback without waiting for a real outage.
    if let spec = UserDefaults.standard.string(forKey: "PIRATICFailAPIHost"), !spec.isEmpty {
      session = FailingAPIHostSession(spec: spec, wrapped: session)
    }
#endif
    return APIClient(
      baseUrl: baseURL,
      plugins: [
        // `CURLLoggingPlugin` is deliberately not here: it printed every request's
        // headers — `Authorization: Bearer …` included — into the system log, and the
        // Network log now renders cURL with the token redacted. The type is kept for
        // one-off local debugging, not for the default stack.
        ResponseLoggingPlugin(),
        UnauthorizedResponsePlugin(),
        AccessTokenPlugin(accessTokenService: accessTokenService)
      ],
      session: session,
      // Genres/countries only (see CacheableRequest). Personalized rows stay on ContentStore.
      cache: ResponseCache(),
      hosts: apiHosts
    )
  }
}

#if DEBUG
/// `-PIRATICFailAPIHost <host>[,<host>…][:502]`: those hosts are unreachable, or answer
/// with that status. `kino.watch` matches `kino.watch/api`.
private final class FailingAPIHostSession: URLSessionProtocol {
  private let hosts: Set<String>
  private let status: Int?
  private let wrapped: URLSessionProtocol

  init(spec: String, wrapped: URLSessionProtocol) {
    let parts = spec.split(separator: ":", maxSplits: 1).map(String.init)
    hosts = Set(parts[0].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
    status = parts.count > 1 ? Int(parts[1]) : nil
    self.wrapped = wrapped
  }

  func data(for request: URLRequest) async throws -> (Data, URLResponse) {
    guard let url = request.url, let host = url.host, hosts.contains(host) else {
      return try await wrapped.data(for: request)
    }
    try await Task.sleep(for: .milliseconds(150))
    if let status, let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil) {
      return (Data("<html>\(status)</html>".utf8), response)
    }
    throw APIClientError.networkError(URLError(.cannotFindHost))
  }
}
#endif
