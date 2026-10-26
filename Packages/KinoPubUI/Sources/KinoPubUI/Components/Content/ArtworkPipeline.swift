//
//  ArtworkPipeline.swift
//  KinoPubUI
//
//  The one artwork cache. Every remote image on every platform goes through this
//  pipeline — `ArtworkImage` / `CachedRemoteImage` (SwiftUI), `TVUIKitRemoteImage`
//  (tvOS cells) and `FallbackRemoteImage` are its only callers, and nothing else
//  imports Nuke.
//
//  Why a library and not `AsyncImage`: `URLCache` stores *bytes*. A recycled tile that
//  hits it still pays a full decode, and the default shared cache holds a handful of
//  posters — which is the "posters vanish while you scroll" report. What is needed is a
//  decoded-image memory cache keyed by target size, in-flight coalescing, prefetching
//  and downsampling. tvOS had all four hand-written here; iOS/macOS had none of it.
//  Nuke is that same design, maintained, and it deletes the split.
//
//  Disk holds **original bytes, once per URL** (`.storeOriginalData`). Memory holds the
//  decoded, already-downsampled variants. A rail and a grid asking for the same still at
//  different sizes are two memory entries and one disk entry — which is also what makes
//  the number in Settings › Storage mean something.
//

import Foundation
import CoreGraphics
import SwiftUI
import Nuke
import KinoPubMetadata

/// Namespace for the shared artwork stack: the pipeline, the request shape, and the
/// cache accounting Settings reports.
public enum Artwork {

  /// Artwork does not share `URLCache` with the API client — the loader's own session
  /// cache is off so bytes are stored once, by `dataCache`, and Storage settings can
  /// report a number that is only artwork.
  ///
  /// **One slow host must not hold the others.** Nuke runs every download through one
  /// queue, six at a time. The cast photos live on `m.pushbr.com`, which answers nothing
  /// for ~25 s and then fails (measured 2026-10-04, from the Mac and the tvOS simulator);
  /// the detail page asks for eight of them before its episode stills, so the six slots
  /// filled with requests going nowhere and the episode rail stayed grey for half a
  /// minute while `m.staticpop.net` answers in 0.3 s. The queue is wide now and the
  /// per-host cap is `URLSession`'s own (`httpMaximumConnectionsPerHost`), so a stalled
  /// host only stalls itself; and a request gives up after `requestTimeout`, not the
  /// session's 60 s.
  public static let pipeline: ImagePipeline = {
    let configuration = URLSessionConfiguration.default
    configuration.urlCache = nil
    configuration.timeoutIntervalForRequest = requestTimeout

    return ImagePipeline {
      $0.dataLoader = DataLoader(configuration: configuration)
      $0.dataLoadingQueue = TaskQueue(maxConcurrentOperationCount: concurrentDownloads)
      $0.dataCache = diskCache
      $0.imageCache = memoryCache
      $0.dataCachePolicy = .storeOriginalData
    }
  }()

  /// Downloads in flight across all hosts. `URLSession` keeps each host to its own
  /// connection limit, so this only has to be wide enough that one host cannot take it all.
  static let concurrentDownloads = 24
  /// No byte for this long and the request fails; the cell keeps its placeholder.
  static let requestTimeout: TimeInterval = 15

  /// Decoded images. On tvOS this is the number that was measured: a 1 MB still decodes
  /// to ~8 MB at full resolution, so 64 MB held about eight of them — at tile size the
  /// same budget holds hundreds, and that is what stopped tiles going blank a short
  /// scroll away. Apple TV HD has little headroom, so the TV budget stays there.
  /// Decoded-image budget. Settings shows usage against this, so the number
  /// the cache is created with and the number on the screen are the same one.
  public static let memoryByteLimit: Int = {
#if os(tvOS)
    64 * 1024 * 1024
#else
    256 * 1024 * 1024
#endif
  }()

  private static let memoryCache: ImageCache = {
#if os(tvOS)
    ImageCache(costLimit: memoryByteLimit, countLimit: 500)
#else
    ImageCache(costLimit: memoryByteLimit, countLimit: 2000)
#endif
  }()

  /// tvOS purges `Caches/` when the app is not running, so the TV budget is deliberately
  /// small — it is a within-session cache there, and pretending otherwise buys nothing.
  /// Worker logo/backdrop request URL → language stamp from the last network answer.
  /// Nuke cache hits do not keep `urlResponse`; hero captions read this table.
  private static let workerLanguageLock = NSLock()
  private static var workerLanguageByRequestURL: [URL: WorkerArtworkLanguageTag] = [:]

  /// Original-byte budget. Nuke evicts past this. tvOS purges `Caches/` when the
  /// app is not running, so the TV budget stays a within-session cache.
  public static let diskByteLimit: Int = {
#if os(tvOS)
    128 * 1024 * 1024
#else
    512 * 1024 * 1024
#endif
  }()

  private static let diskCache: DataCache? = {
    guard let cache = try? DataCache(name: "com.soda.kinopub.artwork") else { return nil }
    cache.sizeLimit = diskByteLimit
    return cache
  }()

  /// How a decode fills its target box. Still / landscape cells need a centre crop so
  /// a 2:3 poster handed to a 16:9 tile does not letterbox; `TVPosterView` lockups must
  /// **not** crop — cover lettering has to stay readable (Sasha, 2026-10-02).
  public enum ResizeMode: Sendable, Hashable {
    /// Centre-crop to the box (stills, wide cards, SwiftUI tiles).
    case fill
    /// Scale to fit inside the box, no crop — poster lockups.
    case fit
  }

  /// - Parameter size: the box this art is going into, in points. Artwork is decoded
  ///   down to it, and the size is part of the cache key — the same still in a rail and
  ///   in a grid is a different decode, and handing one out for the other is either
  ///   blurry or wasteful. `.zero` keeps full resolution and should be rare.
  /// - Parameter mode: `.fill` (default) centre-crops; `.fit` preserves the whole cover
  ///   for `TVPosterView` (see `ResizeMode`).
  public static func request(_ url: URL, size: CGSize = .zero, mode: ResizeMode = .fill) -> ImageRequest {
    noteSeen(url, size: size, mode: mode)
    return makeRequest(url, size: size, mode: mode)
  }

  private static func makeRequest(_ url: URL, size: CGSize, mode: ResizeMode) -> ImageRequest {
    guard size != .zero else { return ImageRequest(url: url) }
    let processor: ImageProcessors.Resize
    switch mode {
    case .fill:
      processor = ImageProcessors.Resize(size: size, unit: .points, contentMode: .aspectFill, crop: true)
    case .fit:
      processor = ImageProcessors.Resize(size: size, unit: .points, contentMode: .aspectFit, crop: false)
    }
    return ImageRequest(url: url, processors: [processor])
  }

  /// Already-decoded art at this size, or nil. Synchronous on purpose: a cell calls this
  /// while configuring so a recycled tile never paints a placeholder.
  public static func cachedImage(for url: URL, size: CGSize = .zero, mode: ResizeMode = .fill) -> PlatformImage? {
    pipeline.cache[request(url, size: size, mode: mode)]?.image
  }

  /// Decode (or cache-hit) off the call site's actor. `FallbackRemoteImage` and
  /// `ArtworkImage` go through this so they never import Nuke.
  public static func image(for url: URL, size: CGSize = .zero) async throws -> PlatformImage {
    try await pipeline.image(for: request(url, size: size))
  }

  /// `image(for:)`, plus where it came from: the URL that answered after redirects
  /// (nil from a cache, which does not keep it), the worker language stamp when the
  /// final URL or `Content-Language` carries `ru` / `en` / `und`, and the tier —
  /// `memory`, `disk` or `network`. For the source log and hero captions.
  public static func imageWithSource(for url: URL, size: CGSize = .zero) async throws
    -> (image: PlatformImage, answered: URL?, language: WorkerArtworkLanguageTag?, tier: String) {
    let response = try await pipeline.imageTask(with: request(url, size: size)).response
    let tier: String
    switch response.cacheType {
    case .memory: tier = "memory"
    case .disk: tier = "disk"
    case .none: tier = "network"
    @unknown default: tier = "unknown"
    }
    let answered = response.urlResponse?.url
    let header = (response.urlResponse as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Language")
    var language = WorkerArtworkLanguageTag.resolved(answeredURL: answered, contentLanguageHeader: header)
    if language == nil {
      language = rememberedWorkerLanguage(for: url)
    } else {
      rememberWorkerLanguage(requestURL: url, language: language)
    }
    return (response.image, answered, language, tier)
  }

  /// Language stamp when the URL is already the worker's durable path (cache hit).
  public static func workerLanguage(on url: URL) -> WorkerArtworkLanguageTag? {
    if let stamped = WorkerArtworkLanguageTag.parseStampedURL(url) { return stamped }
    return rememberedWorkerLanguage(for: url)
  }

  /// Follows the worker redirect when Nuke has bytes but no stamp (disk/memory hit).
  public static func fetchWorkerLanguageStamp(for requestURL: URL) async -> WorkerArtworkLanguageTag? {
    if let known = workerLanguage(on: requestURL) { return known }
    var request = URLRequest(url: requestURL)
    request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
    request.timeoutInterval = 15
    request.setValue(workerHTTPAcceptLanguage, forHTTPHeaderField: "Accept-Language")
    guard let (_, response) = try? await URLSession.shared.data(for: request),
          let http = response as? HTTPURLResponse,
          let final = http.url else { return nil }
    let header = http.value(forHTTPHeaderField: "Content-Language")
    let language = WorkerArtworkLanguageTag.resolved(
      answeredURL: final,
      contentLanguageHeader: header
    )
    rememberWorkerLanguage(requestURL: requestURL, language: language)
    return language
  }

  private static var workerHTTPAcceptLanguage: String {
    TitleImageRoute.appLanguage == "en" ? "en-US,en;q=0.9" : "ru"
  }

  private static func rememberWorkerLanguage(requestURL: URL, language: WorkerArtworkLanguageTag?) {
    guard let language else { return }
    workerLanguageLock.lock()
    workerLanguageByRequestURL[requestURL] = language
    workerLanguageLock.unlock()
  }

  private static func rememberedWorkerLanguage(for requestURL: URL) -> WorkerArtworkLanguageTag? {
    workerLanguageLock.lock()
    defer { workerLanguageLock.unlock() }
    return workerLanguageByRequestURL[requestURL]
  }

  // MARK: - Accounting, for Settings › Storage

  public static var memoryBytes: Int { memoryCache.totalCost }

  /// Walks the cache directory, so call it off a hot path.
  public static var diskBytes: Int { diskCache?.totalSize ?? 0 }

  /// Pictures this session asked for, grouped by what the URL is, with the
  /// original file's size when it is already on disk. Nuke names cache files
  /// by hash, so a logo count cannot be read back from the directory alone.
  public struct UsageGroup: Sendable, Equatable {
    public var id: String
    public var count: Int
    public var bytes: Int64
  }

  public static func sessionGroups() -> [UsageGroup] {
    seenLock.lock()
    let urls = Array(seen.keys)
    seenLock.unlock()
    let order = ["logos", "posters", "backdrops", "stills", "people", "other"]
    var buckets: [String: (count: Int, bytes: Int64)] = [:]
    for url in urls {
      let id = usageKind(for: url)
      var bucket = buckets[id] ?? (0, 0)
      bucket.count += 1
      bucket.bytes += storedBytes(for: url)
      buckets[id] = bucket
    }
    return order.compactMap { id in
      guard let bucket = buckets[id], bucket.count > 0 else { return nil }
      return UsageGroup(id: id, count: bucket.count, bytes: bucket.bytes)
    }
  }

  private static func usageKind(for url: URL) -> String {
    let path = url.path.lowercased()
    let host = url.host?.lowercased() ?? ""
    if path.contains("/logo/") || path.contains("/img/logo") { return "logos" }
    if path.contains("/backdrop/") { return "backdrops" }
    if path.contains("/poster/") { return "posters" }
    if path.contains("/thumb/") || path.contains("/thumbnail/") || path.contains("/still") {
      return "stills"
    }
    if host.contains("pushbr") || path.contains("/person") || path.contains("/cast") {
      return "people"
    }
    return "other"
  }

  /// File size of the original bytes. Reading the data would pull the whole
  /// picture cache into memory just to count it.
  private static func storedBytes(for url: URL) -> Int64 {
    let key = pipeline.cache.makeDataCacheKey(for: ImageRequest(url: url))
    guard let file = diskCache?.url(for: key) else { return 0 }
    let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize
    return Int64(size ?? 0)
  }

  public static func clearCaches() {
    memoryCache.removeAll()
    diskCache?.removeAll()
    seenLock.lock()
    seen.removeAll()
    seenLock.unlock()
    workerLanguageLock.lock()
    workerLanguageByRequestURL.removeAll()
    workerLanguageLock.unlock()
  }

  /// Drops one title's pictures: the decoded sizes this session actually asked for,
  /// and the original bytes on disk. Other titles stay.
  public static func remove(urls: some Sequence<URL>) {
    let unique = Array(Set(urls))
    guard !unique.isEmpty else { return }
    seenLock.lock()
    var variants: [(URL, SeenVariant)] = []
    for url in unique {
      if let stored = seen[url] {
        variants.append(contentsOf: stored.map { (url, $0) })
      }
      seen[url] = nil
    }
    seenLock.unlock()
    for (url, variant) in variants {
      pipeline.cache.removeCachedImage(
        for: makeRequest(url, size: variant.size, mode: variant.mode),
        caches: .memory
      )
    }
    for url in unique {
      let bare = ImageRequest(url: url)
      pipeline.cache.removeCachedData(for: bare)
      pipeline.cache[bare] = nil
    }
    workerLanguageLock.lock()
    for url in unique {
      workerLanguageByRequestURL[url] = nil
    }
    workerLanguageLock.unlock()
  }

  private struct SeenVariant: Hashable {
    var size: CGSize
    var mode: ResizeMode
  }

  private static let seenLock = NSLock()
  private static var seen: [URL: Set<SeenVariant>] = [:]

  private static func noteSeen(_ url: URL, size: CGSize, mode: ResizeMode) {
    seenLock.lock()
    seen[url, default: []].insert(SeenVariant(size: size, mode: mode))
    seenLock.unlock()
  }
}

extension Image {
  /// `PlatformImage` is `UIImage` on iOS/tvOS and `NSImage` on macOS, and SwiftUI takes
  /// them through different initialisers.
  init(platformImage: PlatformImage) {
#if os(macOS)
    self.init(nsImage: platformImage)
#else
    self.init(uiImage: platformImage)
#endif
  }
}
