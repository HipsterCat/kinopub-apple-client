//
//  ArtworkPipeline.swift
//  PiraticUI
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
import Synchronization
import Nuke
import PiraticLogging
import PiraticMetadata
#if os(macOS)
import AppKit
#else
import UIKit
#endif

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
      $0.dataLoader = ArtworkDataLoader(DataLoader(configuration: configuration))
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

  /// Decoded-image budget. Settings shows usage against this, so the number
  /// the cache is created with and the number on the screen are the same one.
  ///
  /// Scales with `ProcessInfo.physicalMemory`: ~1/16 of RAM on tvOS/iOS (192 MB on a
  /// 3 GB Apple TV 4K, matching Plozz), ~1/32 on Mac. Floors keep Apple TV HD and
  /// small iPhones from going below a working set; caps keep a 5K iMac from eating RAM.
  public static let memoryByteLimit: Int = memoryByteLimit(
    physicalMemory: ProcessInfo.processInfo.physicalMemory
  )

  /// - Parameter physicalMemory: injected so tests can pin a device class without
  ///   reading this process.
  public static func memoryByteLimit(physicalMemory: UInt64) -> Int {
    let megabytes = Int(physicalMemory / (1024 * 1024))
#if os(tvOS)
    return clampMemoryMegabytes(megabytes / 16, minimum: 64, maximum: 192) * 1024 * 1024
#elseif os(iOS)
    return clampMemoryMegabytes(megabytes / 16, minimum: 128, maximum: 256) * 1024 * 1024
#else
    return clampMemoryMegabytes(megabytes / 32, minimum: 256, maximum: 512) * 1024 * 1024
#endif
  }

  private static func clampMemoryMegabytes(_ value: Int, minimum: Int, maximum: Int) -> Int {
    min(max(value, minimum), maximum)
  }

  private static var memoryCountLimit: Int {
#if os(tvOS)
    1500
#else
    2000
#endif
  }

  /// Decoded images this old expire even when the cache is under its byte/count
  /// limits. Nuke's `ImageCache.ttl` is from insert (not last access), checked
  /// on the next read — the closest public API to an idle timeout.
  public static let memoryEntryTTL: TimeInterval = 15 * 60

  /// An entry larger than this fraction of ``memoryByteLimit`` is not stored.
  /// 0.2 keeps a 1920×1080×4 backdrop (~8 MB) cacheable at the 64 MB floor
  /// (Nuke's 0.1 default would reject it).
  public static let memoryEntryCostLimit: Double = 0.2

  private static let memoryCache: ImageCache = {
    let cache = ImageCache(costLimit: memoryByteLimit, countLimit: memoryCountLimit)
    cache.ttl = memoryEntryTTL
    cache.entryCostLimit = memoryEntryCostLimit
    return cache
  }()

  /// Worker logo/backdrop request URL → language stamp from the last network answer.
  /// Nuke cache hits do not keep `urlResponse`; hero captions read this table.
  /// Written from the image task and read from hero captions, so it cannot live on
  /// the main actor. The critical sections are dictionary updates with no await.
  private static let workerLanguageByRequestURL = Mutex<[URL: WorkerArtworkLanguageTag]>([:])

  /// Original-byte budget. Nuke evicts past this (LRU by last access, down to
  /// 70 % of the limit). tvOS purges `Caches/` when the app is not running, so
  /// the TV budget stays a within-session cache.
  public static let diskByteLimit: Int = {
#if os(tvOS)
    128 * 1024 * 1024
#else
    512 * 1024 * 1024
#endif
  }()

  /// Disk entries not accessed for this long are deleted even if the cache is
  /// under ``diskByteLimit``. One named floor — not a magic number at the sweep.
  public static let diskEntryMaxAge: TimeInterval = 7 * 24 * 60 * 60

  private static let diskCache: DataCache? = {
    guard let cache = try? DataCache(name: "com.soda.piratic.artwork") else { return nil }
    cache.sizeLimit = diskByteLimit
    return cache
  }()

  /// How a decode fills its target box. Still / landscape cells need a centre crop so
  /// a 2:3 poster handed to a 16:9 tile does not letterbox; `TVPosterView` lockups must
  /// **not** crop — cover lettering has to stay readable (Sasha, 2026-10-02). Heroes
  /// use ``fillTop`` so opening a title does not jump — the top of the still stays put
  /// (Sasha, 2026-11-26).
  public enum ResizeMode: Sendable, Hashable {
    /// Centre-crop to the box (stills, wide cards, SwiftUI tiles).
    case fill
    /// Aspect-fill, crop from the **top** (heroes / banners). Nuke's `.fill` always
    /// centre-crops; a top-aligned SwiftUI frame cannot undo that.
    case fillTop
    /// Scale to fit inside the box, no crop — poster lockups.
    case fit
  }

  /// Largest title-logo slot on this platform, in points. Every logo load (session,
  /// slot cache hit, Home neighbour warmup, season-rail mark) uses this box and
  /// ``ResizeMode/fit`` so they share one Nuke key. `TitleLogoFit` then sizes the
  /// bitmap inside the real slot — it only reads `image.size`.
  public static var logoDecodeSize: CGSize {
#if os(tvOS)
    CGSize(width: 680, height: 170)
#elseif os(macOS)
    CGSize(width: 440, height: 120)
#else
    CGSize(width: 360, height: 96)
#endif
  }

  /// Longer side we will decode to, in pixels. Matches TMDB's last non-original
  /// token: 1280 for `.fit` (logos / posters), 1920 for `.fill` / `.fillTop` (backdrops).
  public static func maxDecodePixels(for mode: ResizeMode) -> CGFloat {
    mode == .fit ? 1280 : 1920
  }

  /// - Parameter size: the box this art is going into, in points. Artwork is decoded
  ///   down to it, and the size is part of the cache key — the same still in a rail and
  ///   in a grid is a different decode, and handing one out for the other is either
  ///   blurry or wasteful. `.zero` keeps full resolution and should be rare.
  /// - Parameter mode: `.fill` (default) centre-crops; `.fillTop` aspect-fills and crops
  ///   from the top (heroes); `.fit` preserves the whole cover for `TVPosterView` and
  ///   title logos (see `ResizeMode`).
  public static func request(_ url: URL, size: CGSize = .zero, mode: ResizeMode = .fill) -> ImageRequest {
    noteSeen(url, size: size, mode: mode)
    return makeRequest(url, size: size, mode: mode)
  }

  private static func makeRequest(_ url: URL, size: CGSize, mode: ResizeMode) -> ImageRequest {
    let url = WorkerArtwork.daily(WideArtwork.sized(url, forPoints: size))
    guard size != .zero else { return ImageRequest(url: url) }
    // Nuke's `unit: .points` multiplies by `Screen.scale`. On iOS/tvOS that is the
    // display scale; on **macOS Nuke hardcodes scale to 1** (see Nuke `Graphics.swift`
    // `enum Screen`). Passing card point sizes with `.points` therefore decoded 1×
    // bitmaps for Retina Macs — soft posters on every Home/Series rail (KP-14).
    // Convert to pixels ourselves with the densest attached screen (≥2 when unknown).
    let target = macOSPixelSize(forPoints: size)
    let unit: ImageProcessingOptions.Unit = target.unit
    let box = cappedSize(target.size, unit: unit, mode: mode)
    let processors: [any ImageProcessing]
    switch mode {
    case .fill:
      processors = [ImageProcessors.Resize(size: box, unit: unit, contentMode: .aspectFill, crop: true)]
    case .fillTop:
      // Exact pixel box, top-aligned — SwiftUI `.top` cannot undo Nuke's centre crop.
      let pixels = pixelDimensions(box, unit: unit)
      processors = [TopAlignedFillProcessor(pixelSize: CGSize(width: pixels.width.rounded(),
                                                              height: pixels.height.rounded()))]
    case .fit:
      processors = [ImageProcessors.Resize(size: box, unit: unit, contentMode: .aspectFit, crop: false)]
    }
    var request = ImageRequest(url: url, processors: processors)
    let pixels = pixelDimensions(box, unit: unit)
    let maxPixel = max(pixels.width, pixels.height)
    if maxPixel > 0 {
      request.thumbnail = ImageRequest.ThumbnailOptions(maxPixelSize: Float(maxPixel))
    }
    return request
  }

  /// Shrink a request box so the longer side is at most ``maxDecodePixels(for:)``.
  private static func cappedSize(_ size: CGSize, unit: ImageProcessingOptions.Unit,
                                 mode: ResizeMode) -> CGSize {
    let pixels = pixelDimensions(size, unit: unit)
    let longest = max(pixels.width, pixels.height)
    let cap = maxDecodePixels(for: mode)
    guard longest > cap, longest > 0 else { return size }
    let factor = cap / longest
    return CGSize(width: size.width * factor, height: size.height * factor)
  }

  private static func pixelDimensions(_ size: CGSize, unit: ImageProcessingOptions.Unit) -> CGSize {
    if unit == .pixels { return size }
    let scale = displayScale
    return CGSize(width: size.width * scale, height: size.height * scale)
  }

  /// Point box → Nuke resize unit. macOS always uses `.pixels` at display scale;
  /// other platforms keep Nuke's `.points` (it already multiplies by scale).
  ///
  /// Floor 2 is KP-14 (Nuke's macOS `Screen.scale` is 1; 1× requests made Retina
  /// posters soft). The signpost cache (`displayScale`) must not feed this — a
  /// 1× snapshot would halve request pixels and miss the memory cache.
  private static func macOSPixelSize(forPoints size: CGSize) -> (size: CGSize, unit: ImageProcessingOptions.Unit) {
#if os(macOS)
    let scale = macOSRequestScale
    return (CGSize(width: size.width * scale, height: size.height * scale), .pixels)
#else
    return (size, .points)
#endif
  }

#if os(macOS)
  /// Live screen scale for **requests**, ≥2. Independent of the signpost cache.
  static var macOSRequestScale: CGFloat {
    max(NSScreen.screens.map(\.backingScaleFactor).max() ?? 2, 2)
  }
#endif

  /// Already-decoded art at this size, or nil. Synchronous on purpose: a cell calls this
  /// while configuring so a recycled tile never paints a placeholder.
  ///
  /// `mode` is part of the cache key. A logo warmed with `.fit` is invisible to a
  /// `.fill` probe (and the reverse would centre-crop the PNG).
  public static func cachedImage(for url: URL, size: CGSize = .zero, mode: ResizeMode = .fill) -> PlatformImage? {
    pipeline.cache[request(url, size: size, mode: mode)]?.image
  }

  /// Any size of this URL already decoded in memory — the largest this session asked
  /// for — or nil. For a stand-in that only has to be there at once (the title page's
  /// blurred backdrop placeholder is the card's poster, decoded at the card's size).
  public static func anyCachedImage(for url: URL) -> PlatformImage? {
    let variants = seen.withLock { $0[url] ?? [] }
      .sorted { $0.size.width * $0.size.height > $1.size.width * $1.size.height }
    for variant in variants {
      if let image = pipeline.cache[makeRequest(url, size: variant.size, mode: variant.mode)]?.image {
        return image
      }
    }
    return nil
  }

  /// Title-logo cache probe. Same key as ``logoImage(for:)`` / ``logoWithSource(for:)``.
  public static func cachedLogo(for url: URL) -> PlatformImage? {
    cachedImage(for: url, size: logoDecodeSize, mode: .fit)
  }

  /// Decode (or cache-hit) off the call site's actor. `FallbackRemoteImage` and
  /// `ArtworkImage` go through this so they never import Nuke.
  ///
  /// `mode` defaults to `.fill` (stills / backdrops). Logos must pass `.fit`.
  public static func image(for url: URL, size: CGSize = .zero, mode: ResizeMode = .fill) async throws -> PlatformImage {
    try await tracedResponse(url, size: size, mode: mode).image
  }

  /// Title-logo decode. Same key as ``cachedLogo(for:)``.
  public static func logoImage(for url: URL) async throws -> PlatformImage {
    try await image(for: url, size: logoDecodeSize, mode: .fit)
  }

  /// Warm the data cache for art that is about to appear (context-menu preview, etc.).
  /// Bytes only — same policy as `TVUIKitRemoteImage.prefetch`.
  public static func prefetch(_ urls: [URL?]) {
    let requests = urls.compactMap { $0 }.map { request($0) }
    guard !requests.isEmpty else { return }
    prefetcher.startPrefetching(with: requests)
  }

  private static let prefetcher: ImagePrefetcher = {
    let prefetcher = ImagePrefetcher(pipeline: pipeline, destination: .diskCache)
    prefetcher.priority = .high
    return prefetcher
  }()

  /// `image(for:)`, plus where it came from: the URL that answered after redirects
  /// (nil from a cache, which does not keep it), the worker language stamp when the
  /// final URL or `Content-Language` carries `ru` / `en` / `und`, and the tier —
  /// `memory`, `disk` or `network`. For the source log and hero captions.
  ///
  /// `mode` is part of the decode, the same as `request`: `.fill` centre-crops, `.fit`
  /// keeps the whole picture. A caller that passes `.fit` to `load` and then forgets it
  /// here gets a cropped bitmap back.
  public static func imageWithSource(for url: URL, size: CGSize = .zero,
                                     mode: ResizeMode = .fill) async throws
    -> (image: PlatformImage, answered: URL?, language: WorkerArtworkLanguageTag?, tier: String) {
    let response = try await tracedResponse(url, size: size, mode: mode)
    let tier = cacheTier(response.cacheType)
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

  /// Title-logo decode plus worker language stamp. Same key as ``cachedLogo(for:)``.
  public static func logoWithSource(for url: URL) async throws
    -> (image: PlatformImage, answered: URL?, language: WorkerArtworkLanguageTag?, tier: String) {
    try await imageWithSource(for: url, size: logoDecodeSize, mode: .fit)
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
    let activity = NetworkActivity.begin(request)
    defer { NetworkActivity.end(activity) }
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
    workerLanguageByRequestURL.withLock { $0[requestURL] = language }
  }

  private static func rememberedWorkerLanguage(for requestURL: URL) -> WorkerArtworkLanguageTag? {
    workerLanguageByRequestURL.withLock { $0[requestURL] }
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
    let urls = seen.withLock { Array($0.keys) }
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
    seen.withLock { $0.removeAll() }
    workerLanguageByRequestURL.withLock { $0.removeAll() }
  }

  /// Drops one title's pictures: the decoded sizes this session actually asked for,
  /// and the original bytes on disk. Other titles stay.
  public static func remove(urls: some Sequence<URL>) {
    let unique = Array(Set(urls))
    guard !unique.isEmpty else { return }
    let variants: [(URL, SeenVariant)] = seen.withLock { table in
      var variants: [(URL, SeenVariant)] = []
      for url in unique {
        if let stored = table[url] {
          variants.append(contentsOf: stored.map { (url, $0) })
        }
        table[url] = nil
      }
      return variants
    }
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
    workerLanguageByRequestURL.withLock { table in
      for url in unique {
        table[url] = nil
      }
    }
  }

  private struct SeenVariant: Hashable, Sendable {
    var size: CGSize
    var mode: ResizeMode
  }

  /// Sizes this process has asked Nuke to decode, so Settings and "remove this
  /// title" can name the memory entries. Touched from card layout on the main
  /// actor and from cache clearing, which is why it is a mutex and not a global.
  private static let seen = Mutex<[URL: Set<SeenVariant>]>([:])

  private static func noteSeen(_ url: URL, size: CGSize, mode: ResizeMode) {
    seen.withLock { _ = $0[url, default: []].insert(SeenVariant(size: size, mode: mode)) }
  }

  // MARK: - Decode size / signposts

  /// Drawn box in points → pixels the pipeline will actually decode. `.zero` means
  /// full source resolution (no downsample). Caps at ``maxDecodePixels(for:)``.
  public static func pixelSize(forPoints size: CGSize, mode: ResizeMode = .fill) -> CGSize {
    guard size != .zero else { return .zero }
    let target = macOSPixelSize(forPoints: size)
    let box = cappedSize(target.size, unit: target.unit, mode: mode)
    return pixelDimensions(box, unit: target.unit)
  }

  /// Decoded bitmap bytes (row × height), or a 4-bytes-per-pixel estimate.
  public static func decodedByteCount(_ image: PlatformImage) -> Int {
#if os(macOS)
    if let rep = image.representations.first as? NSBitmapImageRep {
      return max(rep.bytesPerRow * rep.pixelsHigh, 0)
    }
    let pixels = image.representations.first
    let width = pixels?.pixelsWide ?? Int(image.size.width)
    let height = pixels?.pixelsHigh ?? Int(image.size.height)
    return max(width * height * 4, 0)
#else
    if let cg = image.cgImage {
      return max(cg.bytesPerRow * cg.height, 0)
    }
    let scale = image.scale
    return max(Int(image.size.width * scale * image.size.height * scale * 4), 0)
#endif
  }

  public static func noteDisplayed(_ image: PlatformImage, url: URL, size: CGSize) {
    PerfSignpost.emitArtworkDisplay(
      url: url,
      bytes: decodedByteCount(image),
      pixelSize: pixelSize(forPoints: size)
    )
  }

  /// Last scale seen on the main actor. `pixelSize` / `tracedResponse` run off-main
  /// (`async` Nuke); `UITraitCollection.current` and `NSScreen.screens` are undefined
  /// there and often report 1.0 on Apple TV 4K (2×). Signposts only — not requests.
  private static let cachedDisplayScale = Mutex<CGFloat>(0)

  @MainActor
  private enum DisplayScaleObserver {
    static var token: (any NSObjectProtocol)?
#if os(iOS)
    static var sceneToken: (any NSObjectProtocol)?
#endif
  }

  @MainActor
  private enum CacheEvictionObserver {
    static var started = false
    static var tokens: [any NSObjectProtocol] = []
  }

  /// Snapshot the screen scale on the main actor for **signposts** (`pixelSize`
  /// off-main). Does not change Nuke request sizes.
  ///
  /// Reads the screen / window traits — never `UITraitCollection.current` outside
  /// a trait context (that is often 1.0 in `App.init`, while Apple TV 4K is 2×).
  @MainActor
  public static func rememberDisplayScale() {
#if os(macOS)
    cacheDisplayScale(
      NSScreen.main?.backingScaleFactor
        ?? NSScreen.screens.map(\.backingScaleFactor).max()
        ?? 2
    )
#else
    cacheDisplayScale(liveUIKitDisplayScale())
#endif
  }

#if !os(macOS)
  @MainActor
  private static func liveUIKitDisplayScale() -> CGFloat {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first
    if let scene {
      let window = scene.windows.first(where: \.isKeyWindow) ?? scene.windows.first
      let scale = window?.screen.scale ?? scene.screen.scale
      if scale > 0 { return scale }
      let traits = window?.traitCollection.displayScale ?? scene.traitCollection.displayScale
      if traits > 0 { return traits }
    }
    let traits = UITraitCollection.current.displayScale
    return traits > 0 ? traits : 1
  }
#endif

  /// Call once at launch. Re-snapshots when the screen configuration changes —
  /// not on every artwork load. Also starts memory/disk eviction observers.
  @MainActor
  public static func startRememberingDisplayScale() {
    rememberDisplayScale()
    startCacheEviction()
    guard DisplayScaleObserver.token == nil else { return }
#if os(macOS)
    DisplayScaleObserver.token = NotificationCenter.default.addObserver(
      forName: NSApplication.didChangeScreenParametersNotification,
      object: nil,
      queue: .main
    ) { _ in
      MainActor.assumeIsolated { rememberDisplayScale() }
    }
#else
    DisplayScaleObserver.token = NotificationCenter.default.addObserver(
      forName: UIScreen.modeDidChangeNotification,
      object: nil,
      queue: .main
    ) { _ in
      MainActor.assumeIsolated { rememberDisplayScale() }
    }
#if os(iOS)
    // Foldable / multi-scene: screen mode often does not change when the window
    // geometry does (iPhone Duo). Re-read scale when a scene activates.
    DisplayScaleObserver.sceneToken = NotificationCenter.default.addObserver(
      forName: UIScene.didActivateNotification,
      object: nil,
      queue: .main
    ) { _ in
      MainActor.assumeIsolated { rememberDisplayScale() }
    }
#endif
#endif
  }

  /// Memory TTL + aggressive trim on pressure/background (tvOS/iOS). Disk LRU
  /// size sweep plus ``diskEntryMaxAge`` — both off the main thread.
  ///
  /// Nuke's `ImageCache` already `removeAll`s on `DispatchSourceMemoryPressure`
  /// and trims to 10 % on `didEnterBackground`. We still observe the UIKit
  /// names so a warning that did not go through that source is handled, and so
  /// the disk age floor runs at the same moment.
  @MainActor
  public static func startCacheEviction() {
    scheduleDiskSweep()
    guard !CacheEvictionObserver.started else { return }
    CacheEvictionObserver.started = true
#if os(iOS) || os(tvOS)
    let center = NotificationCenter.default
    CacheEvictionObserver.tokens = [
      center.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification,
                         object: nil, queue: .main) { _ in
        MainActor.assumeIsolated { trimMemoryForWarning() }
      },
      center.addObserver(forName: UIApplication.didEnterBackgroundNotification,
                         object: nil, queue: .main) { _ in
        MainActor.assumeIsolated {
          trimMemoryForBackground()
          scheduleDiskSweep()
        }
      }
    ]
#endif
  }

  /// Drop every decoded image. Memory warning: the process is about to be jetsam'd.
  public static func trimMemoryForWarning() {
    memoryCache.removeAll()
  }

  /// Keep a tenth of the budget so a return to Home is not a cold decode of the
  /// current hero, but the rest of the session is gone.
  public static func trimMemoryForBackground() {
    memoryCache.trim(toCost: memoryByteLimit / 10)
    memoryCache.trim(toCount: max(memoryCountLimit / 10, 1))
  }

  /// Size LRU (`DataCache.sweep`) and the 7-day age floor. Never on the hot path:
  /// `DataCache.queue` is utility I/O; `sweep()` hops there via `sync`, so we
  /// bounce off a detached task instead of the main thread.
  public static func scheduleDiskSweep() {
    guard let cache = diskCache else { return }
    let path = cache.path
    let maxAge = diskEntryMaxAge
    cache.queue.async {
      removeExpiredDiskEntries(in: path, olderThan: maxAge)
    }
    Task.detached(priority: .utility) {
      cache.sweep()
    }
  }

  /// Files whose content-access date is older than `maxAge`. Hidden Nuke staging
  /// files (`.tmp`, `.data-cache-info`) are skipped.
  public static func expiredDiskURLs(in directory: URL, olderThan maxAge: TimeInterval,
                                     now: Date = Date()) -> [URL] {
    guard maxAge > 0,
          let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentAccessDateKey],
            options: .skipsHiddenFiles
          ) else { return [] }
    let cutoff = now.addingTimeInterval(-maxAge)
    return urls.filter { url in
      let accessed = (try? url.resourceValues(forKeys: [.contentAccessDateKey]).contentAccessDate)
        ?? (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
        ?? Date()
      return accessed < cutoff
    }
  }

  static func removeExpiredDiskEntries(in directory: URL, olderThan maxAge: TimeInterval,
                                       now: Date = Date()) {
    for url in expiredDiskURLs(in: directory, olderThan: maxAge, now: now) {
      try? FileManager.default.removeItem(at: url)
    }
  }

  public static func cacheDisplayScale(_ scale: CGFloat) {
    cachedDisplayScale.withLock { $0 = max(scale, 1) }
  }

  /// Safe from any actor. Uses the last main-actor snapshot, or a platform
  /// default — never `UITraitCollection.current` off the main actor.
  public static var displayScale: CGFloat {
    let cached = cachedDisplayScale.withLock { $0 }
    if cached > 0 { return cached }
#if os(tvOS)
    return 2
#elseif os(macOS)
    return 2
#else
    return 3
#endif
  }

  private static func cacheTier(_ type: ImageResponse.CacheType?) -> String {
    switch type {
    case .memory: "memory"
    case .disk: "disk"
    case .none: "network"
    @unknown default: "unknown"
    }
  }

  private static func tracedResponse(_ url: URL, size: CGSize, mode: ResizeMode) async throws
    -> ImageResponse {
    let imageRequest = request(url, size: size, mode: mode)
    let pixels = pixelSize(forPoints: size, mode: mode)
    let interval = PerfSignpost.beginArtworkRequest(url: url, pixelSize: pixels)
    do {
      let response = try await pipeline.imageTask(with: imageRequest).response
      interval.endArtwork(
        tier: cacheTier(response.cacheType),
        bytes: decodedByteCount(response.image),
        pixelSize: pixels
      )
      return response
    } catch {
      interval.endArtwork(tier: "error", bytes: 0, pixelSize: pixels)
      throw error
    }
  }
}

/// Reports worker image routes and resolves direct kino.pub artwork mirrors inside
/// the download, so Nuke still coalesces and caches under the requested URL.
final class ArtworkDataLoader: DataLoading, Sendable {
  private static let mirrorAttemptTimeout: TimeInterval = 4
  private let inner: DataLoader

  init(_ inner: DataLoader) {
    self.inner = inner
  }

  func loadData(
    with request: URLRequest,
    didReceiveData: @escaping @Sendable (Data, URLResponse) -> Void,
    completion: @escaping @Sendable (Error?) -> Void
  ) -> any Cancellable {
    if let url = request.url, let candidates = KinoPubArtworkCDN.origins(for: url) {
      return MirrorLoad(task: Task {
        var attempt = request
        attempt.timeoutInterval = Self.mirrorAttemptTimeout
        var lastError: Error = URLError(.badServerResponse)
        for candidate in candidates {
          guard !Task.isCancelled else { return }
          attempt.url = candidate
          do {
            let (data, response) = try await inner.session.data(for: attempt)
            if let error = DataLoader.validate(response: response) { throw error }
            // A block page or a PNG "processing" frame can be an HTTP 200.
            guard data.starts(with: [0xff, 0xd8, 0xff]) else {
              throw URLError(.cannotDecodeContentData)
            }
            guard !Task.isCancelled else { return }
            didReceiveData(data, response)
            completion(nil)
            return
          } catch {
            lastError = error
          }
        }
        if !Task.isCancelled { completion(lastError) }
      })
    }
    guard let url = request.url, NetworkActivity.reportsArtworkRequest(url) else {
      return inner.loadData(with: request, didReceiveData: didReceiveData, completion: completion)
    }
    let token = NetworkActivity.begin(request)
    let box = ActivityReportCancellable(token: token)
    box.hold(inner.loadData(with: request, didReceiveData: didReceiveData) { error in
      box.complete()
      completion(error)
    })
    return box
  }

  private struct MirrorLoad: Cancellable {
    let task: Task<Void, Never>
    func cancel() { task.cancel() }
  }
}

private final class ActivityReportCancellable: Cancellable, Sendable {
  private struct State {
    var ended = false
    var isCancelled = false
    var inner: (any Cancellable)?
  }

  private let token: UUID
  private let state = Mutex(State())

  init(token: UUID) {
    self.token = token
  }

  /// The transfer this reports. Cancelled at once if `cancel()` came first.
  func hold(_ inner: any Cancellable) {
    let isCancelled = state.withLock { state in
      state.inner = inner
      return state.isCancelled
    }
    if isCancelled { inner.cancel() }
  }

  func cancel() {
    end(holdMinimum: false)
    let inner = state.withLock { state in
      state.isCancelled = true
      return state.inner
    }
    inner?.cancel()
  }

  func complete() {
    end(holdMinimum: true)
  }

  private func end(holdMinimum: Bool) {
    let isFirst = state.withLock { state in
      defer { state.ended = true }
      return !state.ended
    }
    guard isFirst else { return }
    NetworkActivity.end(token, holdMinimum: holdMinimum)
  }
}

/// Aspect-fills `pixelSize`, then crops from the **top** (horizontally centred). Nuke's
/// `Resize(crop: true)` always centres vertically, which cuts hero heads and jumps when
/// the title page opens top-aligned (Sasha, 2026-11-26).
///
/// Output is **opaque 32BGRA-compatible** (not RGBA). SwiftUI `.blur` / zoom /
/// `drawingGroup` build `CVPixelBuffer`s; RGBA returns `kCVReturnInvalidPixelFormat`
/// (-6680) — seen on iPhone Duo opening a title from the Home banner.
private struct TopAlignedFillProcessor: ImageProcessing, Sendable {
  let pixelSize: CGSize

  var identifier: String {
    "com.piratic.artwork.topfill/\(Int(pixelSize.width))x\(Int(pixelSize.height))"
  }

  func process(_ image: PlatformImage) -> PlatformImage? {
    // Multiple of 4 so BGRA `bytesPerRow = width×4` is 16-byte aligned for Core Video.
    let width = Self.align(pixelSize.width)
    let height = Self.align(pixelSize.height)
    let target = CGSize(width: width, height: height)
    guard target.width.isFinite, target.height.isFinite,
          target.width >= 4, target.height >= 4,
          target.width <= 8192, target.height <= 8192 else { return image }
#if os(macOS)
    let src = image.size
    guard src.width > 0, src.height > 0 else { return image }
    let scale = max(target.width / src.width, target.height / src.height)
    let draw = CGRect(x: (target.width - src.width * scale) / 2,
                      y: target.height - src.height * scale, // AppKit origin is bottom-left; top align
                      width: src.width * scale,
                      height: src.height * scale)
    let out = NSImage(size: target)
    out.lockFocus()
    NSColor.black.setFill()
    NSRect(origin: .zero, size: target).fill()
    image.draw(in: draw, from: .zero, operation: .copy, fraction: 1)
    out.unlockFocus()
    return out
#else
    let src = image.size
    guard src.width > 0, src.height > 0 else { return image }
    let scale = max(target.width / src.width, target.height / src.height)
    let draw = CGRect(x: (target.width - src.width * scale) / 2,
                      y: 0, // top
                      width: src.width * scale,
                      height: src.height * scale)
    // Opaque → Metal-friendly BGRA, not RGBA (CVPixelBufferCreate -6680 on Duo).
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    return UIGraphicsImageRenderer(size: target, format: format).image { ctx in
      UIColor.black.setFill()
      ctx.fill(CGRect(origin: .zero, size: target))
      image.draw(in: draw)
    }
#endif
  }

  /// Round up to a multiple of 4 (BGRA row alignment). Rejects non-finite / empty sizes.
  private static func align(_ value: CGFloat) -> CGFloat {
    guard value.isFinite, value > 0 else { return 4 }
    return max(4, (value / 4).rounded(.up) * 4)
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

/// kino.pub's `wide` stills are whatever someone uploaded — 1280 px one title, 3050 px
/// the next, 366 KB for a card drawn 400 pt wide (Sasha, 2026-11-21). They are fetched
/// through wsrv.nl at the width they are drawn at, as WebP: the same still is ~8 KB at
/// 500 px. Only kino.pub's wide path is rewritten; the worker's own `/img` answers are
/// already sized and served through wsrv by the worker (KP-68).
///
/// The worker's image route answers with whatever it picks today: a Russian cover that
/// appeared on TMDB, a pin from the picture sheet. The disk cache keeps a file as long as
/// it is looked at, so a title on Home kept its first answer for good (Sasha,
/// 2026-11-26). A discovery URL (`/img/{kind}/by/kinopub/{id}`) carries the day, so each
/// title is asked again once a day; the worker ignores `d`, and its stamped files stay
/// edge-cached, so a re-ask with no change is one redirect and a cached file.
enum WorkerArtwork {
  static let refreshInterval: TimeInterval = 24 * 60 * 60

  static func daily(_ url: URL, now: Date = Date()) -> URL {
    let parts = url.path.split(separator: "/")
    guard parts.count == 5, parts[0] == "img", parts[2] == "by", parts[3] == "kinopub",
          var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
          components.queryItems?.contains(where: { $0.name == "d" }) != true else { return url }
    let day = Int(now.timeIntervalSince1970 / refreshInterval)
    components.queryItems = (components.queryItems ?? []) + [URLQueryItem(name: "d", value: String(day))]
    return components.url ?? url
  }
}

/// `-PIRATICWideOriginal YES` loads the originals, to compare.
enum WideArtwork {
  /// Widths are rounded up to this step so a few card sizes share one file.
  static let step = 160
  /// Full-screen use (`size == .zero`) on the largest screen.
  static let fullScreenPixels = 3840

  static var isEnabled: Bool {
    !UserDefaults.standard.bool(forKey: "PIRATICWideOriginal")
  }

  static func isKinopubWide(_ url: URL) -> Bool {
    url.path.contains("/poster/item/wide/") && url.host?.contains("wsrv.nl") != true
  }

  static func sized(_ url: URL, forPoints size: CGSize) -> URL {
    guard isEnabled, isKinopubWide(url) else { return url }
    let pixels: Int
    if size == .zero {
      pixels = fullScreenPixels
    } else {
      // Filled into its box: as wide as the box, or as the box's height at 16:9 when
      // the box is taller than the still. Two pixels a point covers a 4K screen.
      let points = max(size.width, size.height * 16 / 9)
      pixels = Int((points * scale).rounded(.up))
    }
    let width = min(fullScreenPixels, ((pixels + step - 1) / step) * step)
    var components = URLComponents(string: "https://wsrv.nl/")
    components?.queryItems = [
      URLQueryItem(name: "url", value: url.absoluteString),
      URLQueryItem(name: "w", value: String(width)),
      URLQueryItem(name: "we", value: nil),
      URLQueryItem(name: "q", value: "80"),
      URLQueryItem(name: "output", value: "webp"),
    ]
    return components?.url ?? url
  }

  /// Pixels per point asked for. macOS sizes already arrive in pixels' worth of points
  /// at the request scale; elsewhere 2× covers Apple TV 4K and Retina screens.
  private static var scale: CGFloat {
#if os(macOS)
    Artwork.macOSRequestScale
#else
    2
#endif
  }
}
