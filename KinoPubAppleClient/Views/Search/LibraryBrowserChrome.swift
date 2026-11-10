//
//  LibraryBrowserChrome.swift
//  KinoPubAppleClient
//
//  Catalog / Search header chrome: grid↔list switcher, Filters button with an
//  active-count badge, sort popup (field + direction), and a status line with
//  result counts / loading.
//

import SwiftUI
import KinoPubUI
import KinoPubBackend

#if !os(tvOS)

/// Status line under the page title: «Всего 12 345», «Найдено 145 — 2 фильтра»,
/// or a short updating / loading cue.
struct LibraryBrowserStatusLine: View {
  let resultCount: Int?
  let isLoading: Bool
  let isSearching: Bool
  let activeFilterCount: Int

  var body: some View {
    HStack(spacing: 8) {
      if isLoading {
        ProgressView()
          .controlSize(.small)
        Text(resultCount == nil ? "Loading" : "Updating")
          .foregroundStyle(.secondary)
      } else if let resultCount {
        Text(statusText(for: resultCount))
          .foregroundStyle(.secondary)
      }
      Spacer(minLength: 0)
    }
    .font(TypeScale.filterControl)
    .accessibilityElement(children: .combine)
  }

  private func statusText(for count: Int) -> String {
    let formatted = count.formatted(.number.grouping(.automatic))
    if isSearching {
      if activeFilterCount > 0 {
        return String(format: String(localized: "Catalog_FoundWithFilters"),
                      formatted, activeFilterCount)
      }
      return String(format: String(localized: "Catalog_Found"), formatted)
    }
    return String(format: String(localized: "Catalog_Total"), formatted)
  }
}

/// Quick type chips under the status line (All / Movies / Series / …).
struct LibraryBrowserTypePresets<Catalog: FilterBarDriver>: View {
  @ObservedObject var catalog: Catalog

  private var selected: Set<MediaType> {
    catalog.filter.contentTypes.union(catalog.filter.contentType.map { [$0] } ?? [])
  }

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 8) {
        chip("Any", selected: selected.isEmpty) {
          catalog.update {
            $0.contentType = nil
            $0.contentTypes = []
            $0.kinds = []
          }
        }
        ForEach(primaryTypes) { type in
          chip(LocalizedStringKey(type.title), selected: selected.contains(type)) {
            catalog.update { filter in
              var types = filter.contentTypes
              if let one = filter.contentType { types.insert(one) }
              filter.contentType = nil
              filter.kinds = []
              if types.contains(type) { types.remove(type) } else { types.insert(type) }
              filter.contentTypes = types
            }
          }
        }
      }
      .padding(.horizontal, LibraryFilterMetrics.horizontalInset)
      .padding(.vertical, 4)
    }
  }

  /// The kinds people reach for first; the sheet has the full type set.
  private var primaryTypes: [MediaType] { [.movie, .serial, .tvshow, .documovie, .concert] }

  private func chip(_ title: LocalizedStringKey,
                    selected: Bool,
                    action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Text(title)
        .font(TypeScale.filterControl)
        .lineLimit(1)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
    .buttonStyle(.plain)
    .foregroundStyle(selected ? Color.KinoPub.background : Color.KinoPub.text)
    .background(
      Capsule(style: .continuous)
        .fill(selected ? Color.KinoPub.text.opacity(0.85) : Color.KinoPub.text.opacity(0.12))
    )
  }
}

/// Sort popup: field list + ascending/descending (Reminders / reference 04).
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

/// Filters capsule with an active-count badge; opens the filter sheet.
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

/// In-scroll chrome for iPhone / iPad when the toolbar is too tight for labels:
/// status, type presets, and (optionally) the filter/sort capsules.
struct LibraryBrowserScrollChrome<Catalog: FilterBarDriver>: View {
  @ObservedObject var catalog: Catalog
  var resultCount: Int?
  var showsTypePresets = true
  var showsInlineControls = false
  @Binding var showingFilters: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      LibraryBrowserStatusLine(
        resultCount: resultCount,
        isLoading: catalogIsLoading,
        isSearching: catalogIsSearching,
        activeFilterCount: catalog.filter.activeFilterCount
      )
      .padding(.horizontal, LibraryFilterMetrics.horizontalInset)
      .padding(.top, 8)

      if showsTypePresets {
        LibraryBrowserTypePresets(catalog: catalog)
      }

      if showsInlineControls {
        HStack(spacing: LibraryFilterMetrics.spacing) {
          MediaGridLayoutPicker()
          LibraryFiltersButton(activeCount: catalog.filter.activeFilterCount,
                               action: { showingFilters = true })
          LibrarySortMenu(catalog: catalog)
          Spacer(minLength: 0)
        }
        .padding(.horizontal, LibraryFilterMetrics.horizontalInset)
        .padding(.bottom, 6)
      }
    }
    .padding(.bottom, 4)
  }

  /// `LibraryCatalog` publishes loading; other drivers may not — keep soft.
  private var catalogIsLoading: Bool {
    (catalog as? LibraryCatalog)?.isLoading == true
  }

  private var catalogIsSearching: Bool {
    (catalog as? LibraryCatalog)?.isSearching == true
  }
}

#endif
