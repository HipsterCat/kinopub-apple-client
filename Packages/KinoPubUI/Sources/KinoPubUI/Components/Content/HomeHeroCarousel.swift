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
//  A page is the whole hero — picture, words and buttons slide together under a finger,
//  the paging dots stay put. The pages are a paging `ScrollView`, laid out three laps
//  long so a turn past the last title runs on into the first; once a turn settles on an
//  outer lap the view is put back on the same title of the middle one, which looks the
//  same (`Slot`).
//
//  The picture is forced dark, like everything the Apple TV app draws over a title's
//  picture, and ends on a hard edge: the page under it keeps the system appearance.
//

import SwiftUI

public struct HomeHeroCarousel: View {
  private let hero: HomeHero
  private let size: CGSize
  private let sideInset: CGFloat
  private let isCompact: Bool
  private let onPlay: (MediaCard) -> Void
  private let onDetails: (MediaCard) -> Void
  private let bookmarkEntries: ((MediaCard) -> [MediaCardContextEntry])?

  /// One page: which title, on which lap of the three.
  private struct Slot: Hashable {
    var lap: Int
    var index: Int
  }

  @State private var position: Slot? = Slot(lap: 0, index: 0)
  @State private var isPresented = false
  @State private var isVisibleInPage = true
  @State private var isScrolling = false
  @State private var isHovering = false
  @State private var isMenuOpen = false
  @Environment(\.scenePhase) private var scenePhase

  /// - Parameters:
  ///   - size: the hero's frame — the page's width, and the height the page gives it.
  ///   - sideInset: the page's leading margin, so the words start where the rows do.
  ///   - isCompact: the phone's centred column instead of the leading one.
  public init(hero: HomeHero,
              size: CGSize,
              sideInset: CGFloat,
              isCompact: Bool,
              onPlay: @escaping (MediaCard) -> Void,
              onDetails: @escaping (MediaCard) -> Void,
              bookmarkEntries: ((MediaCard) -> [MediaCardContextEntry])? = nil) {
    self.hero = hero
    self.size = size
    self.sideInset = sideInset
    self.isCompact = isCompact
    self.onPlay = onPlay
    self.onDetails = onDetails
    self.bookmarkEntries = bookmarkEntries
  }

  private var features: [HomeHeroFeature] { hero.features }

  private var slots: [Slot] {
    let laps = features.count > 1 ? [-1, 0, 1] : [0]
    return laps.flatMap { lap in features.indices.map { Slot(lap: lap, index: $0) } }
  }

  private var currentIndex: Int {
    min(position?.index ?? 0, max(features.count - 1, 0))
  }

  /// The tvOS rule: titles turn on their own only while someone can see the hero — not
  /// under a pushed page, another tab or the player, not scrolled away, not while a
  /// finger or the pointer is on it or its Bookmarks menu is open.
  private var advances: Bool {
    features.count > 1 && isPresented && isVisibleInPage && scenePhase == .active
      && !isScrolling && !isHovering && !isMenuOpen
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
    .scrollPosition(id: $position)
    .onScrollPhaseChange { _, phase in
      isScrolling = phase != .idle
      if phase == .idle { settleOnMiddleLap() }
    }
    .frame(width: size.width, height: size.height)
    .overlay(alignment: .bottom) {
      if features.count > 1 {
        HomeHeroPageDots(count: features.count,
                         current: currentIndex,
                         advances: advances,
                         dwell: Self.dwell,
                         onAdvance: { step(1) })
          .padding(.bottom, Metrics.dotsBottom)
      }
    }
    .environment(\.colorScheme, .dark)
    .onHover { isHovering = $0 }
    .onScrollVisibilityChange(threshold: 0.5) { isVisibleInPage = $0 }
    .onAppear { isPresented = true }
    .onDisappear { isPresented = false }
    .onChange(of: features.count) { _, count in
      // The banner set is topped up or trimmed: keep a title that still exists.
      if let position, position.index >= count {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { self.position = Slot(lap: 0, index: 0) }
      }
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
    let from = position ?? Slot(lap: 0, index: 0)
    var next = Slot(lap: from.lap, index: from.index + delta)
    if next.index >= features.count {
      next = Slot(lap: from.lap + 1, index: 0)
    } else if next.index < 0 {
      next = Slot(lap: from.lap - 1, index: features.count - 1)
    }
    guard slots.contains(next) else { return }
    withAnimation(.smooth(duration: 0.6)) { position = next }
  }

  /// A turn that ended on an outer lap goes back to the same title in the middle one,
  /// with nothing animated: the two pages are the same picture, so it does not show.
  private func settleOnMiddleLap() {
    guard let position, position.lap != 0 else { return }
    var transaction = Transaction()
    transaction.disablesAnimations = true
    withTransaction(transaction) {
      self.position = Slot(lap: 0, index: position.index)
    }
  }

  // MARK: Page

  private func page(_ feature: HomeHeroFeature) -> some View {
    ZStack(alignment: isCompact ? .bottom : .bottomLeading) {
      Color.black
      FallbackRemoteImage(urls: feature.backdropCandidates, contentMode: .fill)
        .frame(width: size.width, height: size.height)
        .clipped()
      scrim
      if feature.card.id > 0 {
        words(feature)
          .padding(.horizontal, sideInset)
          .padding(.bottom, features.count > 1 ? Metrics.dotsReserve : Metrics.bottomInset)
      }
    }
    .frame(width: size.width, height: size.height)
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
      .allowsHitTesting(false)
    } else {
      HeroLegibilityTexture(tone: .black)
    }
  }

  // MARK: Words

  private func words(_ feature: HomeHeroFeature) -> some View {
    let card = feature.card
    let alignment: HorizontalAlignment = isCompact ? .center : .leading
    return VStack(alignment: alignment, spacing: Metrics.wordSpacing) {
      VStack(alignment: alignment, spacing: Metrics.wordSpacing) {
        mark(feature)
          .padding(.bottom, Metrics.markGap)
        metaLine(card)
        if let synopsis = card.overview.flatMap({ HomeHeroText.synopsis(of: $0) }) {
          Text(synopsis)
            .font(TypeScale.heroSecondary)
            .foregroundStyle(.white.opacity(0.72))
            .lineLimit(2)
            .frame(maxWidth: Metrics.synopsisMaxWidth, alignment: isCompact ? .center : .leading)
        }
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
    return TitleLogoSlot(resolution: feature.logo, maxWidth: maxWidth, maxHeight: maxHeight) {
      Text(feature.card.title)
        .font(TypeScale.heroTitle)
        .foregroundStyle(.white)
        .lineLimit(2)
        .multilineTextAlignment(isCompact ? .center : .leading)
    }
    .id(feature.card.id)
    .frame(minHeight: maxHeight, alignment: isCompact ? .bottom : .bottomLeading)
  }

  /// Scores, then genre · years · country · seasons — the tvOS banner's line
  /// (`HomeHeroText.metaParts`). One line: when it does not fit, the last parts go first.
  private func metaLine(_ card: MediaCard) -> some View {
    let parts = HomeHeroText.metaParts(for: card)
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
    .foregroundStyle(.white.opacity(0.88))
    .lineLimit(1)
  }

  // MARK: Buttons

  /// Play, Bookmarks, Details, Next — tvOS's row. Where the row does not fit (a phone),
  /// Next goes first (a swipe turns the page), then Details.
  private func buttons(_ feature: HomeHeroFeature) -> some View {
    ViewThatFits(in: .horizontal) {
      buttonRow(feature, details: true, next: true)
      buttonRow(feature, details: true, next: false)
      buttonRow(feature, details: false, next: false)
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
    /// The title page's synopsis width on iOS / macOS (Sasha, 2026-10-29).
    static let synopsisMaxWidth: CGFloat = 660
    static let bottomInset: CGFloat = 28
    /// The dots' own band under the buttons.
    static let dotsBottom: CGFloat = 12
    static let dotsReserve: CGFloat = 48
  }
}

// MARK: - Paging dots

/// The paging dots with the running title's progress in them, the way the Apple TV app
/// draws them. They are also the clock: `onAdvance` when the title's time is up.
///
/// iOS: the system control — `UIPageControl` with `UIPageControlTimerProgress`, what
/// the tvOS hero uses. macOS has no page control, so the same shape is drawn: dots,
/// the current one a capsule filling over the dwell.
struct HomeHeroPageDots: View {
  let count: Int
  let current: Int
  let advances: Bool
  let dwell: TimeInterval
  let onAdvance: () -> Void

  var body: some View {
#if os(iOS)
    SystemPageDots(count: count, current: current, advances: advances,
                   dwell: dwell, onAdvance: onAdvance)
      .fixedSize()
#else
    DrawnPageDots(count: count, current: current, advances: advances,
                  dwell: dwell, onAdvance: onAdvance)
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

  func makeCoordinator() -> Coordinator { Coordinator() }

  func makeUIView(context: Context) -> UIPageControl {
    let control = UIPageControl()
    control.isUserInteractionEnabled = false
    control.hidesForSinglePage = true
    control.backgroundStyle = .minimal
    control.overrideUserInterfaceStyle = .dark
    let timer = UIPageControlTimerProgress(preferredDuration: dwell)
    timer.delegate = context.coordinator
    control.progress = timer
    return control
  }

  func updateUIView(_ control: UIPageControl, context: Context) {
    context.coordinator.onAdvance = onAdvance
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
    var advances = false

    /// The control would turn its own page; the carousel turns it instead, and the dots
    /// follow the carousel.
    func pageControlTimerProgress(_ progress: UIPageControlTimerProgress,
                                  shouldAdvanceToPage page: Int) -> Bool {
      onAdvance()
      return false
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

  @State private var progress: CGFloat = 0
  @ScaledMetric(relativeTo: .caption) private var dot: CGFloat = 7

  private struct Run: Equatable {
    let current: Int
    let advances: Bool
  }

  var body: some View {
    HStack(spacing: dot) {
      ForEach(0..<count, id: \.self) { index in
        if index == current {
          Capsule()
            .fill(.white.opacity(0.35))
            .frame(width: dot * 4, height: dot)
            .overlay(alignment: .leading) {
              Capsule()
                .fill(.white)
                .frame(width: dot * 4 * max(progress, 0.25), height: dot)
            }
        } else {
          Circle()
            .fill(.white.opacity(0.35))
            .frame(width: dot, height: dot)
        }
      }
    }
    .animation(.smooth(duration: 0.3), value: current)
    .task(id: Run(current: current, advances: advances)) {
      progress = 0
      guard advances else { return }
      withAnimation(.linear(duration: dwell)) { progress = 1 }
      try? await Task.sleep(for: .seconds(dwell))
      guard !Task.isCancelled else { return }
      onAdvance()
    }
    .accessibilityHidden(true)
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
