//
//  PageBackdrop.swift
//  KinoPubUI
//
//  INTERIM — to be replaced, not extended (Sasha, 2026-10-11: crutches without reading
//  the APIs; ROADMAP › Redo the tvOS backdrop properly). What is decided is only that the
//  picture is one full-screen layer behind the content, not in the scroll.
//
//  One backdrop for the whole app, behind the tab bar and every stack: the picture does
//  not scroll, does not belong to the hero, and is not drawn again by each page.
//

#if os(tvOS)
import SwiftUI
import CoreImage
import UIKit
import OSLog
import KinoPubLogging

private let backdropLog = Logger(subsystem: "com.soda.kinopub", category: "Backdrop")

/// What a page wants behind it.
public struct PageBackdrop: Equatable, Sendable {
  /// Same id, same picture: a change of palette alone animates in place instead of
  /// crossfading the whole backdrop.
  public var id: String
  /// Tried in order; the first that loads is the picture. Empty draws the palette alone.
  public var imageURLs: [URL]
  /// Art the page already has on screen or in cache — the poster of the card that opened
  /// it. Shown blurred the moment the page is in front, until the picture itself has
  /// loaded: opening a title never waits on the network with the previous title's
  /// picture still up (Sasha, 2026-11-21). Not part of the identity: it never decides
  /// whether the picture has to be loaded again.
  public var placeholderURLs: [URL]
  /// The picture's mean colours, top-leading → bottom-trailing. Drawn under the picture
  /// and on its own where there is none. Empty until a source supplies them.
  public var palette: [Color]

  public init(id: String, imageURLs: [URL], placeholderURLs: [URL] = [], palette: [Color] = []) {
    self.id = id
    self.imageURLs = imageURLs
    self.placeholderURLs = placeholderURLs
    self.palette = palette
  }
}

/// The frontmost page's backdrop, by **navigation state**, not by view lifecycle.
///
/// Whoever owns the paths (`TabsNavigationView`, the fixture root) says which page is in
/// front — `frontKey`, the key of the selected tab's top route, or nil for a page with no
/// picture. Pages publish what their picture is under that same key (`pageBackdrop`). The
/// stage draws the published backdrop of the front key; a front key nobody has published
/// yet keeps the old picture up until the page publishes (it does on appearing), so a push
/// crossfades picture to picture instead of through nothing.
///
/// Why not `onAppear` / `onDisappear`: on a pop the page underneath appears ~0.1 s after
/// Menu while the page leaving disappears ~0.5 s later, a stack's root never re-appears at
/// all, and `isPresented` drops when a page is *covered* and never fires on the way back.
/// The path changes on Select and on Menu, before any transition (Sasha, 2026-10-11).
@MainActor
@Observable
public final class PageBackdropStage {
  private var published: [String: PageBackdrop] = [:]
  /// Pages whose focus is below their hero, in their sections.
  private var inDetails: Set<String> = []
  public private(set) var frontKey: String?
  public private(set) var current: PageBackdrop?
  /// The front page is in its details: its picture is faded out.
  public private(set) var showsDetails = false
  /// Scrubbed backdrop blur for the below-fold, 0...1. Nil means the page is not
  /// driving it, and `showsDetails` fades the picture out instead.
  public private(set) var foldBlur: CGFloat?
  /// Whether each published backdrop's picture actually loaded. Missing while it is
  /// still being fetched.
  private var pictureLoaded: [String: Bool] = [:]

  public init() {}

  /// Whether the page under `key` has a picture behind it: true once one has loaded,
  /// false when every candidate failed or there were none, nil while still loading.
  /// What is drawn over the backdrop is forced dark only over a picture — with none,
  /// the page sits on the system background and follows the appearance.
  public func hasPicture(for key: String) -> Bool? {
    pictureLoaded[key]
  }

  func notePicture(_ loaded: Bool, for key: String) {
    guard pictureLoaded[key] != loaded else { return }
    pictureLoaded[key] = loaded
  }

  func setFront(_ key: String?) {
    guard key != frontKey else { return }
    backdropLog.debug("front \(key ?? "none", privacy: .public)")
    frontKey = key
    resolve()
  }

  func publish(_ backdrop: PageBackdrop) {
    guard published[backdrop.id] != backdrop else { return }
    published[backdrop.id] = backdrop
    resolve()
  }

  func setDetails(_ on: Bool, for key: String) {
    if on { inDetails.insert(key) } else { inDetails.remove(key) }
    resolve()
  }

  /// The season rail reports how far it has risen from the hero into the center.
  /// The picture stays up and a blur is scrubbed across it. Passing nil hands the
  /// picture back to the `showsDetails` fade.
  public func setFoldBlur(_ value: CGFloat?) {
    if foldBlur == nil, value == nil { return }
    if let value, let foldBlur, abs(value - foldBlur) < 0.008 { return }
    foldBlur = value
  }

  /// Keeps what the paths still hold; the rest is gone for good.
  func keepOnly(_ keys: Set<String>) {
    published = published.filter { keys.contains($0.key) }
    pictureLoaded = pictureLoaded.filter { keys.contains($0.key) }
    inDetails.formIntersection(keys)
  }

  private func resolve() {
    let details = frontKey.map(inDetails.contains) ?? false
    if details != showsDetails { showsDetails = details }
    let next: PageBackdrop?
    if let frontKey {
      // Not published yet: hold the current picture rather than flash to nothing.
      guard let backdrop = published[frontKey] else { return }
      next = backdrop
    } else {
      next = nil
    }
    if next != current {
      backdropLog.debug("show \(next?.id ?? "none", privacy: .public)")
      current = next
    }
  }
}

public extension EnvironmentValues {
  @Entry var pageBackdropStage: PageBackdropStage? = nil
}

public extension View {
  /// Installs the one backdrop. Put it at the root, around the tab view: it fills the
  /// screen and stays put while tabs switch and pages push, pop and scroll.
  ///
  /// - Parameters:
  ///   - front: the key of the page in front — the selected tab's top route — or nil
  ///     when that page has no picture. Changes the moment the path does.
  ///   - live: every key any path still holds, so a backdrop popped off for good is
  ///     forgotten.
  func pageBackdropStage(front: String?, live: Set<String>) -> some View {
    modifier(PageBackdropStageInstaller(front: front, live: live))
  }

  /// This page's picture, published under `backdrop.id` — which must be the key its
  /// route gives the stage's `front`. Drawn only while that route is in front.
  /// Without a stage above it (a sheet, a stack outside the tabs) the page draws the same
  /// backdrop itself, still behind its scroll rather than in it.
  func pageBackdrop(_ backdrop: PageBackdrop?) -> some View {
    modifier(PageBackdropPublisher(backdrop: backdrop))
  }

  /// The page under `key` has moved into its details (focus below the hero) or back. The
  /// backdrop fades its picture out while it is there, leaving the system background, and
  /// brings it back on the way up to the hero.
  func pageBackdropDetails(_ inDetails: Bool, key: String) -> some View {
    modifier(PageBackdropDetailsReporter(inDetails: inDetails, key: key))
  }
}

private struct PageBackdropStageInstaller: ViewModifier {
  let front: String?
  let live: Set<String>
  @State private var stage = PageBackdropStage()

  func body(content: Content) -> some View {
    content
      .background { PageBackdropHost(stage: stage) }
      .environment(\.pageBackdropStage, stage)
      .onChange(of: front, initial: true) { _, front in stage.setFront(front) }
      .onChange(of: live, initial: true) { _, live in stage.keepOnly(live) }
  }
}

private struct PageBackdropPublisher: ViewModifier {
  let backdrop: PageBackdrop?
  @Environment(\.pageBackdropStage) private var appStage
  /// Used only where no stage is installed above the page.
  @State private var ownStage = PageBackdropStage()

  func body(content: Content) -> some View {
    content
      .background {
        if appStage == nil {
          PageBackdropHost(stage: ownStage)
        }
      }
      .environment(\.pageBackdropStage, appStage ?? ownStage)
      .onChange(of: backdrop, initial: true) { _, backdrop in
        guard let backdrop else { return }
        if let appStage {
          appStage.publish(backdrop)
        } else {
          ownStage.publish(backdrop)
          ownStage.setFront(backdrop.id)
        }
      }
  }
}

private struct PageBackdropDetailsReporter: ViewModifier {
  let inDetails: Bool
  let key: String
  @Environment(\.pageBackdropStage) private var stage

  func body(content: Content) -> some View {
    content
      .onChange(of: inDetails, initial: true) { _, inDetails in
        stage?.setDetails(inDetails, for: key)
      }
  }
}

/// Draws the stage's current backdrop, full screen, never focusable, never in a scroll.
///
/// A new page's picture never waits behind the previous one (Sasha, 2026-11-21: the old
/// backdrop stayed up until the worker answered, ~5 s on a cold title, swapping together
/// with the logo). On a new id, at once: the picture itself when it is already decoded,
/// else a blurred copy of the art the page already has (the card's poster), else nothing
/// — the old picture is gone either way. The picture crossfades in when it has loaded.
///
/// Every picture also keeps a small blurred copy (`PageBackdropWash`), made once off the
/// main thread. The details sit on it instead of on an empty page (Rivulet's look), and it
/// costs one tiny bitmap stretched by the GPU — no live blur over the scroll.
struct PageBackdropHost: View {
  let stage: PageBackdropStage

  private struct Shown: Equatable {
    var backdrop: PageBackdrop
    /// The picture; nil while it loads, or when nothing loaded.
    var image: Image?
    /// Small blurred copy — of the picture once it is in, of the placeholder before.
    var wash: Image?
  }

  @State private var shown: Shown?
  @Environment(\.colorScheme) private var colorScheme

  /// From one title's picture to the next.
  static let crossfade = Animation.easeInOut(duration: 0.7)
  /// From nothing: slow, so opening a title eases the picture in under the push.
  static let fadeIn = Animation.easeInOut(duration: 1.0)
  /// Into the details and back.
  static let details = Animation.easeInOut(duration: 0.45)
  /// To nothing: quick, and started as the pop starts, so the picture is gone by the time
  /// the page underneath has focus.
  static let fadeOut = Animation.easeOut(duration: 0.35)
  /// Off the previous title onto the next one's placeholder: as quick as the push.
  static let handoff = Animation.easeOut(duration: 0.3)

  var body: some View {
    ZStack {
      if let shown {
        PageBackdropLayer(palette: shown.backdrop.palette,
                          image: shown.image,
                          wash: shown.wash,
                          inDetails: stage.foldBlur == nil && stage.showsDetails,
                          colorScheme: colorScheme)
          .id(shown.backdrop.id)
          .transition(.opacity)
      }
    }
    .animation(stage.foldBlur == nil ? Self.details : nil, value: stage.showsDetails)
    .overlay {
      FoldBlurOverlay(progress: stage.foldBlur ?? 0)
        .opacity(stage.foldBlur == nil ? 0 : 1)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
    .ignoresSafeArea()
    .allowsHitTesting(false)
    .accessibilityHidden(true)
    .task(id: stage.current) {
      await show(stage.current)
    }
  }

  private func show(_ next: PageBackdrop?) async {
    let interval = PerfSignpost.beginHeroBackdrop(id: next?.id ?? "none")
    defer { interval.end(next == nil ? "cleared" : "shown") }
    guard let next else {
      withAnimation(Self.fadeOut) { shown = nil }
      return
    }
    if let shown, shown.backdrop.id == next.id, shown.backdrop.imageURLs == next.imageURLs {
      withAnimation(Self.crossfade) { self.shown?.backdrop = next }
      return
    }
    let sameTitle = shown?.backdrop.id == next.id

    // Already decoded (the Home banner drew the same URL): straight to it.
    if let cached = Self.cachedPicture(of: next.imageURLs) {
      let wash = await PageBackdropWash.make(from: cached)
      guard !Task.isCancelled else { return }
      stage.notePicture(true, for: next.id)
      withAnimation(shown == nil ? Self.fadeIn : Self.crossfade) {
        shown = Shown(backdrop: next, image: Image(platformImage: cached), wash: wash.map(Image.init(platformImage:)))
      }
      return
    }

    if !sameTitle {
      // Never hold the previous title's picture: its placeholder, or nothing, now.
      let placeholder = Self.cachedPlaceholder(of: next.placeholderURLs)
      let wash = await placeholder.asyncMap { await PageBackdropWash.make(from: $0) } ?? nil
      guard !Task.isCancelled else { return }
      withAnimation(Self.handoff) {
        shown = Shown(backdrop: next, image: nil, wash: wash.map(Image.init(platformImage:)))
      }
      if wash == nil, !next.placeholderURLs.isEmpty {
        // Not in memory: from disk or the network, racing the picture — whichever is
        // first is drawn; the picture always wins once it is in.
        Task {
          guard let loaded = await Self.firstImage(of: next.placeholderURLs, id: next.id, logs: false),
                let wash = await PageBackdropWash.make(from: loaded),
                self.shown?.backdrop.id == next.id, self.shown?.image == nil, self.shown?.wash == nil
          else { return }
          withAnimation(Self.handoff) { self.shown?.wash = Image(platformImage: wash) }
        }
      }
    }

    let loaded = await Self.firstImage(of: next.imageURLs, id: next.id, logs: true)
    guard !Task.isCancelled else { return }
    stage.notePicture(loaded != nil, for: next.id)
    guard let loaded else {
      // Nothing loaded: the placeholder wash stays as the page's picture.
      if shown?.backdrop.id != next.id {
        withAnimation(Self.crossfade) { shown = Shown(backdrop: next, image: nil, wash: nil) }
      } else {
        shown?.backdrop = next
      }
      return
    }
    let wash = await PageBackdropWash.make(from: loaded)
    guard !Task.isCancelled else { return }
    withAnimation(shown?.image == nil && shown?.wash == nil ? Self.fadeIn : Self.crossfade) {
      shown = Shown(backdrop: next, image: Image(platformImage: loaded), wash: wash.map(Image.init(platformImage:)))
    }
  }

  /// The first candidate already decoded at full size in memory.
  private static func cachedPicture(of urls: [URL]) -> UIImage? {
    for url in urls {
      if let image = Artwork.cachedImage(for: url) { return image }
    }
    return nil
  }

  /// Any decoded size of a placeholder candidate — the card drew it at its own size.
  private static func cachedPlaceholder(of urls: [URL]) -> UIImage? {
    for url in urls {
      if let image = Artwork.anyCachedImage(for: url) { return image }
    }
    return nil
  }

  /// Wide → big → medium, the same chain `FallbackRemoteImage` walks, through the same
  /// `Artwork` cache — the card that opened the page has usually decoded it already.
  private static func firstImage(of urls: [URL], id: String, logs: Bool) async -> UIImage? {
    for (index, url) in urls.enumerated() {
      if Task.isCancelled { return nil }
      if let loaded = try? await Artwork.imageWithSource(for: url) {
        guard logs else { return loaded.image }
        Artwork.noteDisplayed(loaded.image, url: url, size: .zero)
        ArtworkLog.source("page.backdrop \(id)", id: nil, asked: url, answered: loaded.answered,
                          tier: loaded.tier, candidate: index, of: urls.count)
        return loaded.image
      }
    }
    if logs, !Task.isCancelled { ArtworkLog.exhausted("page.backdrop \(id)", id: nil, tried: urls) }
    return nil
  }
}

private extension Optional {
  func asyncMap<T>(_ transform: (Wrapped) async -> T) async -> T? {
    guard let self else { return nil }
    return await transform(self)
  }
}

/// A picture's blurred stand-in: shrunk to a few dozen pixels and blurred once, then
/// stretched over the screen by the GPU. Made off the main thread, cached per bitmap.
enum PageBackdropWash {
  /// Long side of the blurred bitmap. Stretched to 1920 pt it reads as a heavy blur.
  static let side: CGFloat = 64

  nonisolated(unsafe) private static let context = CIContext(options: [.useSoftwareRenderer: false])

  static func make(from image: UIImage) async -> UIImage? {
    guard let source = image.cgImage else { return nil }
    let result: CGImage? = await Task.detached(priority: .userInitiated) {
      Self.blurred(source)
    }.value
    return result.map { UIImage(cgImage: $0) }
  }

  nonisolated private static func blurred(_ source: CGImage) -> CGImage? {
    let width = CGFloat(source.width), height = CGFloat(source.height)
    guard width > 0, height > 0 else { return nil }
    let scale = side / max(width, height)
    let input = CIImage(cgImage: source)
      .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    let extent = input.extent.integral
    guard let blur = CIFilter(name: "CIGaussianBlur") else { return nil }
    blur.setValue(input.clampedToExtent(), forKey: kCIInputImageKey)
    blur.setValue(2.5, forKey: kCIInputRadiusKey)
    guard let output = blur.outputImage?.cropped(to: extent) else { return nil }
    return context.createCGImage(output, from: extent)
  }
}

/// Palette, picture, then the legibility scrim. The scrim is where text sits on every
/// page that has a backdrop — the whole bottom band and the leading edge — and is black
/// in any appearance: what is drawn over a backdrop is forced dark.
///
/// No picture and no palette — nothing loaded, or nothing to load — draws nothing at
/// all: the page sits on the system background, light or dark with the appearance,
/// instead of a black slab with a scrim over it (Sasha, 2026-10-25).
private struct PageBackdropLayer: View {
  let palette: [Color]
  let image: Image?
  let wash: Image?
  /// Focus is in the sections: the picture gives way to its blurred copy, tinted to the
  /// appearance, instead of fading out to an empty page (Sasha, 2026-11-21).
  var inDetails: Bool = false
  var colorScheme: ColorScheme = .dark

  var body: some View {
    if image == nil, wash == nil, palette.isEmpty {
      Color.clear
    } else {
      layers
    }
  }

  private var layers: some View {
    ZStack {
      Color.black

      if palette.count > 1 {
        LinearGradient(colors: palette, startPoint: .topLeading, endPoint: .bottomTrailing)
      } else if let only = palette.first {
        only
      }

      if let wash {
        Color.clear
          .overlay { wash.resizable().interpolation(.high).aspectRatio(contentMode: .fill) }
          .clipped()
      }

      if let image {
        // A clear frame of the screen's size with the picture laid over it: an
        // aspect-filled image left to size itself reports the overflow as its size.
        Color.clear
          .overlay { image.resizable().aspectRatio(contentMode: .fill) }
          .clipped()
          .opacity(inDetails && wash != nil ? 0 : 1)
      }

      // The Home hero's tuned shading, as on the Mac title page (Sasha, 2026-10-30): the
      // flat bands that were here read as a top and a bottom slab.
      HeroLegibilityTexture(tone: .black)
        .opacity(inDetails ? 0 : 1)

      // The details: one flat tint of the appearance over the blur, so the sections'
      // text (which follows the appearance there) reads in light and dark alike.
      (colorScheme == .dark ? Color.black.opacity(0.45) : Color.white.opacity(0.62))
        .opacity(inDetails ? 1 : 0)
    }
    .animation(PageBackdropHost.crossfade, value: palette)
  }
}

/// Scrubs a blur over the backdrop. `fractionComplete` is the intensity: alpha
/// on a blur view does not blur, it only fades an already-blurred snapshot.
private struct FoldBlurOverlay: UIViewRepresentable {
  var progress: CGFloat

  func makeUIView(context: Context) -> FoldBlurView {
    let view = FoldBlurView()
    view.isUserInteractionEnabled = false
    return view
  }

  func updateUIView(_ view: FoldBlurView, context: Context) {
    view.setProgress(progress)
  }
}

private final class FoldBlurView: UIVisualEffectView {
  private var animator: UIViewPropertyAnimator?

  func setProgress(_ progress: CGFloat) {
    let shown = progress > 0.01
    isHidden = !shown
    guard shown else { return }
    animatorIfNeeded().fractionComplete = min(0.999, max(0.001, progress))
  }

  private func animatorIfNeeded() -> UIViewPropertyAnimator {
    if let animator, animator.state == .active { return animator }
    animator?.stopAnimation(true)
    let animator = UIViewPropertyAnimator(duration: 1, curve: .linear) { [weak self] in
      self?.effect = UIBlurEffect(style: .regular)
    }
    animator.pausesOnCompletion = true
    animator.startAnimation()
    animator.pauseAnimation()
    self.animator = animator
    return animator
  }

  deinit {
    animator?.stopAnimation(true)
  }
}

#if DEBUG
#Preview("Palette only") {
  PageBackdropLayer(palette: [Color(red: 0.32, green: 0.22, blue: 0.14),
                              Color(red: 0.08, green: 0.10, blue: 0.16)],
                    image: nil, wash: nil)
}
#endif
#endif
