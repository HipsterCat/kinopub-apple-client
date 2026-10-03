#if os(tvOS)
//
//  TVUIKitRemoteImage.swift
//  KinoPubUI
//
//  Artwork for the TVUIKit cells. This is a thin face on the shared `Artwork` pipeline,
//  kept because the cells want three UIKit-shaped things the pipeline states differently:
//  a *synchronous* cache probe while a cell is being configured, an async load, and
//  prefetch/cancel driven by `UICollectionViewDataSourcePrefetching`.
//
//  It used to be a hand-written cache — `NSCache` of decoded images keyed by tile size,
//  an actor coalescing in-flight requests, `preparingThumbnail` downsampling. All four
//  behaviours still hold; `Artwork` provides them now, on every platform instead of only
//  this one. See `ArtworkPipeline.swift` for why they are needed at all.
//
//  Catalog / person poster grids load through `load(into: TVPosterView…)` — Nuke's
//  `TVPosterView` display path (`NukeExtensions`) — so the lockup owns aspect and focus
//  scale. Do not put a second `UIImageView` crop/fill stack over a poster lockup.
//

import UIKit
import TVUIKit
import Nuke
import NukeExtensions

/// Nuke's `TVPosterView` display path (`nuke_display`) is overridden to assign the
/// image on the next main-queue turn — `TVPosterView` only computes a non-zero
/// `focusSizeIncrease` when the image lands outside a layout pass (tvOS 27.2 adapter).
///
/// Lives here so NukeExtensions does not leak past `TVUIKitRemoteImage`.
@MainActor
class TVUIKitDeferredPosterView: TVPosterView {
  private var pendingImageToken: UInt = 0

  /// NukeExtensions calls this for `loadImage(into:)`. Defer so focus envelope math runs.
  override func nuke_display(image: UIImage?, data: Data?) {
    pendingImageToken &+= 1
    let token = pendingImageToken
    guard let image else {
      self.image = nil
      return
    }
    DispatchQueue.main.async { [weak self] in
      guard let self, self.pendingImageToken == token else { return }
      self.image = image
    }
  }
}

@MainActor
public enum TVUIKitRemoteImage {

  /// Prefetching stops at the **data** cache: it downloads bytes and does not decode.
  ///
  /// A cell decodes to its own tile size, and the controller doing the prefetching does
  /// not know that size — decoding here would either fill an Apple TV's memory with
  /// full-resolution art or warm a cache key no cell ever asks for. Bytes are keyed by
  /// URL alone, so warming those helps every size. (The tasks this replaced did decode,
  /// at full resolution, under a key the poster and wide cells never read.)
  ///
  /// Low priority so on-screen art never queues behind art that might scroll into view,
  /// and cancellable — the fire-and-forget tasks were not.
  private static let prefetcher: ImagePrefetcher = {
    let prefetcher = ImagePrefetcher(pipeline: Artwork.pipeline, destination: .diskCache)
    prefetcher.priority = .low
    return prefetcher
  }()

  /// Already-decoded art for this URL at this tile size, or nil. Synchronous on purpose:
  /// a cell calls this while configuring so a recycled tile never paints a placeholder.
  public static func cached(url: URL?, size: CGSize = .zero,
                            mode: Artwork.ResizeMode = .fill) -> UIImage? {
    guard let url else { return nil }
    return Artwork.cachedImage(for: url, size: size, mode: mode)
  }

  /// - Parameter size: the tile this art is going into, in points. Artwork is decoded
  ///   down to it — passing `.zero` keeps full resolution and should be rare.
  public static func load(url: URL?, size: CGSize = .zero,
                          mode: Artwork.ResizeMode = .fill) async -> UIImage? {
    guard let url else { return nil }
    do {
      let response = try await Artwork.pipeline.imageTask(with: Artwork.request(url, size: size, mode: mode)).response
      ArtworkLog.loaded(url, from: tier(of: response))
      return response.image
    } catch {
      // Missing actor portraits answer 403 by design (see `ActorImageProvider`), so
      // this is a routine line, not an incident.
      ArtworkLog.failed(url, reason: error.localizedDescription)
      return nil
    }
  }

  /// Assign art through the deferred `TVPosterView` display path so
  /// `focusSizeIncrease` is computed outside a layout pass.
  public static func display(_ image: UIImage?, on posterView: TVPosterView) {
    posterView.nuke_display(image: image, data: nil)
  }

  /// Load into a `TVPosterView` via Nuke's integrated display path (`NukeExtensions`).
  ///
  /// Decodes with `.fit` (no centre crop) so cover lettering stays readable — the
  /// shared `.fill` path is for still / landscape boxes that need a fixed aspect.
  /// Never set `contentModes` here: changing `imageView.contentMode` / clipping the
  /// lockup kills parallax (AGENTS.md). Deferred image assignment for
  /// `focusSizeIncrease` lives on `TVUIKitDeferredPosterView.nuke_display`.
  @discardableResult
  public static func load(into posterView: TVPosterView,
                          url: URL?,
                          size: CGSize,
                          placeholder: UIImage) -> ImageTask? {
    guard let url else {
      // `nil` request cancels any in-flight Nuke task tied to this view.
      _ = loadImage(with: nil as ImageRequest?, options: reuseOptions(placeholder: placeholder), into: posterView) { _ in }
      posterView.nuke_display(image: placeholder, data: nil)
      ArtworkLog.skipped(by: "poster", reason: "no artwork URL")
      return nil
    }
    if cached(url: url, size: size, mode: .fit) != nil {
      ArtworkLog.servedFromMemory(url, by: "poster")
    } else {
      ArtworkLog.requested(url, by: "poster")
    }
    var options = ImageLoadingOptions(
      placeholder: placeholder,
      transition: nil,
      failureImage: placeholder,
      failureImageTransition: nil,
      contentModes: nil
    )
    options.pipeline = Artwork.pipeline
    // Keep the current image until the new decode lands — blanking mid-scroll is worse
    // than a one-frame-stale poster. `nuke_display` still defers the real assignment.
    options.isPrepareForReuseEnabled = false
    options.isProgressiveRenderingEnabled = false
    return loadImage(with: Artwork.request(url, size: size, mode: .fit), options: options, into: posterView) { result in
      switch result {
      case .success(let response):
        ArtworkLog.loaded(url, from: tier(of: response))
      case .failure(let error):
        ArtworkLog.failed(url, reason: error.localizedDescription)
      }
    }
  }

  /// Drop any in-flight Nuke request tied to this lockup (reuse / reconfigure).
  public static func cancel(into posterView: TVPosterView) {
    _ = loadImage(with: nil as ImageRequest?, options: reuseOptions(placeholder: nil), into: posterView) { _ in }
  }

  /// Warm the data cache for art that is about to scroll into view.
  public static func prefetch(_ urls: [URL?]) {
    prefetcher.startPrefetching(with: requests(urls))
  }

  /// Stop warming art that scrolled back out of range before it was needed.
  public static func cancelPrefetch(_ urls: [URL?]) {
    prefetcher.stopPrefetching(with: requests(urls))
  }

  private static func requests(_ urls: [URL?]) -> [ImageRequest] {
    urls.compactMap { $0 }.map { Artwork.request($0) }
  }

  private static func reuseOptions(placeholder: UIImage?) -> ImageLoadingOptions {
    var options = ImageLoadingOptions(placeholder: placeholder, transition: nil,
                                      failureImage: placeholder, failureImageTransition: nil,
                                      contentModes: nil)
    options.pipeline = Artwork.pipeline
    options.isPrepareForReuseEnabled = true
    return options
  }

  private static func tier(of response: ImageResponse) -> String {
    switch response.cacheType {
    case .memory: return "memory"
    case .disk: return "disk"
    case .none: return "network"
    @unknown default: return "unknown"
    }
  }
}
#endif
