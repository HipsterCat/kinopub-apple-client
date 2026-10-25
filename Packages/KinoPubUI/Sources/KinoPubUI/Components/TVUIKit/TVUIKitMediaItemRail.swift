#if os(tvOS)
//
//  TVUIKitMediaItemRail.swift
//  KinoPubUI
//
//  Horizontal wide rails drawn by the system's own media-item cell:
//  `TVMediaItemContentConfiguration.wideCell()` laid out from
//  `NSCollectionLayoutSection.orthogonalLayoutSectionForMediaItems()`.
//
//  This is the one 16:9 rail for Continue Watching, episodes, trailers, Up Next, and
//  genre / category tiles. Posters stay on `TVPosterView` — the media-item
//  configuration ships a 16:9 `wideCellConfiguration` only, there is no 2:3 variant.
//
//  One deliberately simple look, not a set of options:
//
//  * **Under the tile** — one line, the system's own `text`, in its own space below the
//    artwork. `S2 E4 • Episode Name` in Continue Watching, `7. "Episode Name"` in a
//    season rail. `secondaryText` renders nothing for us, so there is no second line.
//  * **Inside the artwork** — a progress bar whenever there is progress, drawn by our
//    overlay rather than by `playbackProgress`, because the system's only paints on the
//    focused tile and an idle rail still has to say "you did not finish this". Else the
//    runtime bottom-trailing. A play/checkmark glyph sits bottom-leading. Neither sits
//    on a pill; a drop shadow carries their legibility. No SF Symbol floats in the
//    middle of the tile, and no dates appear down here.
//  * **Top-leading badge** — an announced episode's date goes through the *system*
//    badge (`configuration.badgeText`, the same chip as 4K / HDR) and outranks a
//    capability badge. "Watched" stays on our overlay, paired with its scrim and
//    checkmark. `badgeText` takes a `String`, so no glyph can ride along with the date.
//  * **Progress is never a series completion ratio.** A card with no specific episode
//    pinned to it cannot be "in progress" here, however its `progress` field reads —
//    that number would be "6 of 12 episodes watched", not a resume point.
//

import SwiftUI
import UIKit
import TVUIKit
import KinoPubBackend
import KinoPubMedia

// MARK: - Status

/// What this tile can do, which drives the glyph, the bottom-trailing runtime, and the
/// top badge. Episodes need all of them: a rail spans "watched it", "half-way through",
/// "not on kino.pub", and "airs in three days" side by side.
public enum TVUIKitMediaItemStatus: Equatable {
  /// Nothing watched yet. Play glyph + runtime, no bar.
  case ready
  /// Part-watched, 0…1. Progress bar instead of the runtime — the two never show
  /// together, the bar already says "how far in".
  case inProgress(Double)
  /// Finished. Checkmark, "Watched" badge, runtime still shown (it is a fact about the
  /// episode, not about where playback is).
  case watched
  /// On a schedule but not on kino.pub. **No** play glyph — the absence is the signal.
  /// Dimming and disabling is not how we say this; the missing glyph and the caption are.
  case unavailable
  /// Announced, not yet on kino.pub. Associated text is the badge's date — "in 3 days"
  /// or "Mar 13, 2026" — computed by the caller, since only the caller knows today's
  /// date and the app's date-formatting rules (see `SeasonsRailView.airDateLabel`).
  case upcoming(String)
  /// An episode that has aired and kino.pub does not have: a lock in the badge corner,
  /// where an upcoming one shows its date. The two never show together — a date says
  /// "not out yet", the lock "out, but not here" (Sasha, 2026-10-04). One still ahead
  /// of its air date is `.upcoming`, not this.
  case locked

  var glyph: String? {
    switch self {
    case .ready, .inProgress, .watched, .unavailable, .upcoming, .locked: nil
    }
  }

  var progress: Double {
    if case .inProgress(let fraction) = self { return min(max(fraction, 0), 1) }
    return 0
  }

  /// Whether the bottom-trailing corner shows the runtime: on every tile without a
  /// progress bar, watched or not (Sasha, 2026-10-11). The bar already says "how far
  /// along", so a tile in progress shows that instead.
  var showsRuntime: Bool {
    switch self {
    case .ready, .watched, .unavailable, .upcoming: true
    // The bar says it; a locked one has nothing to play and no runtime on the item.
    case .inProgress, .locked: false
    }
  }

  /// Both state badges live on **our** overlay, not on `configuration.badgeText`. The
  /// system chip only paints on the focused tile, and "airs in 3 days" is exactly the
  /// thing an idle rail has to say — same reason the progress bar moved here. Named
  /// distinctly from `TVUIKitMediaItem.badgeText` (the capability badge) so a call site
  /// reading either name says which one it means.
  var overlayBadgeText: String? {
    switch self {
    case .watched: String(localized: "TVMediaItem_Watched")
    case .upcoming(let dateText): dateText
    case .ready, .inProgress, .unavailable, .locked: nil
    }
  }

  /// The symbol the badge leads with: a checkmark beside "Watched", the lock alone in
  /// place of a date. `badgeText` is a `String` with no room for a glyph, which is
  /// part of why this badge is ours and not the system's.
  var badgeSymbol: String? {
    switch self {
    case .watched: "checkmark"
    case .locked: "lock.fill"
    case .ready, .inProgress, .unavailable, .upcoming: nil
    }
  }

  /// Watched tiles sit back so the unwatched ones beside them read first.
  var dimsArtwork: Bool { self == .watched }
}

// MARK: - Model

/// One wide media item — everything the configuration and our overlay can draw.
public struct TVUIKitMediaItem: Identifiable, Equatable {
  public let id: Int
  public let imageURL: URL?
  /// Drawn when there is no artwork URL, or until one loads. Genre / category tiles
  /// have no photograph at all and use this as their real artwork.
  public let tint: UIColor?
  public let symbol: String?
  /// How `tint` is drawn when it is the artwork.
  public let tileStyle: TVUIKitTileArtwork.Style
  /// The line under the tile — always visible: a movie's title, or "S2, E11 · Show".
  public let caption: String?
  /// Second system line under a Library still grid — remaining time, or when it was watched.
  public let detail: String?
  public let status: TVUIKitMediaItemStatus
  /// Chip text beside the glyph, inside the artwork — runtime, or time left.
  public let timeLabel: String?
  public let badgeText: String?
  /// Live content gets the system's own red badge treatment.
  public let badgeIsLive: Bool
  /// How the picture at `imageURL` meets the 16:9 tile.
  public let artworkFit: ArtworkFit
  /// What the player has on screen — the player's Season tab marks it: the still dimmed,
  /// a ring around the tile at rest, the caption in the primary colour, no progress bar.
  public let isNowPlaying: Bool

  public enum ArtworkFit: Equatable, Sendable {
    /// Centre-cropped to the tile — stills, backdrops, covers.
    case fill
    /// Whole, with its edges carried out to the tile (`TVUIKitTileArtwork.letterboxed`) —
    /// a logo, which a crop would cut.
    case letterbox
  }

  public init(id: Int,
              imageURL: URL? = nil,
              tint: UIColor? = nil,
              symbol: String? = nil,
              tileStyle: TVUIKitTileArtwork.Style = .flat,
              caption: String? = nil,
              detail: String? = nil,
              status: TVUIKitMediaItemStatus = .ready,
              timeLabel: String? = nil,
              badgeText: String? = nil,
              badgeIsLive: Bool = false,
              artworkFit: ArtworkFit = .fill,
              isNowPlaying: Bool = false) {
    self.id = id
    self.imageURL = imageURL
    self.tint = tint
    self.symbol = symbol
    self.tileStyle = tileStyle
    self.caption = caption
    self.detail = detail
    self.status = status
    self.timeLabel = timeLabel
    self.badgeText = badgeText
    self.badgeIsLive = badgeIsLive
    self.artworkFit = artworkFit
    self.isNowPlaying = isNowPlaying
  }

  /// A coloured tile with a glyph and nothing else — genres, categories, anything with
  /// no artwork of its own. Colour is derived from the name so it is stable per genre.
  public init(id: Int, genre: String, symbol: String, tint: UIColor? = nil) {
    self.init(id: id,
              tint: tint ?? TVUIKitTileArtwork.tint(for: genre),
              symbol: symbol,
              caption: genre,
              status: .unavailable)
  }
}

public extension TVUIKitMediaItem {
  /// Home / rails — one packed caption line. A parameterless `init(card:)` so
  /// `cards.map(TVUIKitMediaItem.init(card:))` still type-checks.
  init(card: MediaCard) {
    self.init(card: card, stackedCaption: false)
  }

  /// The app's card model in media-item terms.
  ///
  /// `stackedCaption` is the Library's still grid: the card's own title and subtitle
  /// as the system's two text lines, no overlay packing. Home's rail stays one line.
  init(card: MediaCard, stackedCaption: Bool) {
    let art = card.landscapeImageURL ?? card.backdropURL ?? card.posterURL
    let status = Self.status(for: card)
    let subtitle = card.subtitle?.trimmingCharacters(in: .whitespacesAndNewlines)
    self.init(id: card.id,
              imageURL: URL(string: art),
              caption: stackedCaption ? card.title : TVUIKitCardText.caption(for: card),
              detail: stackedCaption ? (subtitle?.isEmpty == false ? subtitle : nil) : nil,
              status: status,
              timeLabel: stackedCaption ? nil : Self.timeLabel(for: card, status: status),
              badgeText: Self.badgeText(for: card))
  }

  /// A fraction only means something pinned to one episode or one movie. A
  /// series-level card (`isSeries` with no specific `video` chosen) can carry
  /// `WatchingItem.progress` — "6 of 12 episodes watched" — and that must never
  /// paint a resume bar here: it is not a point to seek back to.
  static func status(for card: MediaCard) -> TVUIKitMediaItemStatus {
    if card.isWatched { return .watched }
    guard card.video != nil || !card.isSeries else { return .ready }
    // `card.progress` is already `WatchProgress.resumeFraction`. Re-thresholding
    // 0.02 / 0.95 here invented a second watched threshold.
    if let progress = card.progress {
      return .inProgress(progress)
    }
    return .ready
  }

  /// The runtime, for the statuses that show one (`TVUIKitMediaItemStatus.showsRuntime`
  /// — not `.inProgress`, where the bar already says "how far along"). Nil when the payload never told us how long the thing
  /// is — better an empty corner than a made-up number.
  static func timeLabel(for card: MediaCard, status: TVUIKitMediaItemStatus) -> String? {
    guard status.showsRuntime, let duration = card.durationSeconds, duration >= 60 else { return nil }
    return RuntimeText(seconds: duration).text(for: .timeBadge)
  }

  /// Capability only. `MediaCard.badge` deliberately does **not** feed this — on Home it
  /// carries kino.pub's "+10 new episodes" counter, which is noise in a corner chip.
  static func badgeText(for card: MediaCard) -> String? {
    if card.is4K { return "4K" }
    if card.isHDR { return "HDR" }
    return nil
  }
}

// MARK: - SwiftUI entry point

/// Horizontal rail of system media-item cells. Sizes itself — callers must not pin a
/// `.frame(height:)` guess on top of it.
public struct TVUIKitMediaItemRail: UIViewControllerRepresentable {
  /// A row of tiles of one height with a fixed gap, for a container that sizes the row
  /// itself rather than by columns (the player's tabs): the tile is 16:9 at `height`,
  /// `spacing` apart, `inset` from the sides.
  public struct TileRun: Equatable {
    public var height: CGFloat
    public var spacing: CGFloat
    public var inset: CGFloat

    public init(height: CGFloat, spacing: CGFloat, inset: CGFloat) {
      self.height = height
      self.spacing = spacing
      self.inset = inset
    }

    @MainActor
    func section() -> NSCollectionLayoutSection {
      let size = NSCollectionLayoutSize(widthDimension: .absolute((height * 16 / 9).rounded()),
                                        heightDimension: .absolute(height))
      let group = NSCollectionLayoutGroup.horizontal(layoutSize: size,
                                                     subitems: [NSCollectionLayoutItem(layoutSize: size)])
      let section = NSCollectionLayoutSection(group: group)
      section.interGroupSpacing = spacing
      section.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: inset, bottom: 0, trailing: inset)
      return section
    }
  }

  private let items: [TVUIKitMediaItem]
  private let contentInset: CGFloat
  private let columns: Int?
  private let caption: TVPageCaption
  private let entryItemID: Int?
  private let animatesEntryScroll: Bool
  private let onSelect: (Int) -> Void
  private let onNearEnd: ((Int) -> Void)?
  private let onFocusedItem: ((Int) -> Void)?
  private let contextMenuProvider: ((Int) -> [MediaCardContextEntry])?
  private let allowsFocus: Bool
  private let fillsHeight: Bool
  private let overlayOnFocus: Bool
  private let tileRun: TileRun?

  /// - Parameters:
  ///   - contentInset: leading/trailing inset, so the rail lines up with the section
  ///     header above it. Vertical spacing stays the system's.
  ///   - columns: lay the rail out as a `TVPage` still row of this many HIG columns
  ///     (`TVPageLayout.stillRail`) — the size, gutter and focus room Home's rows use.
  ///     Nil keeps the system's `orthogonalLayoutSectionForMediaItems` proportions.
  ///   - caption: with `columns`, when the line under the still shows.
  ///   - entryItemID: where the rail should sit and where focus should land when it
  ///     arrives — the resume episode, or the first episode of a season the user just
  ///     picked. Changing it scrolls the rail; it is *not* a focus binding, because the
  ///     focus engine owns focus once the rail has it.
  ///   - onFocusedItem: which item the engine focused, so a caller can follow it (the
  ///     season tabs track the episode you are standing on).
  ///   - onSelect / onNearEnd / contextMenuProvider: all keyed by `TVUIKitMediaItem.id`.
  ///   - fillsHeight: take the height it is offered rather than the row's own, items from
  ///     the top — for a container that places the row itself (the player's tabs).
  ///   - overlayOnFocus: the runtime and the progress bar show on the focused tile only.
  ///   - tileRun: lay the row out as `TileRun` instead of columns (`columns` is then ignored).
  public init(items: [TVUIKitMediaItem],
              contentInset: CGFloat = 0,
              columns: Int? = nil,
              caption: TVPageCaption = .always,
              entryItemID: Int? = nil,
              animatesEntryScroll: Bool = true,
              onSelect: @escaping (Int) -> Void,
              onNearEnd: ((Int) -> Void)? = nil,
              onFocusedItem: ((Int) -> Void)? = nil,
              contextMenuProvider: ((Int) -> [MediaCardContextEntry])? = nil,
              allowsFocus: Bool = true,
              fillsHeight: Bool = false,
              overlayOnFocus: Bool = false,
              tileRun: TileRun? = nil) {
    self.items = items
    self.contentInset = contentInset
    self.columns = columns
    self.caption = caption
    self.entryItemID = entryItemID
    self.animatesEntryScroll = animatesEntryScroll
    self.onSelect = onSelect
    self.onNearEnd = onNearEnd
    self.onFocusedItem = onFocusedItem
    self.contextMenuProvider = contextMenuProvider
    self.allowsFocus = allowsFocus
    self.fillsHeight = fillsHeight
    self.overlayOnFocus = overlayOnFocus
    self.tileRun = tileRun
  }

  public func makeUIViewController(context: Context) -> TVUIKitMediaItemRailController {
    let controller = TVUIKitMediaItemRailController(contentInset: contentInset, columns: columns,
                                                    caption: caption, overlayOnFocus: overlayOnFocus,
                                                    tileRun: tileRun)
    controller.apply(items: items,
                     entryItemID: entryItemID,
                     animatesEntryScroll: animatesEntryScroll,
                     onSelect: onSelect,
                     onNearEnd: onNearEnd,
                     onFocusedItem: onFocusedItem,
                     contextMenuProvider: contextMenuProvider,
                     allowsFocus: allowsFocus)
    return controller
  }

  public func updateUIViewController(_ controller: TVUIKitMediaItemRailController, context: Context) {
    controller.apply(items: items,
                     entryItemID: entryItemID,
                     animatesEntryScroll: animatesEntryScroll,
                     onSelect: onSelect,
                     onNearEnd: onNearEnd,
                     onFocusedItem: onFocusedItem,
                     contextMenuProvider: contextMenuProvider,
                     allowsFocus: allowsFocus)
  }

  public func sizeThatFits(_ proposal: ProposedViewSize,
                           uiViewController: TVUIKitMediaItemRailController,
                           context: Context) -> CGSize? {
    guard let width = proposal.width, width > 1 else { return nil }
    if fillsHeight, let height = proposal.height { return CGSize(width: width, height: height) }
    guard !items.isEmpty else { return CGSize(width: width, height: 0) }
    if let columns {
      return CGSize(width: width, height: TVPageLayout.stillRailHeight(columns: columns, caption: caption,
                                                                       containerWidth: width,
                                                                       sideInset: contentInset))
    }
    return CGSize(width: width, height: TVUIKitMediaItemMetrics.railHeight(width: width))
  }
}

// MARK: - Sizing

public enum TVUIKitMediaItemMetrics {
  /// Multiplier on the system's own tile size. 1.0 is exactly Apple's row; that reads
  /// small in our shelves, so the shipping tile is a notch above it.
    public static let scale: CGFloat = 1.18

  /// Used only when the probe comes back with nothing — roughly the system row.
  public static let fallback = SystemMetrics(itemSize: CGSize(width: 500, height: 340),
                                             interGroupSpacing: 40,
                                             verticalPadding: 40)

  public struct SystemMetrics: Equatable {
    public var itemSize: CGSize
    public var interGroupSpacing: CGFloat
    /// The section's own top + bottom insets, which we do not scale.
    public var verticalPadding: CGFloat
  }

  @MainActor
  public static func railHeight(width: CGFloat) -> CGFloat {
    let metrics = systemMetrics(width: width)
    return metrics.itemSize.height * scale + metrics.verticalPadding
  }

  /// A section with the system's proportions at our size. `orthogonalLayoutSectionForMediaItems()`
  /// cannot be resized — it exposes neither its group nor its item — so we measure what
  /// it produces once per width and rebuild an equivalent section scaled up. Keeping the
  /// measurement means the tile stays whatever shape Apple ships, not a shape we guessed.
  @MainActor
  public static func section(width: CGFloat, inset: CGFloat) -> NSCollectionLayoutSection {
    let metrics = systemMetrics(width: width)
    let size = NSCollectionLayoutSize(
      widthDimension: .absolute(metrics.itemSize.width * scale),
      heightDimension: .absolute(metrics.itemSize.height * scale)
    )
    let item = NSCollectionLayoutItem(layoutSize: size)
    let group = NSCollectionLayoutGroup.horizontal(layoutSize: size, subitems: [item])
    let section = NSCollectionLayoutSection(group: group)
    section.orthogonalScrollingBehavior = .continuous
    section.interGroupSpacing = metrics.interGroupSpacing * scale
    section.contentInsets = NSDirectionalEdgeInsets(top: metrics.verticalPadding / 2,
                                                    leading: 0,
                                                    bottom: metrics.verticalPadding / 2,
                                                    trailing: 0)
    if inset > 0 {
      // Only the horizontal edges, so the first tile starts under the section title.
      section.contentInsets.leading = inset
      section.contentInsets.trailing = inset
    }
    return section
  }

  /// What `orthogonalLayoutSectionForMediaItems()` lays out at this width. Deterministic
  /// for a given width, so it is measured once with a throwaway collection view.
  @MainActor
  public static func systemMetrics(width: CGFloat) -> SystemMetrics {
    let key = width.rounded()
    guard key > 1 else { return fallback }
    if let cached = cache[key] { return cached }

    let layout = UICollectionViewCompositionalLayout { _, _ in
      .orthogonalLayoutSectionForMediaItems()
    }
    let probe = UICollectionView(
      frame: CGRect(x: 0, y: 0, width: key, height: 4000),
      collectionViewLayout: layout
    )
    probe.register(UICollectionViewCell.self, forCellWithReuseIdentifier: ProbeSource.reuseID)
    probe.dataSource = probeSource
    probe.layoutIfNeeded()


    let first = frame(of: 0, in: probe)
    let second = frame(of: 1, in: probe)
    var metrics = fallback
    if let first, first.width > 1, first.height > 1 {
      metrics.itemSize = first.size
      if let second, second.minX > first.maxX {
        metrics.interGroupSpacing = second.minX - first.maxX
      }
      let content = layout.collectionViewContentSize.height
      if content > first.height {
        metrics.verticalPadding = content - first.height
      }
    }
    cache[key] = metrics
    return metrics
  }

  private static func frame(of index: Int, in probe: UICollectionView) -> CGRect? {
    let path = IndexPath(item: index, section: 0)
    if let attributes = probe.layoutAttributesForItem(at: path) { return attributes.frame }
    return probe.cellForItem(at: path)?.frame
  }

  @MainActor private static var cache: [CGFloat: SystemMetrics] = [:]
  @MainActor private static let probeSource = ProbeSource()

  /// Two cells is enough to read both the tile size and the gap between tiles.
  private final class ProbeSource: NSObject, UICollectionViewDataSource {
    static let reuseID = "TVUIKitMediaItemProbeCell"

    func collectionView(_ collectionView: UICollectionView,
                        numberOfItemsInSection section: Int) -> Int { 2 }

    func collectionView(_ collectionView: UICollectionView,
                        cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
      collectionView.dequeueReusableCell(withReuseIdentifier: Self.reuseID, for: indexPath)
    }
  }
}

// MARK: - Controller

@MainActor
public final class TVUIKitMediaItemRailController: UIViewController {
  private var items: [TVUIKitMediaItem] = []
  private let contentInset: CGFloat
  private let columns: Int?
  private let caption: TVPageCaption
  private let overlayOnFocus: Bool
  private let tileRun: TVUIKitMediaItemRail.TileRun?
  /// The row is this collection's own horizontal scroll, so the offset we set is the one
  /// that shows (`align`).
  private var ownsScroll: Bool { columns != nil || tileRun != nil }

  private var entryItemID: Int?
  private var onSelect: ((Int) -> Void)?
  private var onNearEnd: ((Int) -> Void)?
  private var onFocusedItem: ((Int) -> Void)?
  private var contextMenuProvider: ((Int) -> [MediaCardContextEntry])?
  private var allowsFocus = true

  /// Asked by the engine before it lands on an item, by id. Nil: every item. The season
  /// rail uses it to keep the remote off the episodes it should not land on.
  public var canFocusItem: ((Int) -> Bool)?

  /// How opaque an item's tile is, by id. Nil: all of them fully. The season rail steps
  /// back the seasons that are not the selected one.
  var itemAlpha: ((Int) -> CGFloat)?

  private lazy var collectionView: UICollectionView = {
    let inset = contentInset
    let caption = caption
    let layout: UICollectionViewCompositionalLayout
    if let tileRun {
      layout = UICollectionViewCompositionalLayout(sectionProvider: { _, _ in tileRun.section() },
                                                   configuration: TVPageLayout.stillRunConfiguration())
    } else if let columns {
      // A still row is its own horizontal scroll (`TVPageLayout.stillRun`), so the offset
      // we set is the one that shows.
      layout = UICollectionViewCompositionalLayout(sectionProvider: { _, environment in
        TVPageLayout.stillRun(columns: columns, caption: caption,
                              containerWidth: environment.container.contentSize.width, sideInset: inset)
      }, configuration: TVPageLayout.stillRunConfiguration())
    } else {
      layout = UICollectionViewCompositionalLayout { _, environment in
        TVUIKitMediaItemMetrics.section(width: environment.container.contentSize.width, inset: inset)
      }
    }
    let view = UICollectionView(frame: .zero, collectionViewLayout: layout)
    view.backgroundColor = .clear
    view.clipsToBounds = false
    view.contentInsetAdjustmentBehavior = .never
    // Deliberately OFF. `remembersLastFocusedIndexPath` restores by *index*, and this
    // rail's contents grow underneath it — TMDB schedules arrive after the kino.pub
    // episodes and insert unaired entries, so the remembered index silently becomes a
    // different, later episode. That is how opening a series you have never watched
    // landed on episode 7. `indexPathForPreferredFocusedView` below does the same job
    // by identity, from `entryItemID`.
    view.remembersLastFocusedIndexPath = false
    view.showsHorizontalScrollIndicator = false
    view.showsVerticalScrollIndicator = false
    view.dataSource = self
    view.delegate = self
    view.prefetchDataSource = self
    view.register(TVUIKitMediaItemCell.self, forCellWithReuseIdentifier: TVUIKitMediaItemCell.reuseID)
    return view
  }()

  init(contentInset: CGFloat, columns: Int? = nil, caption: TVPageCaption = .always,
       overlayOnFocus: Bool = false, tileRun: TVUIKitMediaItemRail.TileRun? = nil) {
    self.tileRun = tileRun
    self.contentInset = contentInset
    self.columns = columns
    self.caption = caption
    self.overlayOnFocus = overlayOnFocus
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  /// Reported once per layout pass so the "edge cells are clipped / the next card only
  /// loads on focus" question has measurements behind it rather than screenshots.
  public override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    FocusLog.railGeometry(collectionView, section: "wide-rail")
    // `apply` comes before the view has a width, where the scroll to the entry is a no-op;
    // the first pass with one is where the rail can first stand on it.
    if !hasParkedOnEntry, entryItemID != nil, collectionView.bounds.width > 1 {
      hasParkedOnEntry = true
      scrollToEntry(animated: false)
    }
  }

  /// The first layout with a width has scrolled to the entry item.
  private var hasParkedOnEntry = false

  /// Whether focus is on one of this rail's tiles. While it is not and there is an entry
  /// item, the entry is the only tile the engine may land on, so a move in from outside
  /// arrives there — the way `TVSeasonRail` keeps its rail. Left to geometry, the player's
  /// Season tab took the remote from the tab pill to the sliver of the episode before the
  /// one playing (seen 2026-10-20); the engine does not ask `indexPathForPreferredFocusedView`
  /// for a directional move.
  private var focusIsInside = false
  /// The tile the remote left the rail from; coming back lands there rather than on an
  /// entry the rail may have scrolled away from since.
  private var returnItemID: Int?

  /// The one tile a move in from outside may land on: where the remote left, or the entry.
  private var landingItemID: Int? {
    guard entryItemID != nil else { return nil }
    if let returnItemID, index(of: returnItemID) != nil { return returnItemID }
    return index(of: entryItemID) != nil ? entryItemID : nil
  }

  public override func didUpdateFocus(in context: UIFocusUpdateContext,
                                      with coordinator: UIFocusAnimationCoordinator) {
    super.didUpdateFocus(in: context, with: coordinator)
    focusIsInside = context.nextFocusedView?.isDescendant(of: collectionView) ?? false
  }

  public override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .clear
    view.clipsToBounds = false
    view.insetsLayoutMarginsFromSafeArea = false
    collectionView.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(collectionView)
    NSLayoutConstraint.activate([
      collectionView.topAnchor.constraint(equalTo: view.topAnchor),
      collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
    ])
  }

  func apply(items: [TVUIKitMediaItem],
             entryItemID: Int?,
             animatesEntryScroll: Bool,
             onSelect: @escaping (Int) -> Void,
             onNearEnd: ((Int) -> Void)?,
             onFocusedItem: ((Int) -> Void)?,
             contextMenuProvider: ((Int) -> [MediaCardContextEntry])?,
             allowsFocus: Bool = true) {
    let changed = self.items != items
    let entryMoved = self.entryItemID != entryItemID
    self.items = items
    self.entryItemID = entryItemID
    self.onSelect = onSelect
    self.onNearEnd = onNearEnd
    self.onFocusedItem = onFocusedItem
    self.contextMenuProvider = contextMenuProvider
    let focusChanged = self.allowsFocus != allowsFocus
    self.allowsFocus = allowsFocus
    collectionView.allowsFocus = allowsFocus
    if changed || focusChanged { collectionView.reloadData() }
    if changed || entryMoved { scrollToEntry(animated: animatesEntryScroll && !changed) }
  }

  /// The season rail's way in: items and callbacks, without `apply`'s "a new entry
  /// scrolls the rail". Where the rail sits is `align(to:animated:)`, where focus lands is
  /// `preferredItemID`, each asked for on its own.
  func configure(items: [TVUIKitMediaItem],
                 onSelect: @escaping (Int) -> Void,
                 onFocusedItem: ((Int) -> Void)?,
                 contextMenuProvider: ((Int) -> [MediaCardContextEntry])?) {
    let changed = self.items != items
    self.items = items
    self.onSelect = onSelect
    self.onFocusedItem = onFocusedItem
    self.contextMenuProvider = contextMenuProvider
    guard changed else { return }
    collectionView.reloadData()
  }

  /// Re-reads `itemAlpha` for the tiles on screen; the rest read it as they are dequeued.
  func refreshItemAlpha(animated: Bool) {
    let apply = { [self] in
      for path in collectionView.indexPathsForVisibleItems where items.indices.contains(path.item) {
        (collectionView.cellForItem(at: path) as? TVUIKitMediaItemCell)?.tileAlpha = alpha(at: path.item)
      }
    }
    if animated {
      UIView.animate(withDuration: 0.25, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction],
                     animations: apply)
    } else {
      apply()
    }
  }

  private func alpha(at index: Int) -> CGFloat {
    itemAlpha?(items[index].id) ?? 1
  }

  /// Where focus lands when the engine enters the rail (`indexPathForPreferredFocusedView`).
  /// Setting it moves nothing.
  var preferredItemID: Int? {
    get { entryItemID }
    set { entryItemID = newValue }
  }

  /// What a focus guide points at to land on `preferredItemID`: the collection view,
  /// which asks `indexPathForPreferredFocusedView`.
  var focusTarget: UIFocusEnvironment { collectionView }

  /// Scrolls the rail so this item's art stands where the first item's stands at rest —
  /// on the page margin — or, near the end, as far as the rail goes, so the last item
  /// rests on the trailing margin rather than leaving empty rail after it.
  func align(to id: Int, animated: Bool) {
    guard let index = index(of: id) else { return }
    collectionView.layoutIfNeeded()
    guard collectionView.numberOfItems(inSection: 0) > index,
          let first = collectionView.layoutAttributesForItem(at: IndexPath(item: 0, section: 0)),
          let target = collectionView.layoutAttributesForItem(at: IndexPath(item: index, section: 0))
    else { return }
    let maxX = max(collectionView.contentSize.width - collectionView.bounds.width, 0)
    let x = min(max(target.frame.minX - first.frame.minX, 0), maxX)
    FocusLog.railScroll(section: "wide-rail", toIndex: index, of: items.count, animated: animated)
    collectionView.setContentOffset(CGPoint(x: x, y: collectionView.contentOffset.y), animated: animated)
  }

  /// The collection view by name, not the default: the default searches the root view
  /// by visual layout, which finds nothing when the rail is below the fold — and that is
  /// exactly where it is when SwiftUI hands it focus from the hero (`.focused` on the
  /// rail; the hero's «+ ещё N»). The collection view then asks
  /// `indexPathForPreferredFocusedView`, so the entry item wins.
  public override var preferredFocusEnvironments: [UIFocusEnvironment] {
    allowsFocus ? [collectionView] : []
  }

  private func index(of id: Int?) -> Int? {
    guard let id else { return nil }
    return items.firstIndex { $0.id == id }
  }

  /// Park the rail on its entry item. Scrolling only — focus is asked for through
  /// `indexPathForPreferredFocusedView`, which is the hook the engine consults when it
  /// enters this rail; moving focus from here instead would fight it.
  private func scrollToEntry(animated: Bool) {
    if ownsScroll, let entryItemID {
      align(to: entryItemID, animated: animated)
      return
    }
    guard let index = index(of: entryItemID) else { return }
    let path = IndexPath(item: index, section: 0)
    // After a reload the layout has no attributes yet, so the scroll has to wait a
    // pass or it silently no-ops on the first appearance — the case that matters most.
    collectionView.layoutIfNeeded()
    guard collectionView.numberOfItems(inSection: 0) > index else { return }
    FocusLog.railScroll(section: "wide-rail", toIndex: index, of: items.count, animated: animated)
    collectionView.scrollToItem(at: path, at: .left, animated: animated)
  }
}

extension TVUIKitMediaItemRailController: UICollectionViewDataSourcePrefetching {
  public func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
    TVUIKitRemoteImage.prefetch(imageURLs(at: indexPaths))
  }

  public func collectionView(_ collectionView: UICollectionView,
                             cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
    TVUIKitRemoteImage.cancelPrefetch(imageURLs(at: indexPaths))
  }

  private func imageURLs(at indexPaths: [IndexPath]) -> [URL?] {
    indexPaths.compactMap { path in
      items.indices.contains(path.item) ? items[path.item].imageURL : nil
    }
  }
}

extension TVUIKitMediaItemRailController: UICollectionViewDataSource, UICollectionViewDelegate {
  public func collectionView(_ collectionView: UICollectionView,
                             numberOfItemsInSection section: Int) -> Int {
    items.count
  }

  public func collectionView(_ collectionView: UICollectionView,
                             cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
    let cell = collectionView.dequeueReusableCell(
      withReuseIdentifier: TVUIKitMediaItemCell.reuseID,
      for: indexPath
    ) as! TVUIKitMediaItemCell
    cell.configure(items[indexPath.item], allowsFocus: allowsFocus,
                   captionOnFocus: columns != nil && caption == .onFocus,
                   hidesCaption: tileRun != nil || (columns != nil && caption == .never),
                   overlayOnFocus: overlayOnFocus)
    cell.tileAlpha = alpha(at: indexPath.item)
    return cell
  }

  public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
    guard items.indices.contains(indexPath.item) else { return }
    onSelect?(items[indexPath.item].id)
  }

  /// Where focus lands when the engine enters this rail. This is the native hook for
  /// "start here" — the alternative is pushing focus programmatically from outside,
  /// which fights the engine and loses.
  public func indexPathForPreferredFocusedView(in collectionView: UICollectionView) -> IndexPath? {
    guard allowsFocus else { return nil }
    guard let index = index(of: landingItemID ?? entryItemID) else { return nil }
    return IndexPath(item: index, section: 0)
  }

  public func collectionView(_ collectionView: UICollectionView,
                             canFocusItemAt indexPath: IndexPath) -> Bool {
    guard allowsFocus else { return false }
    guard items.indices.contains(indexPath.item) else { return true }
    let id = items[indexPath.item].id
    // `canFocusItem` is the season rail's, which keeps its own entry; the rest of the
    // rails with an entry keep it here.
    if let canFocusItem { return canFocusItem(id) }
    if !focusIsInside, let landingItemID { return id == landingItemID }
    return true
  }

  public func collectionView(_ collectionView: UICollectionView,
                             didUpdateFocusIn context: UICollectionViewFocusUpdateContext,
                             with coordinator: UIFocusAnimationCoordinator) {
    let name: (IndexPath?) -> String? = { [weak self] path in
      guard let self, let path, self.items.indices.contains(path.item) else { return nil }
      return self.items[path.item].caption
    }
    FocusLog.engine(section: "wide-rail",
                    from: name(context.previouslyFocusedIndexPath),
                    to: name(context.nextFocusedIndexPath))

    guard let path = context.nextFocusedIndexPath, items.indices.contains(path.item) else { return }
    if entryItemID != nil { returnItemID = items[path.item].id }
    onFocusedItem?(items[path.item].id)
  }

  public func collectionView(_ collectionView: UICollectionView,
                             willDisplay cell: UICollectionViewCell,
                             forItemAt indexPath: IndexPath) {
    guard items.indices.contains(indexPath.item) else { return }
    onNearEnd?(items[indexPath.item].id)
  }

  // tvOS routes long-press-Select to the focused view and up its responder chain, so an
  // interaction installed inside the cell never fires — the collection view's own
  // delegate hook is the one UIKit wires to the focus engine, and on tvOS only the
  // plural `…ForItemsAt indexPaths:` variant exists.
  public func collectionView(_ collectionView: UICollectionView,
                             contextMenuConfigurationForItemsAt indexPaths: [IndexPath],
                             point: CGPoint) -> UIContextMenuConfiguration? {
    guard let indexPath = indexPaths.first,
          items.indices.contains(indexPath.item),
          let entries = contextMenuProvider?(items[indexPath.item].id),
          !entries.isEmpty
    else { return nil }

    return UIContextMenuConfiguration(identifier: indexPath as NSIndexPath, previewProvider: nil) { _ in
      TVUIKitContextMenuBuilder.menu(from: entries)
    }
  }

  public func collectionView(
    _ collectionView: UICollectionView,
    willEndContextMenuInteraction configuration: UIContextMenuConfiguration,
    animator: (any UIContextMenuInteractionAnimating)?
  ) {
    TVContextMenuHandoff.menuWillEnd(animator: animator)
  }
}

// MARK: - Cell

@MainActor
final class TVUIKitMediaItemCell: UICollectionViewCell {
  static let reuseID = "TVUIKitMediaItemCell"

  private var item: TVUIKitMediaItem?
  private var artwork: UIImage?
  private var loadedURL: URL?
  private var imageTask: Task<Void, Never>?
  private let overlay = TVUIKitMediaItemOverlayView()
  /// DEBUG `-KINOPUBFocusFirstPoster` sets this false on the CW landscape rail.
  private var cellAllowsFocus = true
  /// The caption under the still appears with focus only (Sasha, 2026-09-21) — the
  /// same rule as the poster footer. `false` keeps it on the tile at rest (grids).
  private var captionOnFocus = false
  /// A `.never` still run: no line under the tile at all.
  private var hidesCaption = false
  /// The runtime and the bar on the focused tile only (the player's tabs).
  private var overlayOnFocus = false

  /// How opaque the tile is. On the content view, not the cell — the layout writes the
  /// cell's own alpha back to 1 whenever it applies attributes — and again after every
  /// configuration, which can put a new content view in place.
  var tileAlpha: CGFloat = 1 {
    didSet { contentView.alpha = tileAlpha }
  }

  func configure(_ item: TVUIKitMediaItem, allowsFocus: Bool = true, captionOnFocus: Bool = false,
                 hidesCaption: Bool = false, overlayOnFocus: Bool = false) {
    cellAllowsFocus = allowsFocus
    self.captionOnFocus = captionOnFocus
    self.hidesCaption = hidesCaption
    self.overlayOnFocus = overlayOnFocus
    let keepsArtwork = self.item?.imageURL == item.imageURL && loadedURL == item.imageURL
    self.item = item
    accessibilityIdentifier = "kinopub.rail.item.\(item.id)"
    if !keepsArtwork {
      artwork = nil
      loadArtwork(for: item)
    }
    setNeedsUpdateConfiguration()
  }

  override func updateConfiguration(using state: UICellConfigurationState) {
    super.updateConfiguration(using: state)
    guard let item else {
      contentConfiguration = nil
      return
    }

    var config = TVMediaItemContentConfiguration.wideCell()
    if let updated = config.updated(for: state) as? TVMediaItemContentConfiguration {
      config = updated
    }
    config.image = artwork ?? fallbackImage(for: item)
    // `text` is the line *under* the tile, always visible. Secondary at rest, label
    // when focused (CURRENT.md caption law); the configuration's default is white
    // regardless of appearance, which is what read as "always white, with a shadow".
    let hideCaption = hidesCaption || (captionOnFocus && !state.isFocused)
    config.text = hideCaption ? nil : item.caption
    config.textProperties.color = state.isFocused || item.isNowPlaying ? .label : .secondaryLabel
    // Library still grids ask for the system's second line (title + remaining / when).
    // Home's rail leaves `detail` nil and stays one line. `updated(for:)` is the
    // sample's construction — the 2026-08-11 attempt set `secondaryText` on a raw
    // `wideCell()` and it painted nothing.
    config.secondaryText = hideCaption ? nil : item.detail
    if item.detail != nil {
      config.secondaryTextProperties.color = state.isFocused ? .secondaryLabel : .tertiaryLabel
    }
    // Zero on purpose: the system's bar only appears on the focused tile, and "you
    // started this and did not finish it" is exactly what an *idle* rail has to say.
    // Ours lives in the overlay below, where we control when it shows.
    config.playbackProgress = 0
    // One corner, one chip. A state badge (Watched / a release date) is drawn by our
    // overlay and outranks the capability badge — 4K on something you cannot watch yet
    // is not the useful fact.
    if item.status.overlayBadgeText == nil, let badge = item.badgeText, !badge.isEmpty {
      config.badgeText = badge
      config.badgeProperties = item.badgeIsLive ? .liveContent() : .default()
    }

    overlay.apply(status: item.status, timeLabel: item.timeLabel, isNowPlaying: item.isNowPlaying,
                  showsTime: !overlayOnFocus || state.isFocused)
    config.overlayView = overlay

    contentConfiguration = config
    contentView.alpha = tileAlpha
    backgroundConfiguration = item.isNowPlaying ? nowPlayingRing(for: state) : nil
  }

  /// The ring round the still of the episode on screen. The system draws it: a clear cell
  /// background framed on the still, with a stroke outside it that
  /// `UIBackgroundConfiguration.strokeOutset` keeps concentric with the corners.
  ///
  /// At rest it stands `ringGap` off the still. Focused, it hugs the still's focused frame
  /// (`TVMediaItemContentView.focusedFrameGuide`), in the same animation, so the tile keeps
  /// saying "playing" while it is the focused one — and under Increase Contrast it lies on
  /// the system's own border rather than beside it (Sasha, 2026-10-21).
  ///
  /// **Apple API limitation:** the ring cannot be part of the still. Focus, parallax and
  /// the press all happen inside the system's image stack, which clips to the still, and its
  /// focused layer overscans past the edge (a ring drawn inside the still is cut off in focus,
  /// probed on tvOS 27.2). TVUIKit also exposes no corner radius: `effectiveRadius` reads 0
  /// on every view of the stack, so the still's corners are measured (`stillCornerRadius`).
  private func nowPlayingRing(for state: UICellConfigurationState) -> UIBackgroundConfiguration {
    var ring = UIBackgroundConfiguration.clear()
    let still = bounds
    var frame = still
    if state.isFocused, let content = contentView as? TVMediaItemContentView {
      // The guide runs a little outside the still it frames: 1.5 pt in puts the ring on the
      // still's edge (tvOS 27.2 shots, 2026-10-21).
      let focused = content.focusedFrameGuide.layoutFrame.insetBy(dx: Self.guideOverhang,
                                                                  dy: Self.guideOverhang)
      if focused.width > 1 { frame = focused }
    }
    ring.backgroundInsets = NSDirectionalEdgeInsets(top: frame.minY - still.minY,
                                                    leading: frame.minX - still.minX,
                                                    bottom: still.maxY - frame.maxY,
                                                    trailing: still.maxX - frame.maxX)
    ring.cornerRadius = state.isFocused ? Self.focusedStillCornerRadius : Self.stillCornerRadius
    ring.strokeColor = .label
    // The outset is the stroke's outer edge. Focused, the stroke starts under the still's
    // edge (`guideOverhang`), so it is widened by as much to show the same 4 pt.
    let width = Self.ringWidth + (state.isFocused ? Self.guideOverhang : 0)
    ring.strokeWidth = width
    ring.strokeOutset = width + (state.isFocused ? 0 : Self.ringGap)
    return ring
  }

  private static let ringWidth: CGFloat = 4
  private static let guideOverhang: CGFloat = 1.5
  private static let ringGap: CGFloat = 6
  /// `wideCell()`'s still corners, measured off tvOS 27.2 shots (2026-10-21), at rest and
  /// focused. TVUIKit exposes no radius (see `nowPlayingRing`).
  private static let stillCornerRadius: CGFloat = 12
  private static let focusedStillCornerRadius: CGFloat = 12

  override func didUpdateFocus(in context: UIFocusUpdateContext,
                               with coordinator: UIFocusAnimationCoordinator) {
    super.didUpdateFocus(in: context, with: coordinator)
    guard item?.isNowPlaying == true else { return }
    // The ring grows and shrinks with the still, in the same animation.
    coordinator.addCoordinatedAnimations { [weak self] in
      guard let self else { return }
      self.updateConfiguration(using: self.configurationState)
      self.layoutIfNeeded()
    }
  }

  private func fallbackImage(for item: TVUIKitMediaItem) -> UIImage {
    guard let tint = item.tint else { return TVUIKitTileArtwork.placeholder(traits: traitCollection) }
    return TVUIKitTileArtwork.wide(tint: tint, symbol: item.symbol, style: item.tileStyle)
  }

  private func loadArtwork(for item: TVUIKitMediaItem) {
    imageTask?.cancel()
    imageTask = nil
    loadedURL = nil
    guard let url = item.imageURL else {
      ArtworkLog.skipped(by: "wide", reason: "no artwork URL")
      return
    }
    // Already decoded — take it now so a recycled tile never shows the tint fallback
    // in place of art it had a moment ago.
    let size = contentView.bounds.size
    let mode: Artwork.ResizeMode = item.artworkFit == .letterbox ? .fit : .fill
    if let hit = TVUIKitRemoteImage.cached(url: url, size: size, mode: mode) {
      artwork = Self.present(hit, fit: item.artworkFit)
      loadedURL = url
      ArtworkLog.servedFromMemory(url, by: "wide")
      return
    }
    ArtworkLog.requested(url, by: "wide")
    imageTask = Task { [weak self] in
      let image = await TVUIKitRemoteImage.load(url: url, size: size, mode: mode)
      guard let self, !Task.isCancelled, self.item?.imageURL == url else { return }
      self.artwork = image.map { Self.present($0, fit: item.artworkFit) }
      self.loadedURL = image == nil ? nil : url
      self.setNeedsUpdateConfiguration()
    }
  }

  /// The loaded picture as the tile draws it — a logo letterboxed to the wide cell's 16:9.
  private static func present(_ image: UIImage, fit: TVUIKitMediaItem.ArtworkFit) -> UIImage {
    switch fit {
    case .fill: image
    case .letterbox: TVUIKitTileArtwork.letterboxed(image, aspectRatio: 16 / 9)
    }
  }

  override func prepareForReuse() {
    super.prepareForReuse()
    imageTask?.cancel()
    imageTask = nil
    item = nil
    artwork = nil
    loadedURL = nil
    contentConfiguration = nil
    cellAllowsFocus = true
    captionOnFocus = false
    hidesCaption = false
    overlayOnFocus = false
    tileAlpha = 1
    backgroundConfiguration = nil
  }

  /// `super` asks the collection view's delegate (`canFocusItemAt`) — the hook the season
  /// rail and an entry item keep the remote with. Answering `cellAllowsFocus` alone
  /// skipped it, so neither ever ran (found 2026-10-20).
  override var canBecomeFocused: Bool { cellAllowsFocus && super.canBecomeFocused }
}

// MARK: - Overlay

/// Sits on `TVMediaItemContentConfiguration.overlayView`, which the system pins over the
/// artwork and resizes with it. Carries what the configuration has no property for: a
/// play/checkmark glyph in the bottom-leading corner, the runtime in the bottom-trailing
/// corner, a top-leading state badge (Watched / an upcoming release date), and the
/// progress bar.
///
/// The runtime wears the same dark pill as the Watched badge: bare text with no plate
/// did not read over the art (Sasha, 2026-10-11). Everything here is shown immediately,
/// never gated by focus: the bar and the runtime are mutually exclusive (exactly one of
/// them says "how far along"), so neither needs to wait for a look to appear.
@MainActor
final class TVUIKitMediaItemOverlayView: UIView {
  private let gradientLayer = CAGradientLayer()
  private let scrim = UIView()
  private let glyphView = UIImageView()
  private let runtimeBadge = UIView()
  private let runtimeLabel = UILabel()
  private let badge = UIView()
  private let badgeIcon = UIImageView()
  private let badgeLabel = UILabel()
  private var badgeIconWidth: NSLayoutConstraint!
  private var badgeIconLeading: NSLayoutConstraint!
  private var badgeLabelLeading: NSLayoutConstraint!
  private var badgeLabelTrailing: NSLayoutConstraint!
  /// Ours, not the configuration's. `playbackProgress` only paints on the focused tile,
  /// and "started, not finished" is precisely what an idle rail has to say — so the bar
  /// moved here, where it is on whenever there is progress.
  private let progressTrack = UIView()
  private let progressFill = UIView()
  private var progressFillWidth: NSLayoutConstraint!
  /// Over the whole still of the episode the player has on screen.
  private let nowPlayingDim = UIView()

  /// Keeps the corner chrome clear of the bar along the very bottom edge.
  private static let cornerInset: CGFloat = 32
  private static let glyphSize: CGFloat = 22
  private static let badgeIconSize: CGFloat = 16
  private static let badgeHeight: CGFloat = 32
  /// Both pills stand this far in from their corner.
  private static let badgeInset: CGFloat = 8
  private static let badgeFill = UIColor.black.withAlphaComponent(0.36)
  /// Fraction of the tile height the legibility gradient covers, from the bottom up.
  private static let gradientHeightFraction: CGFloat = 0.5
  private var progressFraction: CGFloat = 0

  init() {
    super.init(frame: .zero)
    isUserInteractionEnabled = false

    // A light bottom-up fade, not a hard band — just enough for the glyph and runtime to
    // read over bright or busy artwork, since the system's own bottom gradient (under
    // its own text) does not reach up over the artwork itself.
//    gradientLayer.colors = [UIColor.clear.cgColor, UIColor.black.withAlphaComponent(0.25).cgColor]
//    gradientLayer.locations = [0, 1]
//    layer.addSublayer(gradientLayer)

//    scrim.translatesAutoresizingMaskIntoConstraints = false
//    scrim.backgroundColor = UIColor.red.withAlphaComponent(0)
//    scrim.isHidden = true
//    addSubview(scrim)

    nowPlayingDim.translatesAutoresizingMaskIntoConstraints = false
    nowPlayingDim.backgroundColor = UIColor.black.withAlphaComponent(0.45)
    nowPlayingDim.isHidden = true
    addSubview(nowPlayingDim)

    glyphView.translatesAutoresizingMaskIntoConstraints = false
    glyphView.tintColor = .secondaryLabel
    glyphView.contentMode = .scaleAspectFill
    glyphView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 20, weight: .bold)
//    TVUIKitChromeSupport.applyLegibilityShadow(to: glyphView.layer)
    addSubview(glyphView)

    // The Watched badge's pill and type, in the opposite corner.
    runtimeBadge.translatesAutoresizingMaskIntoConstraints = false
    runtimeBadge.backgroundColor = Self.badgeFill
    runtimeBadge.layer.cornerCurve = .continuous
    runtimeBadge.isHidden = true
    addSubview(runtimeBadge)

    runtimeLabel.translatesAutoresizingMaskIntoConstraints = false
    runtimeLabel.font = .preferredFont(forTextStyle: .caption2)
    runtimeLabel.textColor = .white
    runtimeBadge.addSubview(runtimeLabel)

    // A real pill, unlike the bottom corner — this is a badge (Watched / a release
    // date), a different kind of chrome from "what Select does", and Apple's own
    // capability badges (4K / HDR) it stands in for are pills too.
    badge.translatesAutoresizingMaskIntoConstraints = false
    badge.backgroundColor = Self.badgeFill
//       badge.backgrou/*nd(*/.regularMaterial, in: Capsule())
    badge.layer.cornerCurve = .continuous
    badge.isHidden = true
    addSubview(badge)

    badgeIcon.translatesAutoresizingMaskIntoConstraints = false
//    badgeIcon.tintColor = .white
    badgeIcon.contentMode = .scaleAspectFit
    badgeIcon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
    badge.addSubview(badgeIcon)

    badgeLabel.translatesAutoresizingMaskIntoConstraints = false
    badgeLabel.font = .preferredFont(forTextStyle: .caption2)
    badgeLabel.textColor = .white
    badge.addSubview(badgeLabel)

    progressTrack.translatesAutoresizingMaskIntoConstraints = false
    progressTrack.backgroundColor = UIColor.black.withAlphaComponent(0.2)
    progressTrack.layer.cornerRadius = 3
    progressTrack.isHidden = true
    addSubview(progressTrack)

    progressFill.translatesAutoresizingMaskIntoConstraints = false
    progressFill.backgroundColor = .white
    progressFill.layer.cornerRadius = 3
    progressTrack.addSubview(progressFill)

    badgeIconWidth = badgeIcon.widthAnchor.constraint(equalToConstant: Self.badgeIconSize)
    badgeIconLeading = badgeIcon.leadingAnchor.constraint(equalTo: badge.leadingAnchor, constant: 4)
    badgeLabelLeading = badgeLabel.leadingAnchor.constraint(equalTo: badgeIcon.trailingAnchor, constant: 5)
    badgeLabelTrailing = badgeLabel.trailingAnchor.constraint(equalTo: badge.trailingAnchor, constant: -10)
    progressFillWidth = progressFill.widthAnchor.constraint(equalToConstant: 0)

    NSLayoutConstraint.activate([
      nowPlayingDim.topAnchor.constraint(equalTo: topAnchor),
      nowPlayingDim.bottomAnchor.constraint(equalTo: bottomAnchor),
      nowPlayingDim.leadingAnchor.constraint(equalTo: leadingAnchor),
      nowPlayingDim.trailingAnchor.constraint(equalTo: trailingAnchor),

      progressTrack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
      progressTrack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
      progressTrack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
      progressTrack.heightAnchor.constraint(equalToConstant: 6),

      progressFill.leadingAnchor.constraint(equalTo: progressTrack.leadingAnchor),
      progressFill.topAnchor.constraint(equalTo: progressTrack.topAnchor),
      progressFill.bottomAnchor.constraint(equalTo: progressTrack.bottomAnchor),
      progressFillWidth,

//      scrim.topAnchor.constraint(equalTo: topAnchor),
//      scrim.bottomAnchor.constraint(equalTo: bottomAnchor),
//      scrim.leadingAnchor.constraint(equalTo: leadingAnchor),
//      scrim.trailingAnchor.constraint(equalTo: trailingAnchor),

      glyphView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
      glyphView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.cornerInset),
      glyphView.widthAnchor.constraint(equalToConstant: Self.glyphSize),
      glyphView.heightAnchor.constraint(equalToConstant: Self.glyphSize),

      runtimeBadge.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.badgeInset),
      runtimeBadge.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.badgeInset),
      runtimeBadge.heightAnchor.constraint(equalToConstant: Self.badgeHeight),
      runtimeLabel.leadingAnchor.constraint(equalTo: runtimeBadge.leadingAnchor, constant: 10),
      runtimeLabel.trailingAnchor.constraint(equalTo: runtimeBadge.trailingAnchor, constant: -10),
      runtimeLabel.centerYAnchor.constraint(equalTo: runtimeBadge.centerYAnchor),

      badge.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.badgeInset),
      badge.topAnchor.constraint(equalTo: topAnchor, constant: Self.badgeInset),
      badge.heightAnchor.constraint(equalToConstant: Self.badgeHeight),

      badgeIconLeading,
      badgeIcon.centerYAnchor.constraint(equalTo: badge.centerYAnchor),
      badgeIconWidth,

      badgeLabelLeading,
      badgeLabelTrailing,
      badgeLabel.centerYAnchor.constraint(equalTo: badge.centerYAnchor)
    ])
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func layoutSubviews() {
    super.layoutSubviews()
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    badge.layer.cornerRadius = badge.bounds.height / 2
    runtimeBadge.layer.cornerRadius = runtimeBadge.bounds.height / 2
    progressFillWidth.constant = max(progressTrack.bounds.width, 0) * progressFraction
    gradientLayer.frame = CGRect(x: 0,
                                 y: bounds.height * (1 - Self.gradientHeightFraction),
                                 width: bounds.width,
                                 height: bounds.height * Self.gradientHeightFraction)
    CATransaction.commit()
  }

  /// - Parameter showsTime: false keeps the runtime and the bar out (an unfocused tile in the
  ///   player's tabs).
  func apply(status: TVUIKitMediaItemStatus, timeLabel: String?, isNowPlaying: Bool = false,
             showsTime: Bool = true) {
    scrim.isHidden = !status.dimsArtwork
    // Off (Sasha, 2026-10-21: the ring says it). Kept for dimming watched or upcoming tiles
    // as a viewer's choice later, cleared on focus.
    nowPlayingDim.isHidden = true // !isNowPlaying

    let glyph = status.glyph
    glyphView.image = glyph.flatMap { UIImage(systemName: $0) }
    glyphView.isHidden = glyph == nil

    // The episode on screen has no bar: the player's own scrubber is where it is.
    progressFraction = isNowPlaying || !showsTime ? 0 : CGFloat(status.progress)
    progressTrack.isHidden = progressFraction <= 0
    setNeedsLayout()

    // At rest too (Sasha, 2026-10-11, replacing "only while focused" of 2026-09-21).
    // The episode on screen trades its bar for the runtime, like a tile with none.
    let showsRuntime = showsTime && (status.showsRuntime || isNowPlaying) && timeLabel?.isEmpty == false
    runtimeLabel.text = timeLabel
    runtimeBadge.isHidden = !showsRuntime

    let text = status.overlayBadgeText
    let symbol = status.badgeSymbol
    if text != nil || symbol != nil {
      badge.isHidden = false
      badgeLabel.text = text
      badgeIcon.isHidden = symbol == nil
      badgeIcon.image = symbol.flatMap { UIImage(systemName: $0) }
      badgeIconWidth.constant = symbol == nil ? 0 : Self.badgeIconSize
      // A symbol alone (the lock) sits in a circle the badge's height; with words it
      // leads them.
      let iconOnly = text == nil
      badgeIconLeading.constant = iconOnly ? (Self.badgeHeight - Self.badgeIconSize) / 2 : 4
      badgeLabelLeading.constant = iconOnly ? 0 : 5
      badgeLabelTrailing.constant = iconOnly ? -(Self.badgeHeight - Self.badgeIconSize) / 2 : -10
    } else {
      badge.isHidden = true
    }

    gradientLayer.isHidden = true
  }

}
#endif
