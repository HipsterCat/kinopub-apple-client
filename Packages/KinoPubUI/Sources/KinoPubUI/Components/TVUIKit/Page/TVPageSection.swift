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
  /// A large `TVCardView` platter whose art is the title's backdrop, with its logo (or
  /// name), plot, scores, genre and running time over the bottom and the poster inset
  /// at the trailing edge. The Home banner; items are `.feature`.
  case banner
  /// A full-width header that scrolls with the page. Not focusable. One item, a
  /// `TVPageMasthead`: a person's photo and text, or a collection's title and stats.
  case masthead
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

    public init(id: String, title: String, isEnabled: Bool = true, systemImage: String? = nil) {
      self.id = id
      self.title = title
      self.isEnabled = isEnabled
      self.systemImage = systemImage
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

  public init(id: String, title: String, symbol: String? = nil, tint: UIColor? = nil,
              style: TVUIKitTileArtwork.Style = .gradient) {
    self.id = id
    self.title = title
    self.symbol = symbol
    self.tint = tint
    self.style = style
  }

  public var resolvedTint: UIColor { tint ?? TVUIKitTileArtwork.tint(for: title) }
}

public extension TVUIKitMediaItem {
  /// A drawn tile in the still cell: no image URL, so the tint is the artwork, and the
  /// name is the caption line.
  init(tile: TVPageTile) {
    self.init(id: tile.id.hashValue,
              tint: tile.resolvedTint,
              symbol: tile.symbol,
              tileStyle: tile.style,
              caption: tile.title,
              status: .unavailable)
  }
}

/// One title in a banner row: its card, the title logo when external metadata has
/// one, and which lap of the looped row this copy sits in.
public struct TVPageFeature: Hashable {
  public let card: MediaCard
  public let logoURL: URL?
  public let lap: Int

  public init(card: MediaCard, logoURL: URL? = nil, lap: Int = 0) {
    self.card = card
    self.logoURL = logoURL
    self.lap = lap
  }
}

/// The block at the top of a catalog page, in the same collection as the grid so it
/// scrolls away with it. A person leaves room under the name for a biography that may
/// arrive later; a collection is a centered title and the counts the payload actually
/// has. The avatar is not a control — nothing in this block is focusable.
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
  /// Prose under the detail line. Empty until a biography is known; the cell grows
  /// when it is set, so the grid below is not drawn on top of it.
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
  /// The scrolling header. One per section.
  case masthead(TVPageMasthead)
  case placeholder(Int)

  /// Stable within one section. Two sections can hold the same card, so the page
  /// keys items by (section, item) — see `TVPageItemID`.
  var localID: String {
    switch self {
    case .card(let card): return "card.\(card.id)"
    case .person(let person): return "person.\(person.id)"
    case .chip(let chip): return "chip.\(chip.id)"
    case .tile(let tile): return "tile.\(tile.id)"
    case .feature(let feature): return "feature.\(feature.lap).\(feature.card.id)"
    case .masthead: return "masthead"
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

/// Diffable identity of one item on one page: the same title in Up Next and in Hot
/// Series is two cells, and the data source must never see one id twice.
public struct TVPageItemID: Hashable, Sendable {
  public let section: String
  public let item: String
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
  /// The item focus starts on when the page first appears — the middle lap of a looped
  /// banner row, so it can be scrolled either way.
  public let startIndex: Int

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
              startIndex: Int = 0,
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
    self.startIndex = startIndex
    self.items = items
  }

  // MARK: - Templates

  /// 2:3 posters, 6 across by default (HIG 260 at 1920).
  public static func posters(id: String,
                             title: String?,
                             count: String? = nil,
                             columns: Int = 6,
                             flow: TVPageFlow = .rail,
                             caption: TVPageCaption = .onFocus,
                             loadsMore: Bool = false,
                             showsRating: Bool = false,
                             cards: [MediaCard]) -> TVPageSection {
    TVPageSection(id: id, title: title, count: count, kind: .poster, flow: flow,
                  columns: columns, caption: caption, loadsMore: loadsMore,
                  showsRating: showsRating, items: cards.map(TVPageItem.card))
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
                            cards: [MediaCard]) -> TVPageSection {
    TVPageSection(id: id, title: title, count: count, kind: .still, flow: flow,
                  columns: columns, caption: caption, loadsMore: loadsMore,
                  items: cards.map(TVPageItem.card))
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
                           items: [TVPageItem]) -> TVPageSection {
    TVPageSection(id: id, title: title, count: count, kind: .card, flow: .rail,
                  columns: columns, caption: .always, rows: rows, match: match, items: items)
  }

  /// The Home banner: large platters, 2 across (HIG 2-column at 1920), untitled. The
  /// titles repeat for `laps` laps and focus starts in the middle one, so the row
  /// reads as endless in both directions — a carousel, not a list with an end.
  public static func banner(id: String,
                            features: [TVPageFeature],
                            columns: Int = 2,
                            laps: Int = 41) -> TVPageSection {
    let laps = features.count > columns ? max(laps, 1) : 1
    let items = (0..<laps).flatMap { lap in
      features.map { TVPageItem.feature(TVPageFeature(card: $0.card, logoURL: $0.logoURL, lap: lap)) }
    }
    return TVPageSection(id: id, title: nil, kind: .banner, flow: .rail, columns: columns,
                         caption: .always, startIndex: features.count * (laps / 2), items: items)
  }

  /// The scrolling header above a catalog. Not focusable; the grid under it is.
  public static func masthead(id: String, _ masthead: TVPageMasthead) -> TVPageSection {
    TVPageSection(id: id, title: nil, kind: .masthead, flow: .rail, columns: 1,
                  caption: .never, items: [.masthead(masthead)])
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
                         caption: .never, items: (0..<tiles).map(TVPageItem.placeholder))
  }

  /// The same section with `count` skeleton tiles after its items.
  func appendingPlaceholders(_ count: Int) -> TVPageSection {
    TVPageSection(id: id, title: title, count: self.count, kind: kind, flow: flow, columns: columns,
                  caption: caption, rows: rows, match: match, loadsMore: loadsMore,
                  showsRating: showsRating, startIndex: startIndex,
                  items: items + (0..<count).map(TVPageItem.placeholder))
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
    TVPageItemID(section: id, item: items[index].localID)
  }
}
#endif
