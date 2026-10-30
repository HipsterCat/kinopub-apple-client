#if !os(tvOS)
//
//  HomeHeroCarousel.swift
//  KinoPubUI
//
//  The Home hero on iOS, iPadOS and macOS: the tvOS carousel (`TVPageHero.swift`) in
//  SwiftUI — the same titles, logo, line, plot, Play / Bookmarks / Details / Next and
//  the same 8 s turn — laid out the way the Apple TV app lays its hero out on each
//  device. Wide (iPad, Mac): the words low on the leading margin, as on the TV. Phone:
//  one centred column over the foot of the picture.
//
//  The words and buttons are the pages of a paging `ScrollView` and slide under a
//  finger; the pictures do not slide with them. They are one backdrop behind the pages
//  that cross-fades from title to title with the scroll, each picture drifting a little
//  the way the words go (`HeroBackdrop`) — the Apple TV app's hero, one continuous
//  background rather than a strip of photos (Sasha, 2026-10-30). The pages are laid out
//  three laps long so a turn past the last title runs on into the first; once a turn
//  settles on an outer lap the view is put back on the same title of the middle one,
//  which looks the same (`Slot`).
//
//  The picture is forced dark, like everything the Apple TV app draws over a title's
//  picture, and ends on a hard edge: the page under it keeps the system appearance.
//

import SwiftUI

public struct HomeHeroCarousel: View {
  private let hero: HomeHero
  private let size: CGSize
  private let topBleed: CGFloat
  private let sideInset: CGFloat
  private let isCompact: Bool
  private let onPlay: (MediaCard) -> Void
  private let onDetails: (MediaCard) -> Void
  private let bookmarkEntries: ((MediaCard) -> [MediaCardContextEntry])?
  private let isActive: Bool
  @Binding private var shownIndex: Int

  /// One page: which title, on which lap of the three.
  struct Slot: Hashable, Sendable {
    var lap: Int
    var index: Int
  }

  /// The page the hero rests on — the source of truth; the scroll view is told.
  @State private var current: Slot
  @State private var scroll: ScrollPosition
  /// The scroll in pages, written every frame and read only by the backdrop, so a
  /// drag repaints the pictures and nothing else.
  @State private var pager = HeroPager()
  @State private var isPresented = false
  @State private var isVisibleInPage = true
  @State private var isScrolling = false
  @State private var isMenuOpen = false
  @State private var isHovered = false
  /// A turn the code animates is on its way; the scroll may report no phase for it.
  @State private var isTurning = false
  @Environment(\.scenePhase) private var scenePhase

  /// - Parameters:
  ///   - size: the hero's frame — the page's width, and the height the page gives it.
  ///   - topBleed: how far the picture runs on above the frame, under the navigation
  ///     bar or window toolbar (their safe-area inset). The words stay inside the frame.
  ///   - sideInset: the page's leading margin, so the words start where the rows do.
  ///   - isCompact: the phone's centred column instead of the leading one.
  ///   - isActive: the page is the one on screen — its tab selected and nothing pushed
  ///     over it. A Mac keeps the page under a pushed one alive and "appeared".
  ///   - shownIndex: the title on screen, owned by the page, so back from a pushed page
  ///     the hero is on the title it was left on even if this view was rebuilt.
  public init(hero: HomeHero,
              size: CGSize,
              topBleed: CGFloat = 0,
              sideInset: CGFloat,
              isCompact: Bool,
              onPlay: @escaping (MediaCard) -> Void,
              onDetails: @escaping (MediaCard) -> Void,
              bookmarkEntries: ((MediaCard) -> [MediaCardContextEntry])? = nil,
              isActive: Bool = true,
              shownIndex: Binding<Int> = .constant(0)) {
    self.hero = hero
    self.size = size
    self.topBleed = topBleed
    self.sideInset = sideInset
    self.isCompact = isCompact
    self.onPlay = onPlay
    self.onDetails = onDetails
    self.bookmarkEntries = bookmarkEntries
    self.isActive = isActive
    _shownIndex = shownIndex
    let start = shownIndex.wrappedValue
    let slot = Slot(lap: 0, index: hero.features.indices.contains(start) ? start : 0)
    _current = State(initialValue: slot)
    _scroll = State(initialValue: ScrollPosition(id: slot))
  }

  /// The hero's height under the bars for a page `width` wide on a `screen` tall
  /// screen, the bars' `topBleed` above it. Wide (iPad, Mac): a 16:9 picture as long
  /// as it leaves a fifth of the window. Phone: a 16:10 still under the bars and room
  /// under it for the words, at most 70% of the screen (Sasha, 2026-10-30).
  public static func height(width: CGFloat, topBleed: CGFloat, screen: CGFloat,
                            isCompact: Bool) -> CGFloat {
    let picture: CGFloat = isCompact
      ? min(topBleed + stillHeight(width: width) * Metrics.compactStillsTall, screen * 0.7)
      : min(width * 9 / 16 + topBleed, screen * 0.8)
    return max(picture - topBleed, 0).rounded()
  }

  /// The phone's still: 16:10 of the width.
  static func stillHeight(width: CGFloat) -> CGFloat { (width * 10 / 16).rounded() }

  private var features: [HomeHeroFeature] { hero.features }

  private var slots: [Slot] {
    let laps = features.count > 1 ? [-1, 0, 1] : [0]
    return laps.flatMap { lap in features.indices.map { Slot(lap: lap, index: $0) } }
  }

  private var currentIndex: Int {
    min(current.index, max(features.count - 1, 0))
  }

  /// The tvOS rule: titles turn on their own only while someone can see the hero — not
  /// under a pushed page, another tab or the player, not scrolled away, not while a
  /// finger is turning it or its Bookmarks menu is open. Not paused under the pointer:
  /// on a Mac the hero is most of the window, and the pointer is nearly always on it.
  private var advances: Bool {
    features.count > 1 && isActive && isPresented && isVisibleInPage && scenePhase == .active
      && !isScrolling && !isMenuOpen
  }

  public var body: some View {
    ScrollView(.horizontal) {
      LazyHStack(spacing: 0) {
        ForEach(slots, id: \.self) { slot in
          page(features[slot.index])
            .frame(width: size.width, height: size.height)
        }
      }
      .scrollTargetLayout()
    }
    .scrollIndicators(.hidden)
    .scrollTargetBehavior(.paging)
    .scrollPosition($scroll)
    .onScrollGeometryChange(for: CGFloat.self) { geometry in
      let width = geometry.containerSize.width
      return width > 0 ? geometry.contentOffset.x / width : 0
    } action: { _, page in
      pager.page = page
      // At rest between two pages — a burst of window resizes outran the re-snap on
      // the width change and left it there for good: back onto the current page.
      if !isScrolling, !isTurning, abs(page - page.rounded()) > 0.001 {
        DispatchQueue.main.async { snap() }
      }
    }
    .onScrollPhaseChange { _, phase in
      isScrolling = phase != .idle
      if phase == .idle { settle() }
    }
    .frame(width: size.width, height: size.height)
    // The pictures run up under the bars, past the pager's own frame.
    .background(alignment: .bottom) {
      HeroBackdrop(features: features, slots: slots, pager: pager,
                   width: size.width, height: size.height + topBleed, topBleed: topBleed,
                   isCompact: isCompact)
        .allowsHitTesting(false)
    }
    .overlay(alignment: .bottom) {
      if features.count > 1 {
        HomeHeroPageDots(count: features.count,
                         current: currentIndex,
                         advances: advances,
                         dwell: Self.dwell,
                         onAdvance: { step(1) },
                         onSelect: { go(to: $0) })
          .padding(.bottom, Metrics.dotsBottom)
      }
    }
#if os(macOS) || os(iOS)
    .overlay { pagingArrows }
    .onHover { isHovered = $0 }
#endif
    .environment(\.colorScheme, .dark)
    .onScrollVisibilityChange(threshold: 0.5) { isVisibleInPage = $0 }
    .onAppear {
      isPresented = true
      snap()
    }
    .onDisappear { isPresented = false }
    // A window resized, or a page pushed and popped, can leave the pager between two
    // pages: the old offset in a new page width, or a turn cut off on its way.
    .onChange(of: size.width) { move(to: current, animated: false) }
    .onChange(of: isActive) { move(to: current, animated: false) }
    .onChange(of: current.index) { _, index in
      if index != shownIndex { shownIndex = index }
    }
    .onChange(of: features.count) { _, count in
      // The banner set is topped up or trimmed: keep a title that still exists.
      if current.index >= count { move(to: Slot(lap: 0, index: 0), animated: false) }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("kinopub.hero")
  }

  /// How long one title stays before the next — tvOS's `TVPageHeroCarousel.dwell`.
  static let dwell: TimeInterval = 8

  // MARK: Paging

  /// One title over: +1 forward, -1 back, both wrapping onto the next lap.
  private func step(_ delta: Int) {
    guard features.count > 1 else { return }
    var next = Slot(lap: current.lap, index: current.index + delta)
    if next.index >= features.count {
      next = Slot(lap: current.lap + 1, index: 0)
    } else if next.index < 0 {
      next = Slot(lap: current.lap - 1, index: features.count - 1)
    }
    guard slots.contains(next) else { return }
    move(to: next, animated: true)
  }

  /// A dot clicked: that title, on the lap the hero is on.
  private func go(to index: Int) {
    guard features.indices.contains(index), index != current.index else { return }
    move(to: Slot(lap: current.lap, index: index), animated: true)
  }

  private func move(to slot: Slot, animated: Bool) {
    current = slot
    if animated {
      isTurning = true
      withAnimation(.smooth(duration: 0.6)) {
        scroll.scrollTo(id: slot)
      } completion: {
        isTurning = false
        // A turn the code makes may not report a scroll phase of its own.
        settle()
      }
    } else {
      var transaction = Transaction()
      transaction.disablesAnimations = true
      withTransaction(transaction) { scroll.scrollTo(id: slot) }
    }
  }

  /// After a drag or a turn: the page the scroll stopped on becomes the current one,
  /// and one on an outer lap goes back to the same title in the middle one with nothing
  /// animated — the two pages look the same, so it does not show.
  private func settle() {
    let pages = slots
    if size.width > 0, !pages.isEmpty {
      let nearest = min(max(Int(pager.page.rounded()), 0), pages.count - 1)
      current = pages[nearest]
    }
    if current.lap != 0 {
      move(to: Slot(lap: 0, index: current.index), animated: false)
    } else {
      snap()
    }
  }

  /// Puts the scroll back exactly on the current page when it is not there.
  private func snap() {
    guard !isScrolling, !isTurning, let at = slots.firstIndex(of: current) else { return }
    if abs(pager.page - CGFloat(at)) > 0.001 {
      move(to: current, animated: false)
    }
  }

  // MARK: Page

  /// The words over the pictures, which are the backdrop's. A tap anywhere that is not
  /// a button opens the title, as in the Apple TV app.
  private func page(_ feature: HomeHeroFeature) -> some View {
    ZStack(alignment: isCompact ? .bottom : .bottomLeading) {
      Color.clear
      if feature.card.id > 0 {
        words(feature)
          .padding(.horizontal, sideInset)
          .padding(.bottom, features.count > 1 ? Metrics.dotsReserve : Metrics.bottomInset)
      }
    }
    .frame(width: size.width, height: size.height)
    .contentShape(Rectangle())
    .onTapGesture {
      guard feature.card.id > 0 else { return }
      onDetails(feature.card)
    }
  }

#if os(macOS) || os(iOS)
  /// Previous / next at the sides while the pointer is over a wide hero (Mac, iPad with
  /// a pointer), as the Apple TV app has them. There is no system control for these
  /// (none in SwiftUI or AppKit, checked in the 27.2 SDKs): glass circles of the
  /// system's own button style.
  @ViewBuilder
  private var pagingArrows: some View {
    if !isCompact, features.count > 1 {
      HStack {
        arrow("chevron.left", label: hero.labels.previous) { step(-1) }
        Spacer(minLength: 0)
        arrow("chevron.right", label: hero.labels.next) { step(1) }
      }
      .padding(.horizontal)
      .opacity(isHovered ? 1 : 0)
      .animation(.easeInOut(duration: 0.2), value: isHovered)
    }
  }

  private func arrow(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: symbol)
        .font(.title2.weight(.semibold))
        .frame(height: 44)
    }
    .buttonStyle(.glass)
    .buttonBorderShape(.capsule)
    .controlSize(.large)
    .accessibilityLabel(Text(label))
    .help(label)
  }
#endif

  // MARK: Words

  private func words(_ feature: HomeHeroFeature) -> some View {
    let card = feature.card
    let alignment: HorizontalAlignment = isCompact ? .center : .leading
    return VStack(alignment: alignment, spacing: Metrics.wordSpacing) {
      VStack(alignment: alignment, spacing: Metrics.wordSpacing) {
        mark(feature)
          .padding(.bottom, Metrics.markGap)
        // No synopsis for now: kino.pub's plot is long and its first sentences are
        // rarely a tagline. Back once there is a quick source of a short one (Sasha,
        // 2026-10-30); two genres say more in the meantime.
        metaLine(card)
      }
      .multilineTextAlignment(isCompact ? .center : .leading)
      .shadow(color: .black.opacity(0.32), radius: 7, y: 2)
      .accessibilityElement(children: .combine)

      buttons(feature)
        .padding(.top, Metrics.buttonsGap)
    }
    .frame(maxWidth: .infinity, alignment: isCompact ? .center : .leading)
  }

  /// The title logo in the tvOS hero's budget (28% × 8.5% of the width on a wide page);
  /// the name in its place after a confirmed miss. Its slot keeps its height while the
  /// logo loads, so the words under it do not jump.
  private func mark(_ feature: HomeHeroFeature) -> some View {
    let maxWidth = (size.width * (isCompact ? 0.7 : 0.28)).rounded()
    let maxHeight = (size.width * (isCompact ? 0.26 : 0.085)).rounded()
    return TitleLogoSlot(resolution: feature.logo, maxWidth: maxWidth, maxHeight: maxHeight,
                         alignment: isCompact ? .center : .leading) {
      Text(feature.card.title)
        .font(TypeScale.heroTitle)
        .foregroundStyle(.white)
        .lineLimit(2)
        .multilineTextAlignment(isCompact ? .center : .leading)
    }
    .id(feature.card.id)
    .frame(minHeight: maxHeight, alignment: isCompact ? .bottom : .bottomLeading)
  }

  /// Scores, then two genres · years · country · seasons — the tvOS banner's line
  /// (`HomeHeroText.metaParts`). One line: when it does not fit, the last parts go first.
  private func metaLine(_ card: MediaCard) -> some View {
    let parts = HomeHeroText.metaParts(for: card, genres: 2)
    return ViewThatFits(in: .horizontal) {
      ForEach((0...parts.count).reversed(), id: \.self) { count in
        HStack(spacing: MediaScoresView.groupSpacing) {
          if card.scores.hasDisplayableScore {
            MediaScoresView(card.scores, showsVotes: false, bannerLine: true)
          }
          ForEach(parts.prefix(count), id: \.self) { part in
            Text(part)
          }
        }
        .fixedSize()
      }
    }
    .font(TypeScale.heroSecondary)
    .foregroundStyle(.primary.opacity(0.88))
    .lineLimit(1)
  }

  // MARK: Buttons

  /// Play, Bookmarks, Details, Next — tvOS's row. The phone keeps Play and Bookmarks,
  /// as the Apple TV app's phone hero does: a swipe turns the page and a tap on the
  /// picture opens the title. A wide row that does not fit drops Next, then Details.
  @ViewBuilder
  private func buttons(_ feature: HomeHeroFeature) -> some View {
    if isCompact {
      buttonRow(feature, details: false, next: false)
    } else {
      ViewThatFits(in: .horizontal) {
        buttonRow(feature, details: true, next: true)
        buttonRow(feature, details: true, next: false)
        buttonRow(feature, details: false, next: false)
      }
    }
  }

  private func buttonRow(_ feature: HomeHeroFeature, details: Bool, next: Bool) -> some View {
    HStack(spacing: MediaActionMetrics.rowSpacing) {
      playButton(feature)
      if bookmarkEntries != nil {
        bookmarkMenu(feature)
      }
      if details {
        MediaActionButton(detailsAppearance) { onDetails(feature.card) }
      }
      if next, features.count > 1 {
        MediaActionButton(nextAppearance) { step(1) }
      }
    }
    .fixedSize()
  }

  /// What the detail page's Play says for this title (`MediaActionCatalog.play`, laid
  /// over this device's positions); plain Play until its details are in.
  private func playButton(_ feature: HomeHeroFeature) -> some View {
    let appearance = feature.play ?? MediaActionAppearance(
      id: .play,
      chrome: .playPill,
      systemImage: "play.fill",
      title: hero.labels.play,
      accessibilityLabel: hero.labels.play
    )
    return MediaActionButton(appearance) { onPlay(feature.card) }
      .accessibilityIdentifier("kinopub.hero.play")
  }

  /// The detail page's Bookmarks menu: the folders checkmarked under a heading, the
  /// empty line when there are none, then New Folder.
  private func bookmarkMenu(_ feature: HomeHeroFeature) -> some View {
    let appearance = MediaActionCatalog.bookmark(for: MediaActionContext(
      playback: .play(season: nil, episode: nil),
      isSeries: feature.card.isSeries,
      isBookmarked: feature.isBookmarked
    ))
    return Menu {
      let menu = bookmarkFolders(for: feature.card)
      Section {
        if menu.folders.isEmpty {
          Text(hero.labels.noBookmarkFolders)
        } else {
          ForEach(menu.folders) { folder in
            Toggle(isOn: Binding(get: { folder.isOn }, set: { _ in folder.handler() })) {
              Text(folder.title)
            }
          }
        }
      } header: {
        Text(hero.labels.bookmark)
      }
      .onAppear { isMenuOpen = true }
      .onDisappear { isMenuOpen = false }
      ForEach(menu.footer) { item in
        Button(action: item.handler) {
          Label(item.title, systemImage: item.systemImage)
        }
      }
    } label: {
      MediaActionLabel(appearance)
    }
#if !os(macOS)
    .menuActionDismissBehavior(.disabled)
#endif
    .mediaActionStyle(appearance)
    .accessibilityLabel(Text(hero.labels.bookmark))
    .accessibilityIdentifier("kinopub.hero.bookmark")
  }

  private func bookmarkFolders(for card: MediaCard)
    -> (folders: [MediaCardContextAction], footer: [MediaCardContextAction]) {
    for entry in bookmarkEntries?(card) ?? [] {
      if case .submenu(_, _, _, let children, let footer) = entry {
        return (children, footer)
      }
    }
    return ([], [])
  }

  private var detailsAppearance: MediaActionAppearance {
    MediaActionAppearance(id: .more, chrome: .pill, systemImage: "",
                          title: hero.labels.details, accessibilityLabel: hero.labels.details)
  }

  private var nextAppearance: MediaActionAppearance {
    MediaActionAppearance(id: .more, chrome: .circle, systemImage: "chevron.right",
                          accessibilityLabel: hero.labels.next)
  }

  // MARK: Metrics

  private enum Metrics {
    static let wordSpacing: CGFloat = 8
    /// Under the logo, a little more than between the lines: tvOS's 24 against 14.
    static let markGap: CGFloat = 6
    static let buttonsGap: CGFloat = 12
    /// The phone hero's height under the bars, in 16:10 stills: the still, and under it
    /// the part of the words that does not sit on the picture.
    static let compactStillsTall: CGFloat = 1.6
    static let bottomInset: CGFloat = 28
    /// The dots' own band under the buttons.
    static let dotsBottom: CGFloat = 12
    static let dotsReserve: CGFloat = 48
  }
}

// MARK: - Backdrop

/// How far the pager has scrolled, in pages (1.5 = halfway from the second page to the
/// third). Its own object so only the backdrop, which reads it, redraws per frame.
@Observable
final class HeroPager {
  var page: CGFloat = 0
}

/// Every title's picture stacked, the one under the pager opaque and the next fading in
/// over it as the scroll goes, each drifting a fraction of the page the way the words
/// go. All of them stay loaded (six at most), so a turn never waits for a picture.
private struct HeroBackdrop: View {
  let features: [HomeHeroFeature]
  let slots: [HomeHeroCarousel.Slot]
  let pager: HeroPager
  let width: CGFloat
  let height: CGFloat
  let topBleed: CGFloat
  let isCompact: Bool

  /// How far a picture drifts against a whole page of scroll.
  private static let drift: CGFloat = 0.12

  /// Each picture is wider than the hero by its drift on both sides, so a drifting one
  /// never shows its edge (a narrower layer left seams and a white strip mid-turn).
  private var pictureWidth: CGFloat { (width * (1 + 2 * Self.drift)).rounded() }

  var body: some View {
    let position = min(max(pager.page, 0), CGFloat(max(slots.count - 1, 0)))
    let base = Int(position.rounded(.down))
    let fraction = position - CGFloat(base)
    let from = slots.indices.contains(base) ? slots[base].index : 0
    let to = slots.indices.contains(base + 1) ? slots[base + 1].index : from
    ZStack(alignment: .top) {
      Color.black
      ForEach(features.indices, id: \.self) { index in
        let opacity: CGFloat = index == from ? 1 : (index == to ? fraction : 0)
        let shift: CGFloat = index == from ? -fraction : (index == to ? 1 - fraction : 0)
        picture(features[index])
          .offset(x: shift * width * Self.drift)
          // Drawn over the outgoing one as it comes in.
          .zIndex(index == to && to != from ? 1 : 0)
          .opacity(opacity)
      }
      scrim
    }
    .frame(width: width, height: height)
    .clipped()
  }

  /// The picture from the top of the screen. Cropped, it keeps its top — heads and
  /// skies, not the middle. On a phone the 16:10 still starts under the bars, and the
  /// system's background extension carries it on above, under the status bar, and
  /// below. That whole layer is blurred into glass, and the sharp still lies over it
  /// fading out toward both edges, so it melts into the glass instead of stopping on a
  /// line (Sasha, 2026-10-30).
  @ViewBuilder
  private func picture(_ feature: HomeHeroFeature) -> some View {
    let wide = pictureWidth
#if os(iOS)
    if isCompact {
      let still = HomeHeroCarousel.stillHeight(width: width)
      let below = max(height - topBleed - still, 0)
      ZStack(alignment: .top) {
        FallbackRemoteImage(urls: feature.backdropCandidates, contentMode: .fill)
          .frame(width: wide, height: still)
          .clipped()
          .backgroundExtensionEffect()
          .safeAreaPadding(.top, topBleed)
          .safeAreaPadding(.bottom, below)
          .blur(radius: width * 0.06, opaque: true)
        FallbackRemoteImage(urls: feature.backdropCandidates, contentMode: .fill)
          .frame(width: wide, height: still)
          .clipped()
          .mask {
            LinearGradient(stops: [
              .init(color: .clear, location: 0),
              .init(color: .black, location: 0.22),
              .init(color: .black, location: 0.55),
              .init(color: .clear, location: 1)
            ], startPoint: .top, endPoint: .bottom)
          }
          .padding(.top, topBleed)
      }
      .frame(width: wide, height: height, alignment: .top)
    } else {
      croppedPicture(feature, width: wide)
    }
#else
    croppedPicture(feature, width: wide)
#endif
  }

  private func croppedPicture(_ feature: HomeHeroFeature, width: CGFloat) -> some View {
    FallbackRemoteImage(urls: feature.backdropCandidates, contentMode: .fill)
      .frame(width: width, height: height, alignment: .top)
      .clipped()
  }

  /// Wide: the tvOS hero's own legibility texture (`HeroBannerOverlay`) — the leading
  /// edge and the foot shaded under the words. Phone: the words are centred, so the
  /// shade is the foot alone, the way the Apple TV app's phone hero has it.
  @ViewBuilder
  private var scrim: some View {
    if isCompact {
      LinearGradient(stops: [
        .init(color: .black.opacity(0), location: 0.38),
        .init(color: .black.opacity(0.45), location: 0.64),
        .init(color: .black.opacity(0.85), location: 1)
      ], startPoint: .top, endPoint: .bottom)
    } else {
      HeroLegibilityTexture(tone: .black)
    }
  }
}

// MARK: - Paging dots

/// The paging dots with the running title's progress in them, the way the Apple TV app
/// draws them. They are also the clock: `onAdvance` when the title's time is up; a dot
/// clicked or tapped is `onSelect`.
///
/// iOS: the system control — `UIPageControl` with `UIPageControlTimerProgress`, what
/// the tvOS hero uses. macOS has no page control at all (no AppKit class, and SwiftUI's
/// page style is unavailable there, checked in the 27.2 SDK): the same control drawn —
/// the dots' size and spacing, the current one a capsule the title's time fills, each
/// dot a button.
struct HomeHeroPageDots: View {
  let count: Int
  let current: Int
  let advances: Bool
  let dwell: TimeInterval
  let onAdvance: () -> Void
  let onSelect: (Int) -> Void

  var body: some View {
#if os(iOS)
    SystemPageDots(count: count, current: current, advances: advances,
                   dwell: dwell, onAdvance: onAdvance, onSelect: onSelect)
      .fixedSize()
#else
    DrawnPageDots(count: count, current: current, advances: advances,
                  dwell: dwell, onAdvance: onAdvance, onSelect: onSelect)
#endif
  }
}

#if os(iOS)
private struct SystemPageDots: UIViewRepresentable {
  let count: Int
  let current: Int
  let advances: Bool
  let dwell: TimeInterval
  let onAdvance: () -> Void
  let onSelect: (Int) -> Void

  func makeCoordinator() -> Coordinator { Coordinator() }

  func makeUIView(context: Context) -> UIPageControl {
    let control = UIPageControl()
    control.hidesForSinglePage = true
    control.backgroundStyle = .minimal
    control.overrideUserInterfaceStyle = .dark
    control.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)),
                      for: .valueChanged)
    let timer = UIPageControlTimerProgress(preferredDuration: dwell)
    // Past the last page the timer asks for the first one instead of stopping there.
    timer.resetsToInitialPageAfterEnd = true
    timer.delegate = context.coordinator
    control.progress = timer
    return control
  }

  func updateUIView(_ control: UIPageControl, context: Context) {
    context.coordinator.onAdvance = onAdvance
    context.coordinator.onSelect = onSelect
    guard let timer = control.progress as? UIPageControlTimerProgress else { return }
    if control.numberOfPages != count { control.numberOfPages = count }
    if control.currentPage != current {
      control.currentPage = current
      // A new title gets its whole dwell, whoever turned the page.
      timer.currentProgress = 0
    }
    if advances != context.coordinator.advances {
      context.coordinator.advances = advances
      if advances {
        // Back in view, the title on it starts over, as on the TV.
        timer.currentProgress = 0
        timer.resumeTimer()
      } else {
        timer.pauseTimer()
      }
    }
  }

  final class Coordinator: NSObject, UIPageControlTimerProgressDelegate {
    var onAdvance: () -> Void = {}
    var onSelect: (Int) -> Void = { _ in }
    var advances = false

    /// The control would turn its own page; the carousel turns it instead, and the dots
    /// follow the carousel.
    func pageControlTimerProgress(_ progress: UIPageControlTimerProgress,
                                  shouldAdvanceToPage page: Int) -> Bool {
      onAdvance()
      return false
    }

    /// A tap or scrub on the dots: the carousel goes there, and sets the dots back.
    @objc func changed(_ control: UIPageControl) {
      onSelect(control.currentPage)
    }
  }
}
#else
private struct DrawnPageDots: View {
  let count: Int
  let current: Int
  let advances: Bool
  let dwell: TimeInterval
  let onAdvance: () -> Void
  let onSelect: (Int) -> Void

  /// UIPageControl's measures: an 8 pt dot, 8 pt apart, the running one three dots long.
  @ScaledMetric(relativeTo: .body) private var dot: CGFloat = 8
  @State private var progress: CGFloat = 0

  private struct Run: Equatable {
    let current: Int
    let advances: Bool
  }

  var body: some View {
    HStack(spacing: 0) {
      ForEach(0..<count, id: \.self) { index in
        Button { onSelect(index) } label: {
          indicator(index)
            .padding(.horizontal, dot / 2)
            .padding(.vertical, dot)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("\(index + 1)"))
        .accessibilityAddTraits(index == current ? .isSelected : [])
      }
    }
    .animation(.easeInOut(duration: 0.25), value: current)
    .task(id: Run(current: current, advances: advances)) {
      var reset = Transaction()
      reset.disablesAnimations = true
      withTransaction(reset) { progress = 0 }
      guard advances else { return }
      withAnimation(.linear(duration: dwell)) { progress = 1 }
      try? await Task.sleep(for: .seconds(dwell))
      guard !Task.isCancelled else { return }
      onAdvance()
    }
  }

  @ViewBuilder
  private func indicator(_ index: Int) -> some View {
    if index == current {
      Capsule()
        .fill(.white.opacity(advances ? 0.35 : 1))
        .overlay(alignment: .leading) {
          if advances {
            Capsule()
              .fill(.white)
              .frame(width: max(dot, dot * 3 * progress))
          }
        }
        .frame(width: dot * 3, height: dot)
    } else {
      Circle()
        .fill(.white.opacity(0.35))
        .frame(width: dot, height: dot)
    }
  }
}
#endif

#Preview("Home hero") {
  HomeHeroCarousel(
    hero: HomeHero(
      features: [
        HomeHeroFeature(card: MediaCard(
          id: 1,
          posterURL: "https://m.staticpop.net/poster/item/big/100582.jpg",
          title: "Паук-Нуар",
          imdbRating: 7.8,
          kinopoiskRating: 7.5,
          backdropURL: "https://m.staticpop.net/poster/item/wide/100582.jpg"
        )),
        HomeHeroFeature(card: MediaCard(
          id: 2,
          posterURL: "https://m.staticpop.net/poster/item/big/15042.jpg",
          title: "Баннер",
          backdropURL: "https://m.staticpop.net/poster/item/wide/15042.jpg"
        ))
      ],
      labels: .init(play: "Смотреть", details: "Подробнее", bookmark: "Закладки", next: "Дальше")
    ),
    size: CGSize(width: 1000, height: 560),
    sideInset: 40,
    isCompact: false,
    onPlay: { _ in },
    onDetails: { _ in }
  )
}
#endif
