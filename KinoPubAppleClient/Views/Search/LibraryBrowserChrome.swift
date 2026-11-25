//
//  LibraryBrowserChrome.swift
//  KinoPubAppleClient
//
//  Catalog / listing chrome: Files-style view Menu (grid/list + sort), a clean
//  Filters toolbar button, and Notes-style count copy for `.navigationSubtitle`
//  under the title (Catalog and category screens — not the Search tab root).
//  Sort also lives in the Filter & Sort sheet (field + direction).
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

/// Trailing toolbar Menu: layout (grid / list) + sort field + direction.
/// Icon is the current layout — no segmented control, no nested glass chrome.
struct LibraryViewOptionsMenu<Catalog: FilterBarDriver>: View {
  @ObservedObject var catalog: Catalog
  var includesSort = true
  @AppStorage(MediaGridLayout.storageKey) private var layoutRaw = MediaGridLayout.posters.rawValue

  private var currentLayout: MediaGridLayout { MediaGridLayout.resolved(from: layoutRaw) }

  var body: some View {
    Menu {
      Section {
        Picker(selection: layoutBinding) {
          ForEach(MediaGridLayout.allCases) { layout in
            Label(LocalizedStringKey(layout.titleKey), systemImage: layout.systemImage)
              .tag(layout.rawValue)
          }
        } label: {
          Text("View Options")
        }
        .pickerStyle(.inline)
      }

      if includesSort {
        Section {
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
        }
      }
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

/// Native toolbar Filters control — filled symbol + system badge when active.
/// No nested capsule, no `.glass` / `.bordered` (toolbar Liquid Glass is the system’s).
struct LibraryFiltersButton: View {
  let activeCount: Int
  let action: () -> Void
  var showsTitle = true

  private var symbol: String {
    activeCount > 0
      ? "line.3.horizontal.decrease.circle.fill"
      : "line.3.horizontal.decrease.circle"
  }

  var body: some View {
    Button(action: action) {
      if showsTitle {
        Label("Filters", systemImage: symbol)
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

#endif
