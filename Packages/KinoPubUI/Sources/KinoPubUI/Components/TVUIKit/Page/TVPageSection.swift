#if os(tvOS)
//
//  TVPageSection.swift
//  KinoPubUI
//
//  A tvOS page is a list of typed sections. The section says *what* it holds (one of
//  the system cell families, or chips), *how it flows* (a rail or a grid) and
//  *how many columns* the HIG grid should split the container into. Everything else —
//  card width, heights, insets, focus room — is derived in `TVPageLayout`.
//
//  There is deliberately no `HomeSection` / `SearchSection` / `LibrarySection`: a poster
//  rail on Watch Now and a poster rail on a person page are the same section with a
//  different id and title. The column count is the only per-surface knob, and it is a
//  number, so it can move without touching the component.
//

import Foundation
import UIKit

/// The cell family a section dequeues. Four system cells and one system control.
public enum TVPageCellKind: Hashable, Sendable {
  /// 2:3 art — `TVPosterView` lockup. Title in the system footer.
  case poster
  /// 1:1 art — the same `TVPosterView` lockup at a square aspect. Collection covers,
  /// festival and award tiles.
  case square
  /// 16:9 art — `TVMediaItemContentConfiguration.wideCell()`. Stills, episodes,
  /// trailers, Continue Watching, genre / category tiles, collections.
  case still
  /// A person — `TVMonogramContentConfiguration.cell()`.
  case person
  /// A text pill — system `UIButton` inside the cell. Tags, quick filters, suggestions,
  /// and pull-down filters when the chip carries a `menu`.
  case chip
  /// A `TVCardView` platter with a thumbnail and text beside it — the UIKit side of
  /// SwiftUI's `.card` button style. For rows where the words matter as much as the
  /// art: search's top results, where a title and a person sit side by side.
  case card
  /// The Home banner: large `TVCardView` platters in a rail. Where the row sits, and
  /// what each platter draws, is `TVPageBannerChrome`.
  case banner
  /// The Home hero: one full-screen carousel at the top of the page, Apple TV style —
  /// the backdrop behind the whole screen, the title's words and actions low on the
  /// left, the next row peeking under it. One item, a `TVPageHero`. Drawn by
  /// `TVPageHeroCell` over `TVPageHeroBackdropView`.
  case hero
  /// A full-width header that scrolls with the page. Focusable as one band so Up
  /// from the grid reaches person / collection detail. One item, a `TVPageMasthead`.
  case masthead
  /// A `TVCardView` platter drawn from a `TVPageInfoCard` — a score, a review, a fact, a
  /// mosaic of stills, a column of specifications. The HIG's "Cards": ratings and reviews
  /// for a media item, as a card with a header, content and a footer.
  case infoCard
  /// One row of titled groups that scroll together — Ratings | Reviews, Director | Cast,
  /// Stills | Facts, Type · Year · Country · Genre. The section's `groups` say what each
  /// holds; the cell of each item follows from the item, its size from its group's
  /// `columns`. Where the other kinds are one family of cells in a rail, this is a rail of
  /// families, and the only way a page puts two things side by side.
  case strip
}

public enum TVPageFlow: Hashable, Sendable {
  /// One row, scrolls horizontally inside the page (orthogonal section).
  case rail
  /// Wraps into rows, scrolls with the page.
  case grid
}

/// When a card's caption is drawn: the poster footer and the still's text line both
/// follow it. People always show their name — that is how the monogram cell is built.
public enum TVPageCaption: Hashable, Sendable {
  case onFocus
  case always
  case never
}

public struct TVPageChip: Identifiable, Hashable, Sendable {
  public let id: String
  public let title: String
  public let systemImage: String?
  /// When set, the chip is a pull-down: Select opens the system menu (`UIButton.menu`
  /// shown as the primary action) and a pick reports the option's id.
  public let menu: Menu?
  /// A filter that is narrowing the results — drawn filled, so a row of pull-downs says
  /// at a glance which of them are in play.
  public let isActive: Bool
  /// Off: drawn dimmed and skipped by focus — a filter the other picks rule out.
  public let isEnabled: Bool
  public let alignment: Alignment
  /// Off: an icon-only round button — the title is its accessibility label ("Reset
  /// Filters" as ×).
  public let showsTitle: Bool

  public enum Alignment: Hashable, Sendable {
    case leading
    /// Pushed to the row's trailing edge, with every later chip after it — the sort
    /// pull-down sits apart from the filters.
    case trailing
    /// The row's chips as one group in the middle. A collection's sort under a
    /// centered title.
    case center
  }

  public struct Option: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let isEnabled: Bool
    /// An SF Symbol beside the title — the trash can on "Reset Filters".
    public let systemImage: String?
    /// Red in the system menu — Delete Folder.
    public let isDestructive: Bool

    public init(id: String, title: String, isEnabled: Bool = true, systemImage: String? = nil,
                isDestructive: Bool = false) {
      self.id = id
      self.title = title
      self.isEnabled = isEnabled
      self.systemImage = systemImage
      self.isDestructive = isDestructive
    }
  }

  /// A pull-down's content as a tree, the shape `UIMenu` takes: options with a
  /// checkmark, inline sections, and submenus that show their current value as a
  /// subtitle — "Ratings ▸ Kinopoisk ▸ from / to".
  public indirect enum MenuNode: Hashable, Sendable {
    case option(Option, isSelected: Bool)
    /// A run of entries drawn in the menu itself; a title makes it a titled section,
    /// no title and it is part of the list (no divider above it).
    case section(title: String?, children: [MenuNode])
    case submenu(title: String, subtitle: String?, children: [MenuNode])
  }

  public struct Menu: Hashable, Sendable {
    public let nodes: [MenuNode]
    /// Multi-select: a pick toggles a checkmark in place and the menu stays open
    /// (`UIMenuElement.Attributes.keepsMenuPresented`); the whole selection is reported
    /// once, when the menu closes — the list under the finger does not rebuild or jump.
    public let keepsPresented: Bool
    /// The "all / any" option of a multi-select: picking it clears the rest, picking
    /// anything else clears it, and clearing the last pick brings it back.
    public let exclusiveOptionID: String?

    /// Options that only combine with their own group (option id → group). A pick from
    /// another group starts a new selection — "films" and "anime" are different axes
    /// on the server and cannot be one request.
    public let optionGroups: [String: Int]
    /// Groups whose options stand alone — presets: a pick is that option only, and
    /// picking it again clears it.
    public let soloGroups: Set<Int>

    public init(nodes: [MenuNode], keepsPresented: Bool = false, exclusiveOptionID: String? = nil,
                optionGroups: [String: Int] = [:], soloGroups: Set<Int> = []) {
      self.nodes = nodes
      self.keepsPresented = keepsPresented
      self.exclusiveOptionID = exclusiveOptionID
      self.optionGroups = optionGroups
      self.soloGroups = soloGroups
    }

    /// The checked option ids, anywhere in the tree.
    public var selectedIDs: Set<String> {
      func collect(_ nodes: [MenuNode]) -> [String] {
        nodes.flatMap { node -> [String] in
          switch node {
          case let .option(option, isSelected): return isSelected ? [option.id] : []
          case let .section(_, children), let .submenu(_, _, children): return collect(children)
          }
        }
      }
      return Set(collect(nodes))
    }

    /// The selection after tapping `id`, by the multi-select rules above.
    public func toggling(_ id: String, in selection: Set<String>) -> Set<String> {
      var next = selection
      if let all = exclusiveOptionID {
        if id == all { return [all] }
        next.remove(all)
      }
      let group = optionGroups[id]
      if let group, soloGroups.contains(group) {
        next = next.contains(id) ? [] : [id]
      } else {
        if next.contains(where: { optionGroups[$0] != group }) { next = [] }
        if next.contains(id) { next.remove(id) } else { next.insert(id) }
      }
      if next.isEmpty, let all = exclusiveOptionID { return [all] }
      return next
    }

    /// A flat single-select list.
    public init(options: [Option], selectedID: String?) {
      self.init(nodes: options.map { .option($0, isSelected: $0.id == selectedID) })
    }
  }

  public init(id: String,
              title: String,
              systemImage: String? = nil,
              menu: Menu? = nil,
              isActive: Bool = false,
              isEnabled: Bool = true,
              alignment: Alignment = .leading,
              showsTitle: Bool = true) {
    self.id = id
    self.title = title
    self.systemImage = systemImage
    self.menu = menu
    self.isActive = isActive
    self.isEnabled = isEnabled
    self.alignment = alignment
    self.showsTitle = showsTitle
  }
}

/// A tile whose artwork is drawn rather than loaded — genres, categories, sub-sections,
/// the "See All" entry that opens a row's full list. It takes the cell of the section
/// it sits in (a still, a square, a poster), so a genre rail and a row of posters are
/// the same collection with different items. The name is the tile's caption, in the
/// system's text line under the art, not painted into the bitmap.
public struct TVPageTile: Identifiable, Hashable {
  public let id: String
  public let title: String
  public let symbol: String?
  /// Nil takes a stable colour from the title (`TVUIKitTileArtwork.tint(for:)`).
  public let tint: UIColor?
  public let style: TVUIKitTileArtwork.Style
  /// A logo drawn over the tint once it loads — a TV channel's card. Whole, never
  /// cropped: its edges are carried out to the tile (`TVUIKitTileArtwork.letterboxed`).
  public let logoURL: URL?
  /// A second line under the name, in the still cell's secondary text — what a channel
  /// has on air.
  public let subtitle: String?

  public init(id: String, title: String, symbol: String? = nil, tint: UIColor? = nil,
              style: TVUIKitTileArtwork.Style = .gradient, logoURL: URL? = nil,
              subtitle: String? = nil) {
    self.id = id
    self.title = title
    self.subtitle = subtitle
    self.symbol = symbol
    self.tint = tint
    self.style = style
    self.logoURL = logoURL
  }

  public var resolvedTint: UIColor { tint ?? TVUIKitTileArtwork.tint(for: title) }
}

public extension TVUIKitMediaItem {
  /// A drawn tile in the still cell: the tint is the artwork (until a logo, if there is
  /// one, loads over it), and the name is the caption line.
  init(tile: TVPageTile) {
    self.init(id: tile.id.hashValue,
              imageURL: tile.logoURL,
              tint: tile.resolvedTint,
              symbol: tile.symbol,
              tileStyle: tile.style,
              caption: tile.title,
              detail: tile.subtitle,
              status: .unavailable,
              artworkFit: .letterbox)
  }
}

/// One title in the banner: its card and the title-logo slot (pending / URL / miss).
public struct TVPageFeature: Hashable {
  public let card: MediaCard
  public let logo: TitleLogoResolution
  /// The textless wide frame from the worker's image route. Tried first; a 404 there
  /// falls back to the card's own kino.pub wide still (`card.backdropImageURL`), never
  /// to the portrait poster.
  public let backdrop: URL?
  /// Play as the detail page draws it for this title (`MediaActionCatalog.play`: the
  /// label, the resume bar, Replay); nil until the title's details are in, when the
  /// hero shows plain Play.
  public let play: MediaActionAppearance?
  /// The title is in at least one bookmark folder (the glyph fills, as on the detail page).
  public let isBookmarked: Bool

  public var logoURL: URL? { logo.url }

  /// The backdrop chain, first that loads wins.
  public var backdropCandidates: [URL] {
    var seen = Set<String>()
    var ordered: [URL?] = [backdrop]
    if card.hasSpecifiedWideArtwork || !(card.backdropURL ?? "").isEmpty {
      ordered.append(URL(string: card.backdropURL ?? card.landscapeImageURL ?? ""))
    }
    return ordered
      .compactMap { $0 }
      .filter { !$0.absoluteString.isEmpty && seen.insert($0.absoluteString).inserted }
  }

  public init(card: MediaCard, logo: TitleLogoResolution = .missing, backdrop: URL? = nil,
              play: MediaActionAppearance? = nil, isBookmarked: Bool = false) {
    self.card = card
    self.logo = logo
    self.backdrop = backdrop
    self.play = play
    self.isBookmarked = isBookmarked
  }

  public init(card: MediaCard, logoURL: URL?) {
    self.card = card
    self.logo = logoURL.map { .url($0) } ?? .missing
    self.backdrop = nil
    self.play = nil
    self.isBookmarked = false
  }
}

/// What the hero carousel shows: its titles, in order, and the words on its buttons.
/// The words come from the app — this package has no localization tables.
public struct TVPageHero: Hashable {
  public struct Labels: Hashable {
    public let play: String
    public let details: String
    /// The Bookmark menu's heading, as on the detail page.
    public let bookmark: String
    public let next: String
    /// The Bookmark menu's line when there are no folders yet.
    public let noBookmarkFolders: String

    public init(play: String, details: String, bookmark: String, next: String,
                noBookmarkFolders: String = "") {
      self.play = play
      self.details = details
      self.bookmark = bookmark
      self.next = next
      self.noBookmarkFolders = noBookmarkFolders
    }
  }

  public let features: [TVPageFeature]
  public let labels: Labels

  public init(features: [TVPageFeature], labels: Labels) {
    self.features = features
    self.labels = labels
  }
}

/// The block at the top of a catalog page, in the same collection as the grid so it
/// scrolls away with it. One focus stop: a person shows name / role at rest and opens
/// the biography when focused; a collection is the title plus the stats strip. The
/// avatar image is not a separate control — the cell is.
public struct TVPageMasthead: Hashable, Sendable {
  public enum Style: Hashable, Sendable {
    case person
    case collection
  }

  public struct Stat: Hashable, Sendable {
    public let value: String
    public let caption: String

    public init(value: String, caption: String) {
      self.value = value
      self.caption = caption
    }
  }

  public let style: Style
  public let title: String
  /// A second line under the name — an original name, when one exists.
  public let subtitle: String?
  /// Role, place, age. One line.
  public let detail: String?
  /// Prose under the detail line. Empty until a biography is known; the cell opens
  /// it only when focused, so a late metadata paint does not shove the grid.
  public let biography: String?
  public let photoURL: URL?
  /// SF Symbol above a collection title. No plate behind it.
  public let symbolName: String?
  public let stats: [Stat]

  public init(style: Style,
              title: String,
              subtitle: String? = nil,
              detail: String? = nil,
              biography: String? = nil,
              photoURL: URL? = nil,
              symbolName: String? = nil,
              stats: [Stat] = []) {
    self.style = style
    self.title = title
    self.subtitle = subtitle
    self.detail = detail
    self.biography = biography
    self.photoURL = photoURL
    self.symbolName = symbolName
    self.stats = stats
  }
}

/// One entry in a section. A `.placeholder` is an exact-geometry skeleton for a section
/// whose data has not arrived; it takes the same cell shape so the swap is a repaint,
/// not a reflow.
public enum TVPageItem: Hashable {
  case card(MediaCard)
  case person(TVUIKitPerson)
  case chip(TVPageChip)
  /// Drawn artwork, no photograph: a genre, a category, a "See All" entry.
  case tile(TVPageTile)
  /// A banner title — see `TVPageCellKind.banner`.
  case feature(TVPageFeature)
  /// The whole hero carousel — see `TVPageCellKind.hero`. One per section.
  case hero(TVPageHero)
  /// The scrolling header. One per section.
  case masthead(TVPageMasthead)
  /// A card of the `infoCard` family.
  case info(TVPageInfoCard)
  /// The title over one group of a strip. Not a control: focus skips it.
  case groupTitle(id: String, text: String)
  case placeholder(Int)

  /// Stable within one section. Two sections can hold the same card, so the page
  /// keys items by (section, item) — see `TVPageItemID`.
  var localID: String {
    switch self {
    case .card(let card): return "card.\(card.id)"
    case .person(let person): return "person.\(person.id)"
    case .chip(let chip): return "chip.\(chip.id)"
    case .tile(let tile): return "tile.\(tile.id)"
    case .feature(let feature): return "feature.\(feature.card.id)"
    case .hero: return "hero"
    case .masthead: return "masthead"
    case .info(let card): return "info.\(card.id)"
    case .groupTitle(let id, _): return "title.\(id)"
    case .placeholder(let n): return "placeholder.\(n)"
    }
  }

  public var card: MediaCard? {
    switch self {
    case .card(let card): return card
    case .feature(let feature): return feature.card
    default: return nil
    }
  }
}

/// Which cell registration a page item dequeues. Part of `TVPageItemID` so a title
/// that moves from a poster grid to a still grid (Library Following → Continue) is a
/// new identity and is reloaded, not reconfigured into a different cell class.
public enum TVPageRegistration: Hashable, Sendable {
  case poster, still, person, chip, card, banner, hero, masthead, groupTitle
  case rating, reviews, review, fact, gallery, spec, track
}

/// Diffable identity of one item on one page: the same title in Up Next and in Hot
/// Series is two cells, and the data source must never see one id twice. `registration`
/// is the cell class — it must be a stable function of this id, or `reconfigureItems`
/// dequeues the wrong registration (`NSInternalInconsistencyException`).
public struct TVPageItemID: Hashable, Sendable {
  public let section: String
  public let item: String
  public let registration: TVPageRegistration

  public init(section: String, item: String, registration: TVPageRegistration) {
    self.section = section
    self.item = item
    self.registration = registration
  }
}

/// One titled part of a `.strip` row: its own heading over its own cards, sized by its own
/// column count — the Ratings of "Ratings | Reviews".
public struct TVPageGroup: Identifiable, Hashable {
  public let id: String
  /// The heading over the group. Nil: the group is just its cards, and a strip made only
  /// of such groups sits where an untitled row does.
  public let title: String?
  /// The HIG column count that sizes this group's cards, like a section's `columns`.
  public let columns: Int
  public let items: [TVPageItem]
  /// The title is a subheading — smaller, because the strip has a heading of its own
  /// ("Director" and "Starring" under "Cast & Crew") — not the row's title.
  public let isSubheading: Bool
  /// What this group's titles are drawn as. Nil lets each item say (an info card, a person,
  /// a pill; a title is search's wide card). `.poster` draws them as the 2:3 lockup every
  /// poster rail uses — same recipe, same gutter — and its skeleton tiles too.
  public let cell: TVPageCellKind?
  /// The group is **one column** (Sasha, 2026-10-11): its cards stand one under another, each as
  /// wide as one of `columns` equal columns that share the content width, a gutter apart, with the
  /// groups beside it. The table under the page and the credits as text — three columns, and a
  /// card to each item in them, so focus moves from item to item and not over a column taller than
  /// the screen. A column that is not there leaves its width empty.
  public let stacked: Bool
  /// Stacked columns of like cards that read as one grid — a setlist: the same air between
  /// columns as between the cards of a column (`gridGap`), instead of a gutter beside and a
  /// sliver under. Nil: the table's spacing.
  public let gridGap: CGFloat?

  /// A gutter and a half narrower than the columns' gutter, across and down alike
  /// (Sasha, 2026-10-25).
  public static let gridGap: CGFloat = (TVHIGGrid.gutter / 1.5).rounded()

  public init(id: String, title: String?, columns: Int, subheading: Bool = false,
              cell: TVPageCellKind? = nil, stacked: Bool = false, gridGap: CGFloat? = nil,
              items: [TVPageItem]) {
    self.id = id
    self.title = title
    self.columns = columns
    self.isSubheading = subheading
    self.cell = cell
    self.stacked = stacked
    self.gridGap = gridGap
    self.items = items
  }
}

public struct TVPageSection: Identifiable, Hashable {
  public let id: String
  public let title: String?
  /// Beside the title in secondary type — how many items the section stands for.
  public let count: String?
  public let kind: TVPageCellKind
  public let flow: TVPageFlow
  /// The card size, stated as the HIG column count at 1920 — 6 for posters (260),
  /// 5 for stills (320), 4 for featured stills (410), 3 for large ones (560). The
  /// layout fits as many of that size as the container holds and stretches them to
  /// fill: a classic collection with fixed insets and gutters, not a pinned width.
  public let columns: Int
  public let caption: TVPageCaption
  public let items: [TVPageItem]
  /// Rows a rail stacks before it scrolls sideways — search's wide cards run two deep.
  public let rows: Int
  /// The text the page was searched for. A card whose original title holds it shows
  /// that title too, so a match on "The Matrix" under "Матрица" explains itself.
  public let match: String?
  /// A grid with more pages to come: the page pads its last row with skeleton tiles and
  /// shows a spinner under it, so the end of what is loaded never reads as the end.
  public let loadsMore: Bool
  /// Posters and squares carry the title's score in a corner chip. Off by default: a
  /// row decides whether a number is what the user is choosing by.
  public let showsRating: Bool
  /// A strip's groups; empty for every other kind. `items` is these, flattened — each
  /// group's title, then its cards — so the page's one diffable list holds a strip like
  /// any other section.
  public let groups: [TVPageGroup]
  /// Trailing chips on the section header — sort / filter, Following's Unwatched/All
  /// switch, or a folder's ellipsis menu. Same `TVPageChip` the Search filter row uses.
  public let headerActions: [TVPageChip]
  /// Genre ids this section already is, so a cover's caption names the next one
  /// instead of «Документальный» / «Аниме» / «Мультфильм» on every poster.
  public let omittedCaptionGenreIDs: Set<String>

  public init(id: String,
              title: String?,
              count: String? = nil,
              kind: TVPageCellKind,
              flow: TVPageFlow = .rail,
              columns: Int,
              caption: TVPageCaption = .onFocus,
              rows: Int = 1,
              match: String? = nil,
              loadsMore: Bool = false,
              showsRating: Bool = false,
              groups: [TVPageGroup] = [],
              headerActions: [TVPageChip] = [],
              omittedCaptionGenreIDs: Set<String> = [],
              items: [TVPageItem]) {
    self.id = id
    self.title = title
    self.count = count
    self.kind = kind
    self.flow = flow
    self.columns = columns
    self.caption = caption
    self.rows = max(rows, 1)
    self.match = match
    self.loadsMore = loadsMore
    self.showsRating = showsRating
    self.groups = groups
    self.headerActions = headerActions
    self.omittedCaptionGenreIDs = omittedCaptionGenreIDs
    self.items = items
  }

  // MARK: - Templates

  /// 2:3 posters, 6 across by default (HIG 260 at 1920).
  ///
  /// **Captions follow the shape** (Sasha, 2026-10-06): a *rail* — Watch Now, Movies, Series,
  /// the shelves under a detail page — has no title or year under its covers, not even on
  /// focus (`.never`, no footer in the lockup); a *grid* — a catalog, a collection, a
  /// profile's credits, the Library — names every cover (`.always`). Pass `caption` to say
  /// otherwise (search's shelves do).
  public static func posters(id: String,
                             title: String?,
                             count: String? = nil,
                             columns: Int = 6,
                             flow: TVPageFlow = .rail,
                             caption: TVPageCaption? = nil,
                             loadsMore: Bool = false,
                             showsRating: Bool = false,
                             headerActions: [TVPageChip] = [],
                             omittedCaptionGenreIDs: Set<String> = [],
                             cards: [MediaCard]) -> TVPageSection {
    TVPageSection(id: id, title: title, count: count, kind: .poster, flow: flow,
                  columns: columns, caption: caption ?? (flow == .grid ? .always : .never),
                  loadsMore: loadsMore, showsRating: showsRating,
                  headerActions: headerActions, omittedCaptionGenreIDs: omittedCaptionGenreIDs,
                  items: cards.map(TVPageItem.card))
  }

  /// 1:1 art in the poster lockup, 6 across by default — collection covers, awards.
  public static func squares(id: String,
                             title: String?,
                             count: String? = nil,
                             columns: Int = 6,
                             flow: TVPageFlow = .rail,
                             caption: TVPageCaption = .onFocus,
                             items: [TVPageItem]) -> TVPageSection {
    TVPageSection(id: id, title: title, count: count, kind: .square, flow: flow,
                  columns: columns, caption: caption, items: items)
  }

  /// Drawn tiles in the 16:9 still cell — genres, categories. 4 across by default:
  /// a name has to read from the sofa.
  public static func tiles(id: String,
                           title: String?,
                           count: String? = nil,
                           columns: Int = 4,
                           flow: TVPageFlow = .rail,
                           tiles: [TVPageTile]) -> TVPageSection {
    TVPageSection(id: id, title: title, count: count, kind: .still, flow: flow,
                  columns: columns, caption: .always, items: tiles.map(TVPageItem.tile))
  }

  /// 16:9 stills with the system's text lines underneath — Up Next, episodes,
  /// trailers, categories, collections. 5 across by default (HIG 320 at 1920);
  /// 4 (410) reads as "featured".
  public static func stills(id: String,
                            title: String?,
                            count: String? = nil,
                            columns: Int = 5,
                            flow: TVPageFlow = .rail,
                            caption: TVPageCaption = .onFocus,
                            loadsMore: Bool = false,
                            headerActions: [TVPageChip] = [],
                            cards: [MediaCard]) -> TVPageSection {
    TVPageSection(id: id, title: title, count: count, kind: .still, flow: flow,
                  columns: columns, caption: caption, loadsMore: loadsMore,
                  headerActions: headerActions, items: cards.map(TVPageItem.card))
  }

  public static func people(id: String,
                            title: String?,
                            count: String? = nil,
                            columns: Int = 8,
                            people: [TVUIKitPerson]) -> TVPageSection {
    TVPageSection(id: id, title: title, count: count, kind: .person, flow: .rail,
                  columns: columns, caption: .always, items: people.map(TVPageItem.person))
  }

  /// Wide text cards, 3 across by default (HIG 560 at 1920): a title's poster
  /// thumbnail or a person's circle, with the words beside it.
  public static func cards(id: String,
                           title: String?,
                           count: String? = nil,
                           columns: Int = 3,
                           rows: Int = 1,
                           match: String? = nil,
                           omittedCaptionGenreIDs: Set<String> = [],
                           items: [TVPageItem]) -> TVPageSection {
    TVPageSection(id: id, title: title, count: count, kind: .card, flow: .rail,
                  columns: columns, caption: .always, rows: rows, match: match,
                  omittedCaptionGenreIDs: omittedCaptionGenreIDs, items: items)
  }

  /// The Home banner: large platters, untitled. Each title once (Sasha, 2026-10-01).
  /// The row matches the other rails unless `TVPageBannerChrome.row` says centred.
  public static func banner(id: String, features: [TVPageFeature]) -> TVPageSection {
    TVPageSection(id: id, title: nil, kind: .banner, flow: .rail, columns: 2,
                  caption: .always, items: features.map(TVPageItem.feature))
  }

  /// The Home hero carousel: the page's first section, untitled, one item.
  public static func hero(id: String, _ hero: TVPageHero) -> TVPageSection {
    TVPageSection(id: id, title: nil, kind: .hero, flow: .rail, columns: 1,
                  caption: .never, items: [.hero(hero)])
  }

  /// The scrolling header above a catalog. Focusable so Up from the grid reaches it;
  /// entry focus still prefers the first poster when the page asks for that.
  public static func masthead(id: String, _ masthead: TVPageMasthead) -> TVPageSection {
    TVPageSection(id: id, title: nil, kind: .masthead, flow: .rail, columns: 1,
                  caption: .never, items: [.masthead(masthead)])
  }

  /// Titled groups side by side in one rail: the row scrolls as one, so Right from the
  /// last score is the first review. `Ratings | Reviews`, `Stills | Facts`.
  ///
  /// `title` is a heading over the whole row, outside the part that scrolls — "Cast &
  /// Crew" over Director | Starring. The groups' own titles are the row's titles unless a
  /// group says it is a subheading (`TVPageGroup.isSubheading`), which is how a heading
  /// above sets them smaller.
  public static func strip(id: String, title: String? = nil, groups: [TVPageGroup]) -> TVPageSection {
    let items = groups.flatMap { group -> [TVPageItem] in
      (group.title.map { [TVPageItem.groupTitle(id: group.id, text: $0)] } ?? []) + group.items
    }
    return TVPageSection(id: id, title: title, kind: .strip, flow: .rail, columns: 0,
                         caption: .always, groups: groups, items: items)
  }

  public static func chips(id: String,
                           title: String?,
                           chips: [TVPageChip]) -> TVPageSection {
    TVPageSection(id: id, title: title, kind: .chip, flow: .rail,
                  columns: 0, caption: .always, items: chips.map(TVPageItem.chip))
  }

  /// The same section with skeleton tiles in place of data — for a page that knows its
  /// shape (which rows, which kind, how many columns) before the rows arrive.
  public static func placeholder(id: String,
                                 title: String?,
                                 kind: TVPageCellKind,
                                 columns: Int,
                                 flow: TVPageFlow = .rail,
                                 count: Int? = nil) -> TVPageSection {
    let tiles = count ?? (flow == .rail ? columns + 1 : columns * 2)
    return TVPageSection(id: id, title: title, kind: kind, flow: flow, columns: columns,
                         caption: .never, headerActions: [], items: (0..<tiles).map(TVPageItem.placeholder))
  }

  /// Trailing header chips without rebuilding the section's items.
  public func withHeaderActions(_ actions: [TVPageChip]) -> TVPageSection {
    TVPageSection(id: id, title: title, count: count, kind: kind, flow: flow, columns: columns,
                  caption: caption, rows: rows, match: match, loadsMore: loadsMore,
                  showsRating: showsRating, groups: groups, headerActions: actions,
                  omittedCaptionGenreIDs: omittedCaptionGenreIDs, items: items)
  }

  /// The same section with `count` skeleton tiles after its items.
  func appendingPlaceholders(_ count: Int) -> TVPageSection {
    TVPageSection(id: id, title: title, count: self.count, kind: kind, flow: flow, columns: columns,
                  caption: caption, rows: rows, match: match, loadsMore: loadsMore,
                  showsRating: showsRating, groups: groups, headerActions: headerActions,
                  omittedCaptionGenreIDs: omittedCaptionGenreIDs,
                  items: items + (0..<count).map(TVPageItem.placeholder))
  }

  /// Drops later items that would share a `TVPageItemID` with an earlier one. The
  /// collection's snapshot cannot hold a duplicate identifier.
  func uniquedItems() -> TVPageSection {
    var seen = Set<TVPageItemID>()
    if kind == .strip {
      let groups = self.groups.map { group in
        TVPageGroup(id: group.id, title: group.title, columns: group.columns,
                    subheading: group.isSubheading, cell: group.cell, stacked: group.stacked,
                    gridGap: group.gridGap,
                    items: group.items.filter { item in
                      let id = TVPageItemID(section: self.id,
                                            item: "\(group.id)/\(item.localID)",
                                            registration: Self.registration(of: item, groupCell: group.cell))
                      return seen.insert(id).inserted
                    })
      }
      return .strip(id: id, title: title, groups: groups)
    }
    let kept = items.indices.compactMap { index -> TVPageItem? in
      let id = itemID(at: index)
      return seen.insert(id).inserted ? items[index] : nil
    }
    return TVPageSection(id: id, title: title, count: count, kind: kind, flow: flow, columns: columns,
                         caption: caption, rows: rows, match: match, loadsMore: loadsMore,
                         showsRating: showsRating, groups: groups, headerActions: headerActions,
                         omittedCaptionGenreIDs: omittedCaptionGenreIDs, items: kept)
  }

  /// The cell registration this item dequeues. Stable for a given item in a given
  /// section — the data source keys cells by `TVPageItemID.registration`.
  public func registration(at index: Int) -> TVPageRegistration {
    guard items.indices.contains(index) else { return .chip }
    if kind == .strip, let (group, _) = stripGroup(ofItem: index) {
      return Self.registration(of: items[index], groupCell: groups[group].cell)
    }
    return Self.registration(of: items[index], sectionKind: kind)
  }

  private static func registration(of item: TVPageItem, groupCell: TVPageCellKind?) -> TVPageRegistration {
    switch item {
    case .info(let info): return info.registration
    case .groupTitle: return .groupTitle
    case .chip: return .chip
    // A person in a strip is search's wide card — avatar, name, role — as it was before
    // dequeue went by registration. The round person lockup is sized to the column, and a
    // third of the screen made the portraits ~500 pt across, over the row below
    // (Sasha, 2026-10-11).
    case .person: return groupCell == .person ? .person : .card
    case .masthead: return .masthead
    case .feature: return .banner
    case .hero: return .hero
    case .tile: return .still
    case .card, .placeholder:
      return groupCell == .poster ? .poster : .card
    }
  }

  private static func registration(of item: TVPageItem, sectionKind: TVPageCellKind) -> TVPageRegistration {
    switch item {
    case .info(let info): return info.registration
    case .groupTitle: return .groupTitle
    case .chip: return .chip
    // Among search's top cards a person is the same wide card as Cast & Crew's: the round
    // lockup is sized to the column, and a third of the screen drew a face ~500 pt across
    // over the row below (Sasha, 2026-10-25). Only a row of people is a row of lockups.
    case .person: return sectionKind == .person ? .person : .card
    case .masthead: return .masthead
    case .feature: return .banner
    case .hero: return .hero
    case .tile:
      switch sectionKind {
      case .poster, .square: return .poster
      default: return .still
      }
    case .card, .placeholder:
      return registration(for: sectionKind)
    }
  }

  static func registration(for kind: TVPageCellKind) -> TVPageRegistration {
    switch kind {
    case .poster, .square: return .poster
    case .still: return .still
    case .person: return .person
    case .chip: return .chip
    case .card: return .card
    case .banner: return .banner
    case .hero: return .hero
    case .masthead: return .masthead
    case .infoCard: return .spec
    case .strip: return .card
    }
  }

  /// For an item of a strip: which group it is in, and where that group's title sits
  /// among `items` (nil for an untitled group). Nil for any other kind of section.
  func stripGroup(ofItem index: Int) -> (group: Int, title: Int?)? {
    guard kind == .strip, items.indices.contains(index) else { return nil }
    var start = 0
    for (position, group) in groups.enumerated() {
      let hasTitle = group.title != nil
      let count = (hasTitle ? 1 : 0) + group.items.count
      if index < start + count { return (position, hasTitle ? start : nil) }
      start += count
    }
    return nil
  }

  /// What the group of an item of a strip draws its titles as (`TVPageGroup.cell`).
  func stripCell(ofItem index: Int) -> TVPageCellKind? {
    guard let (group, _) = stripGroup(ofItem: index) else { return nil }
    return groups[group].cell
  }

  /// Items that are data, not skeleton tiles.
  var loadedCount: Int {
    items.reduce(0) { count, item in
      if case .placeholder = item { return count } else { return count + 1 }
    }
  }

  public var isPlaceholder: Bool {
    items.allSatisfy { if case .placeholder = $0 { return true } else { return false } }
  }

  public func itemID(at index: Int) -> TVPageItemID {
    // A strip is several groups in one list, and two of them can hold the same title or
    // the same run of skeleton tiles: the group says which is which. `registration` is
    // the cell class — it must travel with the id so reconfigure cannot dequeue another.
    let registration = registration(at: index)
    if let (group, _) = stripGroup(ofItem: index) {
      return TVPageItemID(section: id, item: "\(groups[group].id)/\(items[index].localID)",
                          registration: registration)
    }
    return TVPageItemID(section: id, item: items[index].localID, registration: registration)
  }
}
#endif
