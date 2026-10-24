import Foundation
import SwiftUI
import KinoPubBackend
import KinoPubKit
import KinoPubMetadata

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

protocol KinopoiskKeyProviderProvider {
  var kinopoiskKeyProvider: KinopoiskKeyProvider { get }
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
& TrackPreferencesProvider {}

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
  var hlsDownloadsStore: HLSDownloadsStore
  var hlsDownloadManager: HLSAssetDownloadManager
  var actionsService: UserActionsService
  var metadataService: MetadataService
  var kinopoiskKeyProvider: KinopoiskKeyProvider
  var contentStore: ContentStore
  var collectionsService: CollectionsService
  var deviceService: DeviceService
  var localProgressStore: LocalWatchProgressStore
  var libraryState: MediaLibraryStore
  /// Which dub and which subtitles each title opens with. Local-only knowledge the
  /// server has no concept of, which is why it does not live on `MediaLibraryStore`.
  var trackPreferences = TrackPreferenceStore.shared

  /// What the viewer has done with a thing — one read over the stores above.
  var viewerState: ViewerStateReading {
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
    let seasonDownloadManager = SeasonDownloadManager(
      downloadManager: downloadManager,
      notifications: downloadNotificationManager
    )
    let hlsDownloadsStore = HLSDownloadsStore()
    let hlsDownloadManager = HLSAssetDownloadManager(
      store: hlsDownloadsStore,
      maxResolutionProvider: { StreamQuality.current.maxHeight }
    )
    // Hop onto MainActor via `shared` rather than capturing the managers: they are
    // `@MainActor` and these callbacks are not. The closures run after `shared` is live.
    hlsDownloadManager.onDownloadFinished = { meta in
      Task { @MainActor in
        AppContext.shared.downloadNotificationManager.notifyFinished(
          title: meta.notificationTitle, identifier: "\(meta.id)")
      }
    }
    hlsDownloadManager.onDownloadFailed = { meta in
      Task { @MainActor in
        AppContext.shared.downloadNotificationManager.notifyFailed(
          title: meta.notificationTitle, identifier: "\(meta.id)")
      }
    }
    // Deferred a tick: reattaching to a background AVAssetDownloadURLSession is an XPC round
    // trip to nsurlsessiond (~20-25ms measured, main-thread-only work since AVAssetDownloadURLSession
    // requires a main delegate queue here). Called synchronously this sat directly in front of
    // RootView's first frame, since `AppContext.shared` is resolved on the main thread before
    // any view renders. A paused/interrupted HLS download reattaching a few hundred ms later is
    // imperceptible; blocking every cold launch on it (even with zero downloads to restore) is not.
    // `nonisolated(unsafe)`: the Task is MainActor-queued after this MainActor `shared` init
    // finishes, so it cannot overlap the stores below; the manager is not Sendable.
    nonisolated(unsafe) let hlsToRestore = hlsDownloadManager
    Task { @MainActor in
      hlsToRestore.restorePendingDownloads()
    }
    downloadManager.onDownloadFinished = { url, meta in
      Task { @MainActor in
        let handledBySeason = AppContext.shared.seasonDownloadManager.handleFinished(url: url)
        if !handledBySeason {
          AppContext.shared.downloadNotificationManager.notifyFinished(
            title: meta.notificationTitle, identifier: "\(meta.id)")
        }
      }
    }
    downloadManager.onDownloadFailed = { _, meta, _ in
      Task { @MainActor in
        AppContext.shared.downloadNotificationManager.notifyFailed(
          title: meta.notificationTitle, identifier: "\(meta.id)")
      }
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
    let kinopoiskKeyProvider = KinopoiskKeyProvider()
    let metadataService = MetadataService(sources: [
      TMDBSource(configuration: metadataConfig),
      KinopoiskSource(keyProvider: kinopoiskKeyProvider),
      KinopoiskProxySource()
    ], images: TitleImageRoute(baseURL: metadataConfig.proxyBaseURL))

#if DEBUG && os(tvOS)
    // A fixture swaps the API for stand-ins but keeps the real stores, and the real player
    // records what it plays: the seasonStrip series a UI test played turned up in Continue
    // Watching on the next ordinary launch (2026-10-25). A fixture run's progress stays in
    // memory.
    let isFixtureRun = DetailFixture.isActive || LibraryFixture.isActive || TVChannelsFixture.isActive
#else
    let isFixtureRun = false
#endif
    let localProgressStore = isFixtureRun
      ? LocalWatchProgressStore(container: WatchLibrary.makeInMemoryContainer())
      : LocalWatchProgressStore()
#if DEBUG && os(tvOS)
    // What fixture runs wrote before they kept to memory: on a simulator that ran the UI
    // tests, the stand-in series still sits in the store.
    if !isFixtureRun {
      DetailFixture.allCases.forEach { localProgressStore.clear(id: $0.itemID) }
    }
#endif
    let libraryState = MediaLibraryStore(
      downloadManager: downloadManager,
      hlsDownloadManager: hlsDownloadManager,
      hlsStore: hlsDownloadsStore,
      downloadedFilesDatabase: downloadedFilesDatabase
    )
    // Rows read the viewer's state at paint time, not from the cached cards.
    let viewerState = ViewerStateReader(library: libraryState, progress: localProgressStore)
    let contentStore = MainActor.assumeIsolated { ContentStore(viewer: viewerState) }

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
    // `-KINOPUBDetailFixture`: the detail page against local stand-ins (UI tests).
    if DetailFixture.isActive {
      return DetailFixture.context(replacingServicesOf: context)
    }
    // `-KINOPUBLibraryFixture`: the Library against a stand-in API.
    if LibraryFixture.isActive {
      return LibraryFixture.context(replacingServicesOf: context)
    }
    // `-KINOPUBTVChannelsFixture`: the TV tab against a stand-in API.
    if TVChannelsFixture.isActive {
      return TVChannelsFixture.context(replacingServicesOf: context)
    }
#endif
    return context
  }()

  // MARK: - API Client building

  private static func makeApiClient(with baseURL: String, accessTokenService: AccessTokenService) -> APIClient {
    APIClient(
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
      // Genres/countries only (see CacheableRequest). Personalized rows stay on ContentStore.
      cache: ResponseCache()
    )
  }
}
