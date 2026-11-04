#if !os(tvOS)
import Foundation
//
//  HomeHeroCarousel.swift
//  KinoPubUI
//
//  The Home hero on iOS, iPadOS and macOS: the tvOS carousel (`TVPageHero.swift`) in
//  SwiftUI — the same titles, logo, line, plot, Play and Bookmarks (Details and Next
//  are tvOS-only: here the picture opens the title and the edge arrows page) and
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

import KinoPubMetadata
import SwiftUI
#if os(macOS)
import AppKit
#endif

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
  @Environment(\.heroStepRequest) private var heroStepRequest

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
  /// A finger (or trackpad) on the pager: tracking, interacting or decelerating. A turn
  /// the code makes scrolls in the `.animating` phase, which may never report `.idle`
  /// when the window is not drawn (a locked screen held the hero for good, trace
  /// 2026-11-04), so only a hand on it holds the clock and the next step.
  @State private var isDragging = false
  @State private var isMenuOpen = false
  @State private var isHovered = false
  /// A turn the code animates is on its way; the scroll may report no phase for it.
  @State private var isTurning = false
  /// Which code turn is the latest: an older one's completion, cut off by a resize or a
  /// newer turn, must not settle the pager back on the page it was leaving.
  @State private var turnID = 0
  /// Bumped when a window resize settles with the pager still off its page: it is built
  /// afresh on the current page. After a burst of resizes the Mac's scroll view stayed
  /// half a page off and ignored every `scrollTo`, while the dots went on turning.
  @State private var generation = 0
  @Environment(\.scenePhase) private var scenePhase
#if os(macOS)
  /// A sheet over the window (What's New): the hero holds still under it, as on the TV
  /// (Sasha, 2026-11-04). Also a window not on screen at all (minimised, another Space,
  /// the screen locked). A window merely not key, behind another app or beside another
  /// window, is still seen and keeps turning.
  @State private var isWindowHeld = false
#endif

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
  /// screen, the bars' `topBleed` above it. Mac: the picture, toolbar strip included,
  /// is always 16:9 of its own width (the window's, less the sidebar), whatever the window's height (Sasha,
  /// 2026-10-30). iPad: a 16:9 picture as long as it leaves a fifth of the screen.
  /// Phone: a 16:10 still under the bars and room under it for the words, at most 70%
  /// of the screen.
  public static func height(width: CGFloat, topBleed: CGFloat, screen: CGFloat,
                            isCompact: Bool) -> CGFloat {
#if os(macOS)
    let picture = width * 9 / 16
#else
    let picture: CGFloat = isCompact
      ? min(topBleed + stillHeight(width: width) * Metrics.compactStillsTall, screen * 0.7)
      : min(width * 9 / 16 + topBleed, screen * 0.8)
#endif
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
      && !isDragging && !isTurning && !isMenuOpen && isWindowKey
  }

  private var isWindowKey: Bool {
#if os(macOS)
    !isWindowHeld
#else
    true
#endif
  }

  public var body: some View {
    ScrollView(.horizontal) {
      LazyHStack(spacing: 0) {
        ForEach(slots, id: \.self) { slot in
          page(features[slot.index])
        }
      }
      .scrollTargetLayout()
    }
    .id(generation)
    // In the hero's own frame, not past it: since the page sits beside the Mac's sidebar,
    // ignoring the safe area widened the scroll view by the sidebar under it — pages
    // narrower than the scroll, turns that skipped a title, and a click on the hero that
    // opened its neighbour (Sasha, 2026-11-04).
    .scrollIndicators(.hidden)
    .scrollTargetBehavior(.paging)
    .scrollPosition($scroll)
    .onScrollGeometryChange(for: CGFloat.self) { geometry in
      let width = geometry.containerSize.width
      // Counted from the inset edge: on a Mac the page runs under the floating sidebar,
      // which sets a leading content inset as wide as the sidebar. A page at rest then
      // sits at offset `n × width − inset`, and the bare offset read as a page part-way
      // through a turn — two pictures at once, until a resize moved the inset (Sasha,
      // 2026-10-31).
      return width > 0 ? (geometry.contentOffset.x + geometry.contentInsets.leading) / width : 0
    } action: { _, page in
      pager.page = page
      // At rest between two pages — a burst of window resizes outran the re-snap on
      // the width change and left it there for good: back onto the current page.
      if !isScrolling, !isTurning, abs(page - page.rounded()) > 0.001 {
        DispatchQueue.main.async { snap() }
      }
    }
    .onScrollPhaseChange { _, phase in
      heroLog("scroll phase \(phase)")
      isScrolling = phase != .idle
      isDragging = phase != .idle && phase != .animating
      if phase == .idle { settle() }
    }
    .frame(width: size.width, height: size.height)
    // The pictures run up under the bars, past the pager's own frame.
    // The scrim is its own layer over the pictures, never redrawn by a turn.
    .background(alignment: .bottom) {
      ZStack {
        HeroBackdrop(features: features, slots: slots, pager: pager,
                     width: size.width, height: size.height + topBleed, topBleed: topBleed,
                     isCompact: isCompact)
        HeroScrim(isCompact: isCompact)
      }
      .frame(width: size.width, height: size.height + topBleed)
      .allowsHitTesting(false)
    }
    .overlay(alignment: isCompact ? .bottom : .bottomLeading) {
      HeroWords(features: features, slots: slots, pager: pager, width: size.width,
                alignment: isCompact ? .bottom : .bottomLeading) { feature in
        wordsBlock(feature)
      }
    }
    .overlay(alignment: .bottom) {
      if features.count > 1 {
        HomeHeroPageDots(count: features.count,
                         current: currentIndex,
                         pager: pager,
                         slots: slots,
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
#if os(macOS)
    .background(WindowSheetProbe(isWindowHeld: $isWindowHeld))
#endif
    .onScrollVisibilityChange(threshold: 0.5) { isVisibleInPage = $0 }
    .onAppear {
      isPresented = true
      snap()
    }
    .onDisappear { isPresented = false }
    // A window resized, or a page pushed and popped, can leave the pager between two
    // pages: the old offset in a new page width, or a turn cut off on its way.
    .onChange(of: size.width) { move(to: current, animated: false) }
    .task(id: size.width) {
      try? await Task.sleep(for: .milliseconds(300))
      guard !Task.isCancelled else { return }
      // Built afresh only when the scroll view stayed off its page after the re-snap
      // (a burst of resizes did that): a rebuild reloads every picture.
      guard abs(pager.page - pager.page.rounded()) > 0.001 else { return }
      isScrolling = false
      isDragging = false
      isTurning = false
      scroll = ScrollPosition(id: current)
      generation += 1
    }
    .onChange(of: isActive) { move(to: current, animated: false) }
    .onChange(of: advances) { _, now in
      heroLog("advances=\(now) active=\(isActive) presented=\(isPresented) visible=\(isVisibleInPage) scene=\(scenePhase == .active) dragging=\(isDragging) turning=\(isTurning) menu=\(isMenuOpen) key=\(isWindowKey)")
    }
    // Left / Right from the keyboard while the page holds focus (Mac sidebar shell).
    .onChange(of: heroStepRequest) { _, request in
      if let request { step(request.delta) }
    }
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
    // A turn already on its way finishes first: stepping from a `current` that has
    // moved ahead of the picture is what skipped a title.
    guard features.count > 1, !isTurning, !isDragging else {
      heroLog("step(\(delta)) dropped turning=\(isTurning) dragging=\(isDragging)")
      return
    }
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
    turnID += 1
    let turn = turnID
    heroLog("move to \(slot.lap):\(slot.index) animated=\(animated) turn=\(turn)")
    if animated {
      isTurning = true
      withAnimation(.smooth(duration: 0.6)) {
        scroll.scrollTo(id: slot)
      } completion: {
        heroLog("turn \(turn) completed (latest \(turnID))")
        guard turn == turnID else { return }
        isTurning = false
        // The turn knows where it goes: `current` is already the target. Not read back
        // from the scroll position — the completion comes ~0.1 s in, before the pages
        // have moved (more so while the window is dragged or the screen throttled), and
        // the rounded position then sent the hero back a title and the clock with it
        // (trace 2026-11-04). Only a page on an outer lap is put back in the middle one.
        if current.lap != 0 {
          move(to: Slot(lap: 0, index: current.index), animated: false)
        }
      }
    } else {
      isTurning = false
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

  /// The title the picture shows now: the page nearest the scroll position.
  private var visibleFeature: HomeHeroFeature? {
    let pages = slots
    guard !pages.isEmpty else { return nil }
    let at = min(max(Int(pager.page.rounded()), 0), pages.count - 1)
    let index = pages[at].index
    return features.indices.contains(index) ? features[index] : nil
  }

  /// Puts the scroll back exactly on the current page when it is not there.
  private func snap() {
    guard !isScrolling, !isTurning, let at = slots.firstIndex(of: current) else { return }
    if abs(pager.page - CGFloat(at)) > 0.001 {
      move(to: current, animated: false)
    }
  }

  // MARK: Page

  /// A page is only the swipe and the tap: the words are one element over all pages
  /// (`HeroWords`) and the pictures one backdrop under them. A tap anywhere that is not
  /// a button opens the title, as in the Apple TV app.
  private func page(_ feature: HomeHeroFeature) -> some View {
    Color.clear
      .frame(width: size.width, height: size.height)
      .contentShape(Rectangle())
      .onTapGesture {
        // The title on screen, not the page that took the tap: while a turn or a drag
        // is under way the two differ, and the click must open what the viewer sees.
        let shown = visibleFeature ?? feature
        guard shown.card.id > 0 else { return }
        onDetails(shown.card)
      }
  }

  /// The words and buttons for one title, where they sit in the hero.
  @ViewBuilder
  private func wordsBlock(_ feature: HomeHeroFeature) -> some View {
    if feature.card.id > 0 {
      words(feature)
        .padding(.leading, sideInset)
        .padding(.trailing, sideInset)
        .padding(.bottom, features.count > 1 ? Metrics.dotsReserve : Metrics.bottomInset)
    }
  }

#if os(macOS) || os(iOS)
  /// Previous / next at the very sides while the pointer is over a wide hero (Mac, iPad
  /// with a pointer). The Apple TV app's own arrows are private (none in SwiftUI or
  /// AppKit, checked in the 27.2 SDKs), so these are drawn to their measures (Sasha,
  /// 2026-10-30): `chevron.compact`, 6 pt from the edge, no safe area.
  @ViewBuilder
  private var pagingArrows: some View {
    if !isCompact, features.count > 1 {
      HStack(spacing: 0) {
        HeroPagingArrow(symbol: "chevron.compact.left", label: hero.labels.previous,
                        isShown: isHovered) { step(-1) }
        Spacer(minLength: 0)
        HeroPagingArrow(symbol: "chevron.compact.right", label: hero.labels.next,
                        isShown: isHovered) { step(1) }
      }
      .padding(.leading, Metrics.arrowEdgeInset)
      .padding(.trailing, Metrics.arrowEdgeInset)
    }
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
      // The words float over the pager: a swipe or tap on them goes to the page under
      // them (turn, open the title). Only the buttons take touches of their own.
      .allowsHitTesting(false)

      buttons(feature)
        .padding(.top, Metrics.buttonsGap)
    }
    .frame(maxWidth: .infinity, alignment: isCompact ? .center : .leading)
  }

  /// The title logo in the tvOS hero's budget (28% × 8.5% of the width on a wide page);
  /// the name in its place after a confirmed miss. Its slot keeps its height while the
  /// logo loads, so the words under it do not jump.
  private func mark(_ feature: HomeHeroFeature) -> some View {
    let maxWidth = (size.width * (isCompact ? 0.7 : 0.4)).rounded()
    let maxHeight = (size.width * (isCompact ? 0.26 : 0.085)).rounded()
    // Lettered names get more room than a logo: two lines of the hero's type in a logo's
    // width broke short names (Sasha's TODO, 2026-11-04).
    let textMaxWidth = (size.width * (isCompact ? 0.9 : 0.5)).rounded()
    return HeroTitleMark(feature: feature, maxWidth: maxWidth, maxHeight: maxHeight,
                         textMaxWidth: textMaxWidth, isCompact: isCompact)
      .id(feature.card.id)
  }

  /// Scores, then two genres · years · country · seasons — the tvOS banner's line
  /// (`HomeHeroText.metaParts`). One line: when it does not fit, the last parts go first.
  private func metaLine(_ card: MediaCard) -> some View {
    let parts = HomeHeroText.metaParts(for: card, genres: HomeHeroText.Rules.genres)
    return ViewThatFits(in: .horizontal) {
      ForEach((0...parts.count).reversed(), id: \.self) { count in
        HStack(spacing: MediaScoresView.groupSpacing) {
          if card.scores.hasDisplayableScore {
            MediaScoresView(card.scores, showsVotes: HomeHeroText.Rules.showsVotes, bannerLine: true)
          }
          ForEach(parts.prefix(count), id: \.self) { part in
            Text(part)
          }
        }
        .fixedSize()
      }
    }
    .font(TypeScale.heroSecondary)
    .foregroundStyle(.primary.opacity(0.85))
    .lineLimit(2)
  }

  // MARK: Buttons

  /// Play and Bookmarks. tvOS's row adds Details and Next; here, as in the Apple TV
  /// app's phone and Mac heroes, a click on the picture opens the title and the edge
  /// arrows (or a swipe) turn the page (Sasha, 2026-10-31).
  private func buttons(_ feature: HomeHeroFeature) -> some View {
    HStack(spacing: MediaActionMetrics.rowSpacing) {
      playButton(feature)
      if bookmarkEntries != nil {
        bookmarkMenu(feature)
      }
    }
    .fixedSize()
  }

  /// What the detail page's Play says for this title (`MediaActionCatalog.play`, laid
  /// over this device's positions); plain Play until its details are in. The quieter
  /// glass pill, not the detail page's white one: the banner is a preview, and white
  /// read as the loudest thing on Home (Sasha, 2026-10-31).
  private func playButton(_ feature: HomeHeroFeature) -> some View {
    var appearance = feature.play ?? MediaActionAppearance(
      id: .play,
      chrome: .pill,
      systemImage: "play.fill",
      title: hero.labels.play,
      accessibilityLabel: hero.labels.play
    )
    appearance.chrome = .pill
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



  // MARK: Metrics

  private enum Metrics {
    static let wordSpacing: CGFloat = 8
    /// Under the logo, a little more than between the lines: tvOS's 24 against 14.
    static let markGap: CGFloat = 6
    static let buttonsGap: CGFloat = 12
    /// The phone hero's height under the bars, in 16:10 stills: the still, and under it
    /// the part of the words that does not sit on the picture.
    static let compactStillsTall: CGFloat = 1.6
    static let arrowEdgeInset: CGFloat = 6
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

  /// The title the scroll is leaving, the one it is heading for, and how far along
  /// (0 = all `from`).
  func blend(over slots: [HomeHeroCarousel.Slot]) -> (from: Int, to: Int, fraction: CGFloat) {
    let position = min(max(page, 0), CGFloat(max(slots.count - 1, 0)))
    let base = Int(position.rounded(.down))
    let from = slots.indices.contains(base) ? slots[base].index : 0
    let to = slots.indices.contains(base + 1) ? slots[base + 1].index : from
    return (from, to, position - CGFloat(base))
  }
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
    let (from, to, fraction) = pager.blend(over: slots)
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
}

/// Wide: the tvOS hero's own legibility texture (`HeroBannerOverlay`) — the leading
/// edge and the foot shaded under the words. Phone: the words are centred, so the shade
/// is the foot alone, the way the Apple TV app's phone hero has it. One layer for all
/// titles, outside the pictures, so a turn never makes it blink.
private struct HeroScrim: View {
  let isCompact: Bool

  var body: some View {
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

/// The words and buttons as one element over all the pages: as the scroll turns, the
/// outgoing title's words slide a little to the leading side and fade out by halfway,
/// and the incoming one's come in from the trailing side out of nothing — the Apple TV
/// app's hero, where the words never travel with the picture (Sasha, 2026-10-30). Only
/// the one more than half there takes clicks.
private struct HeroWords<Content: View>: View {
  let features: [HomeHeroFeature]
  let slots: [HomeHeroCarousel.Slot]
  let pager: HeroPager
  let width: CGFloat
  let alignment: Alignment
  @ViewBuilder let content: (HomeHeroFeature) -> Content

  /// How far the words travel while they fade, against the hero's width.
  private static var travel: CGFloat { 0.06 }

  var body: some View {
    let (from, to, fraction) = pager.blend(over: slots)
    // Keyed by title, so the incoming words stay the same view when they become the
    // outgoing ones — no logo reloading as a turn ends.
    let shown = (to != from && fraction > 0 ? [from, to] : [from]).filter(features.indices.contains)
    ZStack(alignment: alignment) {
      Color.clear.allowsHitTesting(false)
      ForEach(shown, id: \.self) { index in
        let leaving = index == from
        content(features[index])
          .offset(x: (leaving ? -fraction : 1 - fraction) * width * Self.travel)
          .opacity(leaving ? max(0, 1 - fraction * 2) : max(0, fraction * 2 - 1))
          .allowsHitTesting(leaving ? fraction < 0.5 : fraction >= 0.5)
      }
    }
  }
}

#if os(macOS) || os(iOS)
/// One hover arrow: the glyph shows while the pointer is anywhere on the hero, in the
/// secondary colour; over the arrow's own 28 × 52 pt box a dark material capsule comes
/// up 2 pt around the glyph; pressed, the glyph turns primary. The box is what takes the
/// click and the hover.
private struct HeroPagingArrow: View {
  let symbol: String
  let label: String
  let isShown: Bool
  let action: () -> Void

  @State private var isHovered = false

  var body: some View {
    Button(action: action) {
      Image(systemName: symbol)
        .font(.system(size: 26))
    }
    .buttonStyle(HeroPagingArrowStyle(isHovered: isHovered))
    .frame(width: 28, height: 52)
    .contentShape(Rectangle())
    .onHover { isHovered = $0 }
    .opacity(isShown || isHovered ? 1 : 0)
    .animation(.easeInOut(duration: 0.2), value: isShown || isHovered)
    .accessibilityLabel(Text(label))
    .help(label)
  }
}

private struct HeroPagingArrowStyle: ButtonStyle {
  let isHovered: Bool

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .foregroundStyle(configuration.isPressed ? .primary : .secondary)
      .padding(2)
      .background {
        if isHovered {
          Capsule()
            .fill(.regularMaterial)
            .overlay(Capsule().fill(Color(white: 0.2).opacity(0.6)))
        }
      }
      .frame(width: 28, height: 52)
      .contentShape(Rectangle())
      .animation(.easeOut(duration: 0.15), value: isHovered)
  }
}
#endif

// MARK: - Paging dots

/// The title logo, or the name after a confirmed miss, and the other name under it — the
/// title page hero's line, by the same rule (`TitleLogoCaption`), under a logo no wider
/// than the logo is drawn (Sasha, 2026-11-04). The banner knows no partner title from
/// enrichment: it makes no details request, so only kino.pub's own two names count.
private struct HeroTitleMark: View {
  let feature: HomeHeroFeature
  let maxWidth: CGFloat
  let maxHeight: CGFloat
  let textMaxWidth: CGFloat
  let isCompact: Bool

  @State private var reportedMark: TitleLogoMark = .empty
  @State private var deliveredLanguage: WorkerArtworkLanguageTag?

  private var card: MediaCard { feature.card }
  private var mark: TitleLogoMark {
    TitleLogoCaption.resolvedMark(reportedMark, logoURL: feature.logoURL)
  }
  private var caption: String? {
    TitleLogoCaption.line(mark: mark, deliveredLanguage: deliveredLanguage,
                          logoURL: feature.logoURL, localized: card.title,
                          original: card.subtitle ?? card.title)
  }

  var body: some View {
    let alignment: HorizontalAlignment = isCompact ? .center : .leading
    SecondLineCappedToFirst(capsWidth: mark == .logo, alignment: alignment) {
      TitleLogoSlot(resolution: feature.logo, maxWidth: maxWidth, maxHeight: maxHeight,
                    textMaxWidth: textMaxWidth, alignment: alignment,
                    onMarkChange: { reportedMark = $0 },
                    onDeliveredLanguageChange: { if let language = $0 { deliveredLanguage = language } }) {
        Text(card.title)
          .font(TypeScale.heroTitle)
          .foregroundStyle(.white)
          .lineLimit(2)
          .multilineTextAlignment(isCompact ? .center : .leading)
      }
      .frame(minHeight: maxHeight, alignment: isCompact ? .bottom : .bottomLeading)
      if let caption {
        Text(caption)
          .font(TypeScale.heroSecondary)
          .foregroundStyle(.white.opacity(0.7))
          .lineLimit(2)
          .multilineTextAlignment(isCompact ? .center : .leading)
          .fixedSize(horizontal: false, vertical: true)
          .padding(.top, mark == .logo ? 12 : 6)
      }
    }
  }
}

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
  /// The title the hero rests on: its dwell runs, and a new one starts it over.
  let current: Int
  /// Read here only, so a drag redraws the dots and nothing else around them.
  let pager: HeroPager
  let slots: [HomeHeroCarousel.Slot]
  let advances: Bool
  let dwell: TimeInterval
  let onAdvance: () -> Void
  let onSelect: (Int) -> Void

  /// The title under the scroll right now: the dot moves when the picture has, half-way
  /// through a turn, not when the scroll comes to rest (it lagged the banner, Sasha,
  /// 2026-11-04).
  private var shown: Int {
    guard !slots.isEmpty else { return current }
    let page = min(max(Int(pager.page.rounded()), 0), slots.count - 1)
    return slots[page].index
  }

  var body: some View {
#if os(iOS)
    SystemPageDots(count: count, current: current, shown: shown, advances: advances,
                   dwell: dwell, onAdvance: onAdvance, onSelect: onSelect)
      .fixedSize()
#else
    DrawnPageDots(count: count, current: current, shown: shown, advances: advances,
                  dwell: dwell, onAdvance: onAdvance, onSelect: onSelect)
#endif
  }
}

#if os(iOS)
private struct SystemPageDots: UIViewRepresentable {
  let count: Int
  let current: Int
  let shown: Int
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
    if control.currentPage != shown { control.currentPage = shown }
    if context.coordinator.current != current {
      context.coordinator.current = current
      // A new title gets its whole dwell, whoever turned the page.
      timer.currentProgress = 0
    }
    if advances != context.coordinator.advances {
      context.coordinator.advances = advances
      // Held, not restarted: a drag let go before the turn goes on from where it was.
      if advances { timer.resumeTimer() } else { timer.pauseTimer() }
    }
  }

  final class Coordinator: NSObject, UIPageControlTimerProgressDelegate {
    var onAdvance: () -> Void = {}
    var onSelect: (Int) -> Void = { _ in }
    var advances = false
    var current = -1

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
/// The Mac's page dots, drawn: macOS has no page control (`.page` styles are unavailable,
/// no NSPageControl in the 27.2 SDK). Built as UIPageControl and Plozz's dots behave:
/// one capsule per dot that stretches into the running one in a single animation (no
/// swap of shapes, which jumped), a row of fixed width, the running one filling as it
/// dwells, a tap or a scrub along the row picks a page, and a plate behind the row while
/// the pointer is over it (Sasha, 2026-11-04).
private struct DrawnPageDots: View {
  let count: Int
  let current: Int
  let shown: Int
  let advances: Bool
  let dwell: TimeInterval
  let onAdvance: () -> Void
  let onSelect: (Int) -> Void

  /// UIPageControl's measures: an 8 pt dot, 8 pt apart, the running one three dots long.
  @ScaledMetric(relativeTo: .body) private var dot: CGFloat = 8
  /// The dwell spent on `runFor` before the run going now, and when that run began
  /// (`nil` while held). A hold keeps the fill where it was — a drag let go before the
  /// turn, a sheet over the window — instead of starting it over or filling it whole.
  @State private var spent: TimeInterval = 0
  @State private var runStart: Date?
  @State private var runFor = -1
  @State private var isHovered = false
  @State private var scrubbed: Int?

  private struct Run: Equatable {
    let current: Int
    let advances: Bool
  }

  private var running: CGFloat { dot * 3 }
  private var gap: CGFloat { dot }

  var body: some View {
    TimelineView(.animation(paused: runStart == nil)) { context in
      let progress = fill(at: context.date)
      HStack(spacing: gap) {
        ForEach(0..<count, id: \.self) { index in
          let active = index == shown
          Capsule()
            .fill(.white.opacity(0.35))
            .overlay(alignment: .leading) {
              Capsule()
                .fill(.white)
                .frame(width: active ? max(dot, running * (shown == current ? progress : 0)) : 0)
                .opacity(active ? 1 : 0)
            }
            .frame(width: active ? running : dot, height: dot)
        }
      }
    }
    .padding(.horizontal, dot)
    .padding(.vertical, dot)
    .background {
      Capsule()
        .fill(.white.opacity(0.14))
        .opacity(isHovered ? 1 : 0)
    }
    .contentShape(Capsule())
    .animation(.smooth(duration: 0.3), value: shown)
    .animation(.easeOut(duration: 0.2), value: isHovered)
    .onHover { isHovered = $0 }
    .gesture(
      DragGesture(minimumDistance: 0)
        .onChanged { value in pick(at: value.location.x) }
        .onEnded { value in
          pick(at: value.location.x)
          scrubbed = nil
        }
    )
    .accessibilityElement()
    .accessibilityLabel(Text("\(shown + 1) / \(count)"))
    .accessibilityAdjustableAction { direction in
      switch direction {
      case .increment: onSelect((current + 1) % count)
      case .decrement: onSelect((current - 1 + count) % count)
      @unknown default: break
      }
    }
    .task(id: Run(current: current, advances: advances)) {
      // Lets the run this one replaces count its time first.
      await Task.yield()
      runStart = nil
      // A new title starts its dwell over.
      if runFor != current {
        runFor = current
        spent = 0
      }
      guard advances else { heroLog("dwell \(current) held, spent \(spent)"); return }
      let start = Date()
      let title = current
      runStart = start
      heroLog("dwell \(current) runs \(max(dwell - spent, 0)) s")
      try? await Task.sleep(for: .seconds(max(dwell - spent, 0)))
      guard !Task.isCancelled else {
        // Only the time it actually ran counts. Counted on the next run instead, a run
        // whose dots went away (a resize, the window dragged) brought all the time away
        // back with it and turned at once, a title skipped (Sasha, 2026-11-04).
        if runFor == title { spent += Date().timeIntervalSince(start) }
        if runStart == start { runStart = nil }
        heroLog("dwell \(title) cancelled, spent \(spent)")
        return
      }
      runStart = nil
      heroLog("dwell \(title) done, advance")
      onAdvance()
    }
  }

  private func fill(at date: Date) -> CGFloat {
    guard dwell > 0 else { return 0 }
    let now = runStart.map { spent + date.timeIntervalSince($0) } ?? spent
    return CGFloat(min(max(now / dwell, 0), 1))
  }

  /// The dot under `x`, in the row's own layout (the running one is wider).
  private func pick(at x: CGFloat) {
    var edge = dot
    var index = count - 1
    for i in 0..<count {
      edge += (i == shown ? running : dot) + gap / 2
      if x < edge { index = i; break }
      edge += gap / 2
    }
    guard index != scrubbed else { return }
    scrubbed = index
    if index != shown { onSelect(index) }
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

#if !os(tvOS)
/// A keyboard turn of the Home hero, from whatever holds focus in the page: each request
/// has its own id, so the same direction twice is two turns.
public struct HeroStepRequest: Equatable, Sendable {
  public let id: UUID
  public let delta: Int

  public init(delta: Int) {
    self.id = UUID()
    self.delta = delta
  }
}

public extension EnvironmentValues {
  @Entry var heroStepRequest: HeroStepRequest? = nil
}
#endif

#if os(macOS)
/// Whether a sheet hangs over this view's window. SwiftUI has no environment value for it
/// (`controlActiveState` / `appearsActive` also go off for a window that is merely not key),
/// so the window's own sheet notifications say it.
private struct WindowSheetProbe: NSViewRepresentable {
  @Binding var isWindowHeld: Bool

  func makeNSView(context: Context) -> Probe {
    let probe = Probe()
    probe.onChange = { isWindowHeld = $0 }
    return probe
  }

  func updateNSView(_ probe: Probe, context: Context) {
    probe.onChange = { isWindowHeld = $0 }
  }

  final class Probe: NSView {
    var onChange: ((Bool) -> Void)?
    nonisolated(unsafe) private var observers: [NSObjectProtocol] = []

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      observers.forEach(NotificationCenter.default.removeObserver)
      observers = []
      guard let window else { return }
      let center = NotificationCenter.default
      observers.append(center.addObserver(forName: NSWindow.willBeginSheetNotification,
                                          object: window, queue: .main) { [weak self] _ in
        MainActor.assumeIsolated { self?.onChange?(true) }
      })
      observers.append(center.addObserver(forName: NSWindow.didEndSheetNotification,
                                          object: window, queue: .main) { [weak self, weak window] _ in
        MainActor.assumeIsolated { self?.onChange?(window.map(Self.isHeld) ?? false) }
      })
      // Not on screen: minimised, hidden, covered, on another Space, the screen locked.
      // An undrawn window cannot finish a turn's scroll, so it does not start one.
      observers.append(center.addObserver(forName: NSWindow.didChangeOcclusionStateNotification,
                                          object: window, queue: .main) { [weak self, weak window] _ in
        MainActor.assumeIsolated { self?.onChange?(window.map(Self.isHeld) ?? false) }
      })
      let current = Self.isHeld(window)
      DispatchQueue.main.async { [weak self] in self?.onChange?(current) }
    }

    /// A sheet over the window, or the window not visible at all.
    static func isHeld(_ window: NSWindow) -> Bool {
      if window.attachedSheet != nil { return true }
#if DEBUG
      // Test runs from a shell start behind other windows: `-KINOPUBHeroIgnoreOcclusion YES`.
      if UserDefaults.standard.bool(forKey: "KINOPUBHeroIgnoreOcclusion") { return false }
#endif
      return !window.occlusionState.contains(.visible)
    }

    deinit {
      observers.forEach(NotificationCenter.default.removeObserver)
    }
  }
}
#endif

/// Debug trace of the hero's clock and turns (`[HomeHero]` in the console).
@inline(__always)
func heroLog(_ message: @autoclosure () -> String) {
#if DEBUG
  print("[HomeHero] \(String(format: "%.2f", Date().timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1000))) \(message())")
#endif
}
