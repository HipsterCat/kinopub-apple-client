//
//  LibraryBrowserChrome.swift
//  KinoPubAppleClient
//
//  Catalog / Search chrome: grid↔list switcher, Filters button with an active-count
//  badge, and Notes-style count copy for `.navigationSubtitle` under the title.
//  Sort lives primarily in the Filter & Sort sheet (field + direction).
//

import SwiftUI
import KinoPubUI
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

/// Sort menu kept for collection sort-only toolbars and as a compact toolbar control.
struct LibrarySortMenu<Catalog: FilterBarDriver>: View {
  @ObservedObject var catalog: Catalog
  var showsTitle = true
  var iconOnly = false

  var body: some View {
    Menu {
      Picker("Sort", selection: sortBinding) {
        ForEach(MediaSortOrder.allCases) { order in
          Text(LocalizedStringKey(order.titleKey)).tag(order)
        }
      }
      .pickerStyle(.inline)

      Divider()

      Picker("Sort_Order", selection: directionBinding) {
        Text(LocalizedStringKey(catalog.filter.sort.descendingTitleKey)).tag(true)
        Text(LocalizedStringKey(catalog.filter.sort.ascendingTitleKey)).tag(false)
      }
      .pickerStyle(.inline)
    } label: {
      if iconOnly && !showsTitle {
        Label("Sort", systemImage: "arrow.up.arrow.down")
          .labelStyle(.iconOnly)
      } else {
        Label(LocalizedStringKey(catalog.filter.sort.titleKey),
              systemImage: "arrow.up.arrow.down")
          .labelStyle(.titleAndIcon)
          .lineLimit(1)
      }
    }
    .modifier(LibraryFilterGlassStyle(isProminent: false))
    .help(Text("Sort"))
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

  private var directionBinding: Binding<Bool> {
    Binding(
      get: { catalog.filter.sortDescending },
      set: { descending in
        catalog.update { $0.sortDescending = descending }
      }
    )
  }
}

/// Filters capsule with an active-count badge; opens the Filter & Sort sheet.
struct LibraryFiltersButton: View {
  let activeCount: Int
  let action: () -> Void
  var showsTitle = true

  var body: some View {
    Button(action: action) {
      HStack(spacing: 6) {
        Image(systemName: "line.3.horizontal.decrease")
        if showsTitle {
          Text("Filters")
        }
        if activeCount > 0 {
          Text("\(activeCount)")
            .font(.caption.weight(.bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.primary.opacity(0.18)))
            .accessibilityLabel(Text("\(activeCount)"))
        }
      }
      .font(TypeScale.filterControl)
      .lineLimit(1)
    }
    .modifier(LibraryFilterGlassStyle(isProminent: activeCount > 0))
    .help(Text("Filters"))
    .accessibilityValue(activeCount > 0
                        ? Text("\(activeCount)")
                        : Text("None"))
  }
}

#endif
