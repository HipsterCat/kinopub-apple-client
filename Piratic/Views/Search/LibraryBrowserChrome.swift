//
//  LibraryBrowserChrome.swift
//  Piratic
//
//  Catalog / listing chrome: layout Menu (grid/list), Filters button, separate
//  Sort menu (arrows, trailing), and Notes-style count for `.navigationSubtitle`
//  under the title (Catalog and category screens — not the empty Search root).
//  Sort also lives in the Filter & Sort sheet (field + direction).
//

import SwiftUI
import PiraticUI
import KinoPubBackend

#if !os(tvOS)

/// Notes-style count under the page title («Всего 54 593», «Найдено 145 — 2 фильтра»).
enum LibraryBrowserSubtitle {
  static func text(resultCount: Int?,
                   isLoading: Bool,
                   isSearching: Bool,
                   activeFilterCount: Int) -> String {
    if isLoading {
      return String(localized: resultCount == nil ? "Loading" : "Updating")
    }
    guard let resultCount else { return "" }
    let formatted = resultCount.formatted(.number.grouping(.automatic))
    if isSearching {
      if activeFilterCount > 0 {
        return String(format: String(localized: "Catalog_FoundWithFilters"),
                      formatted, activeFilterCount)
      }
      return String(format: String(localized: "Catalog_Found"), formatted)
    }
    return String(format: String(localized: "Catalog_Total"), formatted)
  }

  @MainActor
  static func text(for catalog: LibraryCatalog) -> String {
    text(resultCount: catalog.resultCount,
         isLoading: catalog.isLoading,
         isSearching: catalog.isSearching,
         activeFilterCount: catalog.filter.activeFilterCount)
  }
}

/// Trailing toolbar Menu: posters / list only. Sort is a separate control.
struct LibraryViewOptionsMenu: View {
  @AppStorage(MediaGridLayout.storageKey) private var layoutRaw = MediaGridLayout.posters.rawValue

  private var currentLayout: MediaGridLayout { MediaGridLayout.resolved(from: layoutRaw) }

  var body: some View {
    Menu {
      Picker(selection: layoutBinding) {
        ForEach(MediaGridLayout.allCases) { layout in
          Label(LocalizedStringKey(layout.titleKey), systemImage: layout.systemImage)
            .tag(layout.rawValue)
        }
      } label: {
        Text("View Options")
      }
      .pickerStyle(.inline)
    } label: {
      Label(LocalizedStringKey(currentLayout.titleKey), systemImage: currentLayout.systemImage)
        .labelStyle(.iconOnly)
    }
    .help(Text(LocalizedStringKey(currentLayout.titleKey)))
    .accessibilityLabel(Text("View Options"))
  }

  private var layoutBinding: Binding<String> {
    Binding(
      get: { MediaGridLayout.resolved(from: layoutRaw).rawValue },
      set: { layoutRaw = $0 }
    )
  }
}

/// Sort as its own trailing toolbar Menu — `arrow.up.arrow.down`, far right.
/// No nested `.glass` / `.bordered` (toolbar Liquid Glass is the system’s).
struct LibrarySortMenu<Catalog: FilterBarDriver>: View {
  @ObservedObject var catalog: Catalog
  var showsTitle = true

  var body: some View {
    Menu {
      Picker(selection: sortBinding) {
        ForEach(MediaSortOrder.allCases) { order in
          Text(LocalizedStringKey(order.titleKey)).tag(order)
        }
      } label: {
        Text("Sort_By")
      }
      .pickerStyle(.inline)

      Button {
        catalog.update { $0.sortDescending = true }
      } label: {
        if catalog.filter.sortDescending {
          Label(LocalizedStringKey(catalog.filter.sort.descendingTitleKey),
                systemImage: "checkmark")
        } else {
          Text(LocalizedStringKey(catalog.filter.sort.descendingTitleKey))
        }
      }

      Button {
        catalog.update { $0.sortDescending = false }
      } label: {
        if !catalog.filter.sortDescending {
          Label(LocalizedStringKey(catalog.filter.sort.ascendingTitleKey),
                systemImage: "checkmark")
        } else {
          Text(LocalizedStringKey(catalog.filter.sort.ascendingTitleKey))
        }
      }
    } label: {
      if showsTitle {
        Label(LocalizedStringKey(catalog.filter.sort.titleKey),
              systemImage: "arrow.up.arrow.down")
          .labelStyle(.titleAndIcon)
          .lineLimit(1)
      } else {
        Label("Sort_By", systemImage: "arrow.up.arrow.down")
          .labelStyle(.iconOnly)
      }
    }
    .help(Text("Sort_By"))
  }

  private var sortBinding: Binding<MediaSortOrder> {
    Binding(
      get: { catalog.filter.sort },
      set: { order in
        catalog.update {
          $0.sort = order
          $0.sortDescending = order.prefersDescending
        }
      }
    )
  }
}

/// Native `.searchScopes` under the Search field: Everywhere / Titles / People.
/// Maps onto `LibraryCatalog.searchField` (`nil` / `.title` / `.cast`).
enum LibrarySearchScope: String, CaseIterable, Identifiable, Hashable {
  case everywhere
  case titles
  case people

  var id: String { rawValue }

  /// Short labels for the scope bar (not the long tvOS chip menu copy).
  var titleKey: String {
    switch self {
    case .everywhere: return "Scope_Bar_Everywhere"
    case .titles: return "Scope_Bar_Titles"
    case .people: return "Scope_Bar_People"
    }
  }

  var field: SearchItemsRequest.Field? {
    switch self {
    case .everywhere: return nil
    case .titles: return .title
    case .people: return .cast
    }
  }

  static func from(_ field: SearchItemsRequest.Field?) -> LibrarySearchScope {
    switch field {
    case .title: return .titles
    case .cast, .director: return .people
    case nil: return .everywhere
    }
  }
}

/// Native toolbar Filters control.
/// Idle: plain three-line glyph. Active: filled circle + system badge.
/// No nested capsule, no `.glass` / `.bordered`.
struct LibraryFiltersButton: View {
  let activeCount: Int
  let action: () -> Void
  var showsTitle = true

  private var symbol: String {
    activeCount > 0
      ? "line.3.horizontal.decrease.circle.fill"
      : "line.3.horizontal.decrease"
  }

  var body: some View {
    Button(action: action) {
      if showsTitle {
        Label("Filters", systemImage: symbol)
          .labelStyle(.titleAndIcon)
          .lineLimit(1)
      } else {
        Label("Filters", systemImage: symbol)
          .labelStyle(.iconOnly)
      }
    }
    .badge(activeCount > 0 ? activeCount : 0)
    .help(Text("Filters"))
    .accessibilityValue(activeCount > 0
                        ? Text("\(activeCount)")
                        : Text("None"))
  }
}

extension View {
  /// Native scope bar under `.searchable` — Everywhere / Titles / People.
  func librarySearchScopes(_ scope: Binding<LibrarySearchScope>) -> some View {
    searchScopes(scope) {
      ForEach(LibrarySearchScope.allCases) { item in
        Text(LocalizedStringKey(item.titleKey)).tag(item)
      }
    }
  }
}

#endif
