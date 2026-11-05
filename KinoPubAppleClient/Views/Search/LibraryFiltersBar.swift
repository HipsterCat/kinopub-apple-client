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
  /// The toolbar's grid / wide switch alone: a text search, where the picks do not apply.
  case layoutOnly
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
  /// Mac: the menus as icons in the window toolbar (`LibraryFiltersToolbar`), where the
  /// toolbar draws their glass; the chips' own glass and titles are off.
  var iconOnly = false
  /// With `iconOnly`: the menu's name beside its glyph — the current sort, «Фильтры» —
  /// while the window has room for it (`toolbarShowsLabels`).
  var showsToolbarTitle = false
  /// Mac: the menus as submenus of one Filters menu, the system's look inside a menu.
  var asSubmenu = false

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
      menus
    }
#if os(macOS)
    .padding(.horizontal, LibraryFilterMetrics.horizontalInset)
    .padding(.vertical, LibraryFilterMetrics.verticalPadding)
#endif
  }

  // MARK: - Menus

  /// The menus side by side, unwrapped: a toolbar group takes each as an item of its own.
  @ViewBuilder
  var menus: some View {
    sortMenu
    filterMenus
  }

  /// Sort alone: the toolbar keeps it in one place, trailing, apart from the filters.
  /// Named in the Mac toolbar it is a pop-up button — the current order and the system's
  /// up/down chevrons, as the SF Symbols app's font and weight selects (Sasha,
  /// 2026-11-05); without room, the glyph menu.
  @ViewBuilder
  var sort: some View {
    if iconOnly && showsToolbarTitle {
      sortPicker
        .pickerStyle(.menu)
        .fixedSize()
        .help(Text("Sort"))
    } else {
      sortMenu
    }
  }

  private var sortPicker: some View {
    Picker("Sort", selection: Binding(
      get: { catalog.filter.sort },
      set: { order in catalog.update { $0.sort = order } }
    )) {
      ForEach(MediaSortOrder.allCases) { order in
        Text(LocalizedStringKey(order.titleKey)).tag(order)
      }
    }
  }

  /// Whether a filter narrows the list now.
  var hasActiveFilters: Bool { catalog.filter.hasActiveFilters }

  @ViewBuilder
  var filterMenus: some View {
    if chrome == .full {
      typeMenu
      genreMenu
      countryMenu
      yearMenu

      if catalog.filter.hasActiveFilters {
        if iconOnly {
          Button {
            catalog.clearFilters()
          } label: {
            Label("Clear", systemImage: "xmark")
              .labelStyle(.iconOnly)
          }
          .help(Text("Clear"))
        } else {
          Button {
            catalog.clearFilters()
          } label: {
            Label("Clear", systemImage: "xmark")
          }
        }
      }
    }
  }

  private var sortMenu: some View {
    glassMenu(
      label: LocalizedStringKey(catalog.filter.sort.titleKey),
      icon: "arrow.up.arrow.down",
      isActive: false
    ) {
      // A picker: the system draws the selection (Sasha, 2026-10-30), not a checkmark
      // glyph pasted into one button's label.
      sortPicker
        .pickerStyle(.inline)
    }
  }

  private var typeMenu: some View {
    let selected = catalog.filter.contentTypes.union(catalog.filter.contentType.map { [$0] } ?? [])
    return glassMenu(
      label: typeLabel(selected),
      icon: "square.grid.2x2",
      isActive: !selected.isEmpty
    ) {
      Toggle("Any", isOn: Binding(
        get: { selected.isEmpty },
        set: { isOn in
          guard isOn else { return }
          catalog.update {
            $0.contentType = nil
            $0.contentTypes = []
          }
        }
      ))
      ForEach(MediaType.allCases) { type in
        Toggle(isOn: Binding(
          get: { selected.contains(type) },
          set: { isOn in
            catalog.update { filter in
              var types = filter.contentTypes
              if let one = filter.contentType { types.insert(one) }
              filter.contentType = nil
              if isOn { types.insert(type) } else { types.remove(type) }
              filter.contentTypes = types
            }
          }
        )) {
          Text(LocalizedStringKey(type.title))
        }
      }
    }
  }

  private func typeLabel(_ selected: Set<MediaType>) -> LocalizedStringKey {
    if selected.count == 1, let only = selected.first {
      return LocalizedStringKey(only.title)
    }
    return "Type"
  }

  private var genreMenu: some View {
    let selected = Set(catalog.filter.genreIDs).union(catalog.filter.genreID.map { [$0] } ?? [])
    let single = selected.count == 1
      ? catalog.genres.first { $0.id == selected.first }
      : nil
    return glassMenu(
      label: single.map { LocalizedStringKey($0.title) } ?? "Genre",
      icon: "square.stack.3d.down.right",
      isActive: !selected.isEmpty
    ) {
      Toggle("Any", isOn: Binding(
        get: { selected.isEmpty },
        set: { isOn in
          guard isOn else { return }
          catalog.update {
            $0.genreID = nil
            $0.genreIDs = []
          }
        }
      ))
      ForEach(catalog.genres) { genre in
        Toggle(isOn: Binding(
          get: { selected.contains(genre.id) },
          set: { isOn in
            catalog.update { filter in
              var ids = Set(filter.genreIDs)
              if let one = filter.genreID { ids.insert(one) }
              filter.genreID = nil
              if isOn { ids.insert(genre.id) } else { ids.remove(genre.id) }
              filter.genreIDs = ids.sorted()
            }
          }
        )) {
          Text(LocalizedStringKey(genre.title))
        }
      }
    }
  }

  private var countryMenu: some View {
    let selected = catalog.filter.countryIDs.union(catalog.filter.countryID.map { [$0] } ?? [])
    let single = selected.count == 1
      ? catalog.countries.first { $0.id == selected.first }
      : nil
    return glassMenu(
      label: single.map { LocalizedStringKey($0.title) } ?? "Country",
      icon: "globe",
      isActive: !selected.isEmpty
    ) {
      Toggle("Any", isOn: Binding(
        get: { selected.isEmpty },
        set: { isOn in
          guard isOn else { return }
          catalog.update {
            $0.countryID = nil
            $0.countryIDs = []
          }
        }
      ))
      ForEach(catalog.countries, id: \.id) { country in
        Toggle(isOn: Binding(
          get: { selected.contains(country.id) },
          set: { isOn in
            catalog.update { filter in
              var ids = filter.countryIDs
              if let one = filter.countryID { ids.insert(one) }
              filter.countryID = nil
              if isOn { ids.insert(country.id) } else { ids.remove(country.id) }
              filter.countryIDs = ids
            }
          }
        )) {
          Text(LocalizedStringKey(country.title))
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
      Picker("Years", selection: Binding(
        get: { catalog.filter.years },
        set: { range in catalog.update { $0.years = range } }
      )) {
        Text("Any").tag(YearRange?.none)
        ForEach(years) { range in
          Text(LocalizedStringKey(range.title)).tag(Optional(range))
        }
      }
      .pickerStyle(.inline)
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
    if asSubmenu {
      // Inside the toolbar's Filters menu: a submenu named for what it narrows, the pick
      // checked inside (`LibraryFiltersToolbar`).
      Menu {
        content()
      } label: {
        Label(label, systemImage: icon)
      }
    } else if iconOnly {
      // The Mac toolbar's: an icon, the pick named in the tooltip; a filled glyph
      // while it narrows the list.
      Menu {
        content()
      } label: {
        Label(label, systemImage: icon)
#if os(tvOS)
          // `toolbarLabelStyle` is iOS / macOS only (below); tvOS has no listing toolbar.
          .labelStyle(.iconOnly)
#else
          .toolbarLabelStyle(showsTitle: showsToolbarTitle)
#endif
          .symbolVariant(isActive ? .fill : .none)
      }
      .menuIndicator(.hidden)
      .help(Text(label))
    } else {
      Menu {
        content()
      } label: {
        Label(label, systemImage: icon)
          .labelStyle(.titleAndIcon)
          .lineLimit(1)
      }
      .modifier(LibraryFilterGlassStyle(isProminent: isActive, useSolid: false))
    }
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
//          .tint(Color.KinoPub.accent)
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

#if !os(tvOS)
/// The listing pages' toolbar: the grid / wide switch, then — on the Mac — one Filters
/// menu and Sort, as Apple Music has its sort menu, not chips over the grid (Sasha,
/// 2026-11-04). iOS keeps its filter chips in the scroll; the switch is its toolbar's.
///
/// Attach it before `.catalogGridChrome()`, which tells it whether the window has room
/// for the menus' names.
struct LibraryFiltersToolbar<Catalog: FilterBarDriver>: ToolbarContent {
  @ObservedObject var catalog: Catalog
  var chrome: LibraryFiltersBarChrome = .full
  @Environment(\.toolbarShowsLabels) private var showsLabels

  var body: some ToolbarContent {
    ToolbarItem(placement: .primaryAction) {
      MediaGridLayoutPicker()
    }
#if os(macOS)
    if chrome != .layoutOnly {
      ToolbarSpacer(.fixed, placement: .primaryAction)
      if FeatureFlags.macLegacySearchChrome {
        ToolbarItemGroup(placement: .primaryAction) {
          LibraryFiltersBar(catalog: catalog, chrome: chrome, iconOnly: true).menus
        }
      } else {
        // Photos' and Music's: one Filters menu with a submenu per filter, checkmarks
        // inside; Sort its own menu after it — always last, so it never changes place.
        if chrome == .full {
          ToolbarItem(placement: .primaryAction) {
            let bar = LibraryFiltersBar(catalog: catalog, chrome: chrome, asSubmenu: true)
            Menu {
              bar.filterMenus
            } label: {
              Label("Filters", systemImage: "line.3.horizontal.decrease")
                .toolbarLabelStyle(showsTitle: showsLabels)
                .symbolVariant(bar.hasActiveFilters ? .circle.fill : .none)
            }
            .menuIndicator(.hidden)
            .help(Text("Filters"))
          }
          ToolbarSpacer(.fixed, placement: .primaryAction)
        }
        ToolbarItem(placement: .primaryAction) {
          LibraryFiltersBar(catalog: catalog, chrome: chrome, iconOnly: true,
                            showsToolbarTitle: showsLabels).sort
        }
      }
    }
#endif
  }
}

/// Posters or wide cells — a system segmented control, as the SF Symbols app and AniShelf
/// switch their grids. On a phone a menu: two segments crowd a compact navigation bar.
struct MediaGridLayoutPicker: View {
  @AppStorage(MediaGridLayout.storageKey) private var layoutRaw = MediaGridLayout.posters.rawValue
#if os(iOS)
  @Environment(\.horizontalSizeClass) private var sizeClass
#endif

  private var current: MediaGridLayout { MediaGridLayout(rawValue: layoutRaw) ?? .posters }

  var body: some View {
#if os(iOS)
    if sizeClass == .compact {
      Menu {
        picker.pickerStyle(.inline)
      } label: {
        Label(LocalizedStringKey(current.titleKey), systemImage: current.systemImage)
      }
    } else {
      segmented
    }
#else
    segmented
#endif
  }

  private var segmented: some View {
    picker
      .pickerStyle(.segmented)
      .labelStyle(.iconOnly)
      .help(Text(LocalizedStringKey(current.titleKey)))
  }

  private var picker: some View {
    Picker("View Options", selection: $layoutRaw) {
      ForEach(MediaGridLayout.allCases) { layout in
        Label(LocalizedStringKey(layout.titleKey), systemImage: layout.systemImage)
          .tag(layout.rawValue)
      }
    }
  }
}

extension EnvironmentValues {
  /// Whether the listing toolbar's menus name themselves beside their glyphs. Set by
  /// `catalogGridChrome()` from the page's width.
  @Entry var toolbarShowsLabels = false
}

extension View {
  /// A toolbar menu's label: glyph and name with room, glyph alone without.
  @ViewBuilder
  func toolbarLabelStyle(showsTitle: Bool) -> some View {
    if showsTitle {
      labelStyle(.titleAndIcon)
    } else {
      labelStyle(.iconOnly)
    }
  }

  /// What a listing page with `LibraryFiltersToolbar` needs around its grid: the chosen
  /// posters / wide layout, and — on the Mac — whether its toolbar has room for names.
  func catalogGridChrome() -> some View {
    modifier(CatalogGridChrome())
  }
}

private struct CatalogGridChrome: ViewModifier {
  @AppStorage(MediaGridLayout.storageKey) private var layoutRaw = MediaGridLayout.posters.rawValue
  @State private var showsLabels = false

  /// The page's width past which the toolbar shows Sort's current pick and «Фильтры»
  /// beside their glyphs; below it, glyphs alone. A Mac window of 1280pt (a ~1000pt page)
  /// fits the title, the switch and «Последние добавленные» with room to spare
  /// (2026-11-05); narrower pages fold to icons before the toolbar would start pushing
  /// items into its overflow menu.
  private static let labelledToolbarWidth: CGFloat = 760

  func body(content: Content) -> some View {
    content
      .environment(\.mediaGridLayout, MediaGridLayout(rawValue: layoutRaw) ?? .posters)
      .onGeometryChange(for: Bool.self) { proxy in
        proxy.size.width >= Self.labelledToolbarWidth
      } action: { fits in
        showsLabels = fits
      }
      .environment(\.toolbarShowsLabels, showsLabels)
  }
}
#endif
