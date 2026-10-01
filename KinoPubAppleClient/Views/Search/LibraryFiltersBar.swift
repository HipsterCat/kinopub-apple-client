//
//  LibraryFiltersBar.swift
//  KinoPubAppleClient
//

import SwiftUI
import KinoPubUI
import KinoPubBackend

/// What `LibraryFiltersBar` drives: a filter, the picker contents, and the apply/clear
/// verbs. `LibraryCatalog` applies picks server-side (`/v1/items`). A collection does
/// not: `/v1/collections/view` takes no parameters, so that page only offers sort.
@MainActor
protocol FilterBarDriver: ObservableObject {
  var filter: LibraryFilter { get }
  var genres: [MediaGenre] { get }
  var countries: [Country] { get }
  /// Where a typed query looks. `nil` on a page that is not a text search.
  var searchField: SearchItemsRequest.Field? { get }
  func update(_ transform: (inout LibraryFilter) -> Void)
  func updateSearchField(_ field: SearchItemsRequest.Field?)
  func clearFilters()
}

extension FilterBarDriver {
  var searchField: SearchItemsRequest.Field? { nil }
  func updateSearchField(_ field: SearchItemsRequest.Field?) {}
}

extension LibraryCatalog: FilterBarDriver {}

/// How much of the filter bar a page shows. `.full` is search, the library, and a
/// person's credits — those listings accept the picks. `.sort` is a collection:
/// the endpoint cannot filter, and a local copy of the search row is not a filter.
enum LibraryFiltersBarChrome {
  case full
  case sort
}

/// Sort and filter dropdowns — system `.glass` / `.glassProminent` capsules.
/// On macOS Search they sit centered in the toolbar accessory bar under the
/// trailing search field; on iOS/tvOS they scroll with the grid.
///
/// DESIGN: `CatalogPeriod` (`LibraryFilter.period`) is wired into `/v1/items` — add a
/// Period menu here when the filter chrome is designed (day/week/month/year).
struct LibraryFiltersBar<Catalog: FilterBarDriver>: View {

  @ObservedObject var catalog: Catalog
  var chrome: LibraryFiltersBarChrome = .full

  private var years: [YearRange] {
    YearRange.decades(upTo: Calendar.current.component(.year, from: Date()))
  }

  var body: some View {
#if os(macOS)
    // Centered glass chips under the trailing toolbar search (accessory bar).
    HStack(spacing: 0) {
      Spacer(minLength: 0)
      filterChips
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity)
    .accessibilityIdentifier("kinopub.filter-bar")
#else
    ScrollView(.horizontal, showsIndicators: false) {
      filterChips
        .padding(.horizontal, LibraryFilterMetrics.horizontalInset)
        .padding(.vertical, LibraryFilterMetrics.verticalPadding)
    }
    .accessibilityIdentifier("kinopub.filter-bar")
#endif
  }

  private var filterChips: some View {
    HStack(spacing: LibraryFilterMetrics.spacing) {
      sortMenu
      if chrome == .full {
        typeMenu
        genreMenu
        countryMenu
        yearMenu

        if catalog.filter.hasActiveFilters {
          Button {
            catalog.clearFilters()
          } label: {
            Label("Clear", systemImage: "xmark")
          }
        }
      }
    }
#if os(macOS)
    .padding(.horizontal, LibraryFilterMetrics.horizontalInset)
    .padding(.vertical, LibraryFilterMetrics.verticalPadding)
#endif
  }

  // MARK: - Menus

  private var sortMenu: some View {
    glassMenu(
      label: LocalizedStringKey(catalog.filter.sort.titleKey),
      icon: "arrow.up.arrow.down",
      isActive: false
    ) {
      ForEach(MediaSortOrder.allCases) { order in
        Button {
          catalog.update { $0.sort = order }
        } label: {
          Self.checkmarkLabel(LocalizedStringKey(order.titleKey),
                              selected: catalog.filter.sort == order)
        }
      }
    }
  }

  private var typeMenu: some View {
    glassMenu(
      label: catalog.filter.contentType.map { LocalizedStringKey($0.title) } ?? "Type",
      icon: "square.grid.2x2",
      isActive: catalog.filter.contentType != nil
    ) {
      Button {
        catalog.update { $0.contentType = nil }
      } label: {
        Self.checkmarkLabel("Any", selected: catalog.filter.contentType == nil)
      }
      ForEach(MediaType.allCases) { type in
        Button {
          catalog.update { $0.contentType = type }
        } label: {
          Self.checkmarkLabel(LocalizedStringKey(type.title), selected: catalog.filter.contentType == type)
        }
      }
    }
  }

  private var genreMenu: some View {
    let selected = catalog.genres.first { $0.id == catalog.filter.genreID }
    return glassMenu(
      label: selected.map { LocalizedStringKey($0.title) } ?? "Genre",
      icon: "theatermasks",
      isActive: catalog.filter.genreID != nil
    ) {
      Button {
        catalog.update { $0.genreID = nil }
      } label: {
        Self.checkmarkLabel("Any", selected: catalog.filter.genreID == nil)
      }
      ForEach(catalog.genres) { genre in
        Button {
          catalog.update { $0.genreID = genre.id }
        } label: {
          Self.checkmarkLabel(LocalizedStringKey(genre.title), selected: catalog.filter.genreID == genre.id)
        }
      }
    }
  }

  private var countryMenu: some View {
    let selected = catalog.countries.first { $0.id == catalog.filter.countryID }
    return glassMenu(
      label: selected.map { LocalizedStringKey($0.title) } ?? "Country",
      icon: "globe",
      isActive: catalog.filter.countryID != nil
    ) {
      Button {
        catalog.update { $0.countryID = nil }
      } label: {
        Self.checkmarkLabel("Any", selected: catalog.filter.countryID == nil)
      }
      ForEach(catalog.countries, id: \.id) { country in
        Button {
          catalog.update { $0.countryID = country.id }
        } label: {
          Self.checkmarkLabel(LocalizedStringKey(country.title), selected: catalog.filter.countryID == country.id)
        }
      }
    }
  }

  private var yearMenu: some View {
    glassMenu(
      label: catalog.filter.years.map { LocalizedStringKey($0.title) } ?? "Years",
      icon: "calendar",
      isActive: catalog.filter.years != nil
    ) {
      Button {
        catalog.update { $0.years = nil }
      } label: {
        Self.checkmarkLabel("Any", selected: catalog.filter.years == nil)
      }
      ForEach(years) { range in
        Button {
          catalog.update { $0.years = range }
        } label: {
          Self.checkmarkLabel(LocalizedStringKey(range.title), selected: catalog.filter.years == range)
        }
      }
    }
  }

  // MARK: - Building blocks

  /// Same path as UI Lab `UILabGlassChipStyle` — glass on the Menu itself, not bordered.
  @ViewBuilder
  private func glassMenu<Content: View>(
    label: LocalizedStringKey,
    icon: String,
    isActive: Bool,
    @ViewBuilder content: () -> Content
  ) -> some View {
    Menu {
      content()
    } label: {
      Label(label, systemImage: icon)
        .labelStyle(.titleAndIcon)
        .lineLimit(1)
    }
    .modifier(LibraryFilterGlassStyle(isProminent: isActive, useSolid: false))
  }

  /// Shared Menu chrome for person credits / call sites that still use the static API.
  @ViewBuilder
  static func filterMenu<Content: View>(
    label: LocalizedStringKey,
    icon: String,
    isActive: Bool,
    reduceTransparency: Bool = false,
    highContrast: Bool = false,
    @ViewBuilder content: () -> Content
  ) -> some View {
    Menu {
      content()
    } label: {
      Label(label, systemImage: icon)
        .labelStyle(.titleAndIcon)
        .lineLimit(1)
    }
    .modifier(LibraryFilterGlassStyle(
      isProminent: isActive,
      useSolid: false
    ))
  }

  @ViewBuilder
  static func menu<Content: View>(label: LocalizedStringKey,
                                  icon: String,
                                  isActive: Bool,
                                  @ViewBuilder content: () -> Content) -> some View {
    filterMenu(label: label, icon: icon, isActive: isActive, content: content)
  }

  static func checkmarkLabel(_ title: LocalizedStringKey, selected: Bool) -> some View {
    Label(title, systemImage: selected ? "checkmark" : "")
  }
}

/// The filter capsules' metrics — a generic `LibraryFiltersBar` cannot hold static
/// stored properties, so they live here.
enum LibraryFilterMetrics {
#if os(tvOS)
  static let spacing: CGFloat = 16
  static let horizontalInset: CGFloat = 80
  static let verticalPadding: CGFloat = 16
  static let controlSize: ControlSize = .large
  static let font: Font = TypeScale.filterControl
#elseif os(macOS)
  static let spacing: CGFloat = 8
  static let horizontalInset: CGFloat = 12
  static let verticalPadding: CGFloat = 4
  static let controlSize: ControlSize = .regular
  static let font: Font = TypeScale.filterControl
#else
  static let spacing: CGFloat = 10
  static let horizontalInset: CGFloat = 16
  static let verticalPadding: CGFloat = 8
  static let controlSize: ControlSize = .regular
  static let font: Font = TypeScale.filterControl
#endif
}

/// Glass chip styling — mirrors UI Lab. Solid bordered fallback only for Reduce
/// Transparency / increased contrast.
struct LibraryFilterGlassStyle: ViewModifier {
  var isProminent: Bool
  var useSolid: Bool = false
  var controlSize: ControlSize = LibraryFilterMetrics.controlSize

  func body(content: Content) -> some View {
    Group {
      if useSolid {
        if isProminent {
          content
                .buttonStyle(.glassProminent)
//            .tint(Color.KinoPub.accent)
        } else {
          content
//              /* */ .buttonStyle(.glass)
            .buttonStyle(.bordered)
        }
      } else if isProminent {
        content
          .buttonStyle(.glassProminent)
          .tint(Color.KinoPub.accent)
//          .kinoGlass(in: .capsule, tint: Color.KinoPub.accent, interactive: true)
      } else {
        content
          // System glass — required for accessory-bar filter chips (UI Lab path).
//              .kinoGlass(in: .capsule, interactive: true)
          .buttonStyle(.glass)
      }
    }
    .buttonBorderShape(.capsule)
    .controlSize(controlSize)
  }
}

#if DEBUG
#Preview("Library filters") {
  LibraryFiltersBar(
    catalog: LibraryCatalog(
      itemsService: VideoContentServiceMock(),
      authState: AuthState(
        authService: AuthorizationServiceMock(),
        accessTokenService: AccessTokenServiceMock()
      ),
      errorHandler: ErrorHandler()
    )
  )
  .background(Color.KinoPub.background)
  // .preferredColorScheme(.dark)
}
#endif
