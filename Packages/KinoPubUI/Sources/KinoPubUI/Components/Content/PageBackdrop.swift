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
import OSLog

private let backdropLog = Logger(subsystem: "com.soda.kinopub", category: "Backdrop")

/// What a page wants behind it.
public struct PageBackdrop: Equatable, Sendable {
  /// Same id, same picture: a change of palette alone animates in place instead of
  /// crossfading the whole backdrop.
  public var id: String
  /// Tried in order; the first that loads is the picture. Empty draws the palette alone.
  public var imageURLs: [URL]
  /// The picture's mean colours, top-leading → bottom-trailing. Drawn under the picture
  /// and on its own where there is none. Empty until a source supplies them.
  public var palette: [Color]

  public init(id: String, imageURLs: [URL], palette: [Color] = []) {
    self.id = id
    self.imageURLs = imageURLs
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
/// A new picture is decoded before it is shown, so the crossfade goes from one picture
/// to the next rather than through an empty frame.
struct PageBackdropHost: View {
  let stage: PageBackdropStage

  private struct Shown: Equatable {
    var backdrop: PageBackdrop
    var image: Image?
  }

  @State private var shown: Shown?

  /// From one title's picture to the next.
  static let crossfade = Animation.easeInOut(duration: 0.7)
  /// From nothing: slow, so opening a title eases the picture in under the push.
  static let fadeIn = Animation.easeInOut(duration: 1.0)
  /// Into the details and back.
  static let details = Animation.easeInOut(duration: 0.45)
  /// To nothing: quick, and started as the pop starts, so the picture is gone by the time
  /// the page underneath has focus.
  static let fadeOut = Animation.easeOut(duration: 0.35)

  var body: some View {
    ZStack {
      if let shown {
        PageBackdropLayer(palette: shown.backdrop.palette, image: shown.image)
          .id(shown.backdrop.id)
          .transition(.opacity)
      }
    }
    // Details: the picture goes away and the sections sit on the system's own background,
    // light in the light appearance and dark in the dark one. A material over the picture
    // was tried first: over dark art and the scrim, the light one read as dirty grey
    // (Sasha, 2026-10-11). The picture is the hero's alone.
    .opacity(stage.showsDetails ? 0 : 1)
    .animation(Self.details, value: stage.showsDetails)
    .ignoresSafeArea()
    .allowsHitTesting(false)
    .accessibilityHidden(true)
    .task(id: stage.current) {
      await show(stage.current)
    }
  }

  private func show(_ next: PageBackdrop?) async {
    guard let next else {
      withAnimation(Self.fadeOut) { shown = nil }
      return
    }
    if let shown, shown.backdrop.id == next.id, shown.backdrop.imageURLs == next.imageURLs {
      withAnimation(Self.crossfade) { self.shown?.backdrop = next }
      return
    }
    let image = await Self.firstImage(of: next.imageURLs, id: next.id)
    guard !Task.isCancelled else { return }
    stage.notePicture(image != nil, for: next.id)
    withAnimation(shown == nil ? Self.fadeIn : Self.crossfade) {
      shown = Shown(backdrop: next, image: image)
    }
  }

  /// Wide → big → medium, the same chain `FallbackRemoteImage` walks, through the same
  /// `Artwork` cache — the card that opened the page has usually decoded it already.
  private static func firstImage(of urls: [URL], id: String) async -> Image? {
    for (index, url) in urls.enumerated() {
      if Task.isCancelled { return nil }
      if let loaded = try? await Artwork.imageWithSource(for: url) {
#if os(tvOS)
        ArtworkLog.source("page.backdrop \(id)", id: nil, asked: url, answered: loaded.answered,
                          tier: loaded.tier, candidate: index, of: urls.count)
#endif
        return Image(platformImage: loaded.image)
      }
    }
#if os(tvOS)
    if !Task.isCancelled { ArtworkLog.exhausted("page.backdrop \(id)", id: nil, tried: urls) }
#endif
    return nil
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

  var body: some View {
    if image == nil, palette.isEmpty {
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

      if let image {
        // A clear frame of the screen's size with the picture laid over it: an
        // aspect-filled image left to size itself reports the overflow as its size.
        Color.clear
          .overlay { image.resizable().aspectRatio(contentMode: .fill) }
          .clipped()
      }

      BackdropScrim()
    }
    .animation(PageBackdropHost.crossfade, value: palette)
  }
}

#if DEBUG
#Preview("Palette only") {
  PageBackdropLayer(palette: [Color(red: 0.32, green: 0.22, blue: 0.14),
                              Color(red: 0.08, green: 0.10, blue: 0.16)],
                    image: nil)
}
#endif
#endif
