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
  public let alignment: Alignment

  public enum Alignment: Hashable, Sendable {
    case leading
    /// Pushed to the row's trailing edge, with every later chip after it — the sort
    /// pull-down sits apart from the filters.
    case trailing
  }

  public struct Option: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let isEnabled: Bool
    /// Drawn in the system's destructive style — "Reset Filters".
    public let isDestructive: Bool

    public init(id: String, title: String, isEnabled: Bool = true, isDestructive: Bool = false) {
      self.id = id
      self.title = title
      self.isEnabled = isEnabled
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
    /// Multi-select: a pick toggles and the menu stays open for the next one
    /// (`UIMenuElement.Attributes.keepsMenuPresented`).
    public let keepsPresented: Bool

    public init(nodes: [MenuNode], keepsPresented: Bool = false) {
      self.nodes = nodes
      self.keepsPresented = keepsPresented
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
              alignment: Alignment = .leading) {
    self.id = id
    self.title = title
    self.systemImage = systemImage
    self.menu = menu
    self.isActive = isActive
    self.alignment = alignment
  }
}

/// One entry in a section. A `.placeholder` is an exact-geometry skeleton for a section
/// whose data has not arrived; it takes the same cell shape so the swap is a repaint,
/// not a reflow.
public enum TVPageItem: Hashable {
  case card(MediaCard)
  case person(TVUIKitPerson)
  case chip(TVPageChip)
  case placeholder(Int)

  /// Stable within one section. Two sections can hold the same card, so the page
  /// keys items by (section, item) — see `TVPageItemID`.
  var localID: String {
    switch self {
    case .card(let card): return "card.\(card.id)"
    case .person(let person): return "person.\(person.id)"
    case .chip(let chip): return "chip.\(chip.id)"
    case .placeholder(let n): return "placeholder.\(n)"
    }
  }

  var card: MediaCard? {
    if case .card(let card) = self { return card }
    return nil
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

  public init(id: String,
              title: String?,
              count: String? = nil,
              kind: TVPageCellKind,
              flow: TVPageFlow = .rail,
              columns: Int,
              caption: TVPageCaption = .onFocus,
              rows: Int = 1,
              match: String? = nil,
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
                             cards: [MediaCard]) -> TVPageSection {
    TVPageSection(id: id, title: title, count: count, kind: .poster, flow: flow,
                  columns: columns, caption: caption, items: cards.map(TVPageItem.card))
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
                            cards: [MediaCard]) -> TVPageSection {
    TVPageSection(id: id, title: title, count: count, kind: .still, flow: flow,
                  columns: columns, caption: caption, items: cards.map(TVPageItem.card))
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

  public var isPlaceholder: Bool {
    items.allSatisfy { if case .placeholder = $0 { return true } else { return false } }
  }

  public func itemID(at index: Int) -> TVPageItemID {
    TVPageItemID(section: id, item: items[index].localID)
  }
}
#endif
