//
//  FallbackRemoteImage.swift
//  PiraticUI
//
//  Tries URLs in order (wide → big → poster) and keeps the first that returns image
//  bytes. The fallback chain is ours — no image library models "try these in order" —
//  but each attempt goes through the shared `Artwork` pipeline, so a candidate that
//  already failed or already loaded is answered from cache instead of refetched.
//

import SwiftUI
import OSLog

private let artLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Piratic", category: "Artwork")

/// Loads the first URL that returns image bytes. Used by Home banners where
/// catalogue `/wide/` derivations often 404 while `big` still paints.
public struct FallbackRemoteImage: View {
  private let urls: [URL]
  private let contentMode: ContentMode
  /// Drawn box in points. `.zero` waits for a layout measurement so a hero that
  /// did not pass a size still decodes at the frame, not at full source.
  private let size: CGSize
  /// Decode crop. Heroes pass ``Artwork/ResizeMode/fillTop`` so the still keeps its
  /// top (Sasha, 2026-11-26); shelves keep the default centre ``fill``.
  private let resizeMode: Artwork.ResizeMode
  private let keepsImageWhileReloading: Bool
  private let paintsFromMemory: Bool
  private let onLoaded: (() -> Void)?
  private let onFailed: (() -> Void)?
  @State private var image: Image?
  @State private var measured: CGSize = .zero

  /// `onFailed`: every candidate failed, or there was none.
  public init(urls: [URL], contentMode: ContentMode = .fill,
              size: CGSize = .zero,
              resizeMode: Artwork.ResizeMode = .fill,
              keepsImageWhileReloading: Bool = false,
              paintsFromMemory: Bool = false,
              onLoaded: (() -> Void)? = nil, onFailed: (() -> Void)? = nil) {
    self.urls = urls
    self.contentMode = contentMode
    self.size = size
    self.resizeMode = resizeMode
    self.keepsImageWhileReloading = keepsImageWhileReloading
    self.paintsFromMemory = paintsFromMemory
    self.onLoaded = onLoaded
    self.onFailed = onFailed
  }

  public var body: some View {
    Group {
      if let image = image ?? (paintsFromMemory ? cachedImage : nil) {
        image
          .resizable()
          .aspectRatio(contentMode: contentMode)
          .transition(.opacity)
      } else {
          Color.clear
      }
    }
    .background {
      Color.clear
        .onGeometryChange(for: CGSize.self) { proxy in
          size == .zero ? proxy.size : .zero
        } action: { newSize in
          if measured != newSize && newSize.width > 1 && newSize.height > 1 {
            measured = newSize
          }
        }
    }
    .task(id: taskKey) {
      await load()
    }
  }

  private var decodeSize: CGSize { size != .zero ? size : measured }

  private var taskKey: String {
    "\(listKey)#\(Int(decodeSize.width))x\(Int(decodeSize.height))#\(resizeMode)"
  }

  /// How a picture that had to be fetched comes in. One from the memory cache paints on
  /// the first frame instead — fading in art that is already there reads as a flicker.
  public static let fadeIn = Animation.easeInOut(duration: 0.5)

  /// The candidate that painted last time, per candidate list: a view rebuilt on coming
  /// back to a page paints it from the memory cache on the first frame, instead of
  /// starting over at a first candidate that failed (and briefly showing nothing).
  @MainActor private static let winners: NSCache<NSString, NSURL> = {
    let cache = NSCache<NSString, NSURL>()
    cache.countLimit = 512
    return cache
  }()

  private var listKey: String { urls.map(\.absoluteString).joined(separator: "|") }

  @MainActor
  private var cachedURL: URL? {
    (Self.winners.object(forKey: listKey as NSString) as URL?) ?? urls.first
  }

  @MainActor
  private var cachedImage: Image? {
    guard let cachedURL, decodeSize.width > 1, decodeSize.height > 1 else { return nil }
    return Artwork.cachedImage(for: cachedURL, size: decodeSize, mode: resizeMode).map(Image.init(platformImage:))
  }

  @MainActor
  private func load() async {
    let box = decodeSize
    guard box.width > 1, box.height > 1 else { return }
    let key = listKey as NSString
    if let known = cachedURL, let cached = Artwork.cachedImage(for: known, size: box, mode: resizeMode) {
      Artwork.noteDisplayed(cached, url: known, size: box)
      image = Image(platformImage: cached)
      onLoaded?()
      return
    }
    if !keepsImageWhileReloading { image = nil }

    guard !urls.isEmpty else {
      artLog.debug("FallbackRemoteImage: no candidate URLs")
      onFailed?()
      return
    }

    for url in urls {
      if Task.isCancelled { return }
      do {
        let loaded = try await Artwork.image(for: url, size: box, mode: resizeMode)
        guard !Task.isCancelled else { return }
        Artwork.noteDisplayed(loaded, url: url, size: box)
        if keepsImageWhileReloading {
          image = Image(platformImage: loaded)
        } else {
          withAnimation(Self.fadeIn) { image = Image(platformImage: loaded) }
        }
        Self.winners.setObject(url as NSURL, forKey: key)
        onLoaded?()
        artLog.debug("art OK \(url.absoluteString, privacy: .public)")
        #if DEBUG
        print("[Artwork] OK \(url.absoluteString)")
        #endif
        return
      } catch {
        // A 404 on a `/wide/` derivation is the normal case this view exists for, not
        // an incident — the next candidate usually paints.
        artLog.debug("art error \(url.absoluteString, privacy: .public): \(error.localizedDescription, privacy: .public)")
        #if DEBUG
        print("[Artwork] fail \(url.absoluteString) — \(error.localizedDescription)")
        #endif
      }
    }

    if Task.isCancelled { return }
    onFailed?()
    artLog.debug("FallbackRemoteImage: all candidates failed (\(urls.count))")
    #if DEBUG
    print("[Artwork] exhausted \(urls.count) candidates")
    #endif
  }
}
