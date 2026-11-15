//
//  LibraryFilterSheet.swift
//  KinoPubAppleClient
//
//  Filter & Sort sheet. Draft applies only on checkmark; X discards. Clear is
//  extra. Filter values are wrapping tags (~3 lines), selected ones colored and
//  moved to the front — matching catalog-filters/01-ios-types-sheet.png and
//  06-filter-sort-sheet.png. Not a square chip grid and not a plain list.
//

import SwiftUI
import KinoPubUI
import KinoPubBackend

#if !os(tvOS)
struct LibraryFilterSheet<Catalog: FilterBarDriver>: View {
  @ObservedObject var catalog: Catalog
  @Environment(\.dismiss) private var dismiss
  /// Edits while open; catalog.filter is untouched until ✓.
  @State private var draft: LibraryFilter
  @State private var path = NavigationPath()

  init(catalog: Catalog) {
    self.catalog = catalog
    _draft = State(initialValue: catalog.filter)
  }

  private var decades: [YearRange] {
    YearRange.decades(upTo: Calendar.current.component(.year, from: Date()))
  }

  private var currentYear: Int {
    Calendar.current.component(.year, from: Date())
  }

  var body: some View {
    NavigationStack(path: $path) {
      rootContent
        .navigationTitle("Filter_And_Sort")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .toolbar { sheetToolbar(isRoot: true) }
        .safeAreaInset(edge: .bottom) {
          if draft.hasActiveFilters {
            clearBar
          }
        }
        .navigationDestination(for: FilterSheetRoute.self) { route in
          destination(route)
            .toolbar { sheetToolbar(isRoot: false) }
        }
    }
#if os(macOS)
    .frame(minWidth: 420, idealWidth: 460, minHeight: 560)
#endif
  }

  // MARK: - Root

  private var rootContent: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        presetTags
        sortRow
        categoryRows
      }
      .padding(.horizontal, 16)
      .padding(.top, 8)
      .padding(.bottom, 24)
    }
  }

  private var presetTags: some View {
    let tags = presetTagModels
    return FilterTagWrap(spacing: 8) {
      ForEach(ordered(tags)) { tag in
        FilterTagChip(
          title: tag.title,
          selected: tag.selected,
          action: { withAnimation(.easeOut(duration: 0.22)) { tag.toggle(&draft) } }
        )
      }
    }
    .animation(.easeOut(duration: 0.22), value: draft)
  }

  private var sortRow: some View {
    Button {
      path.append(FilterSheetRoute.sort)
    } label: {
      FilterCategoryRow(
        systemImage: "arrow.up.arrow.down",
        title: "Sort_By",
        value: sortSummary
      )
    }
    .buttonStyle(.plain)
    .padding(.vertical, 4)
  }

  private var categoryRows: some View {
    VStack(spacing: 0) {
      categoryButton(.forms, "square.stack.3d.up", "Filter_Forms", formsValue)
      divider
      categoryButton(.genres, "theatermasks", "Genre", genresValue)
      divider
      categoryButton(.status, "flag", "Filter_Status", statusValue)
      divider
      categoryButton(.year, "calendar", "Filter_Year", yearValue)
      divider
      categoryButton(.decades, "calendar.badge.clock", "Filter_Decades", decadesValue)
      divider
      categoryButton(.quality, "rectangle.badge.checkmark", "Quality", qualityValue)
      divider
      categoryButton(.countries, "globe", "Country", countriesValue)
      divider
      categoryButton(.ratings, "star", "Filter_Rating", ratingsValue)
    }
    .background(
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .fill(Color.primary.opacity(0.06))
    )
    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
  }

  private var divider: some View {
    Divider().padding(.leading, 44)
  }

  private func categoryButton(_ route: FilterSheetRoute,
                              _ icon: String,
                              _ title: LocalizedStringKey,
                              _ value: String) -> some View {
    Button {
      path.append(route)
    } label: {
      FilterCategoryRow(systemImage: icon, title: title, value: value)
    }
    .buttonStyle(.plain)
  }

  private var clearBar: some View {
    Button {
      withAnimation(.easeOut(duration: 0.22)) {
        draft = LibraryFilter(sort: draft.sort, sortDescending: draft.sortDescending,
                              person: draft.person)
      }
    } label: {
      Text("Clear_Filters")
        .font(.body.weight(.semibold))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }
    .buttonStyle(.glass)
    .buttonBorderShape(.capsule)
    .padding(.horizontal, 24)
    .padding(.bottom, 12)
  }

  // MARK: - Toolbar: X + ✓ (+ Clear is separate)

  @ToolbarContentBuilder
  private func sheetToolbar(isRoot: Bool) -> some ToolbarContent {
    ToolbarItem(placement: .cancellationAction) {
      Button {
        if isRoot {
          dismiss()
        } else {
          path.removeLast()
        }
      } label: {
        Image(systemName: "xmark")
      }
      .accessibilityLabel(Text("Close"))
    }
    ToolbarItem(placement: .confirmationAction) {
      Button {
        if isRoot {
          applyAndDismiss()
        } else {
          path.removeLast()
        }
      } label: {
        Image(systemName: "checkmark")
      }
      .fontWeight(.semibold)
      .accessibilityLabel(Text("Done"))
    }
  }

  private func applyAndDismiss() {
    let applied = draft
    catalog.update { $0 = applied }
    dismiss()
  }

  // MARK: - Destinations (wrapping tags)

  @ViewBuilder
  private func destination(_ route: FilterSheetRoute) -> some View {
    switch route {
    case .sort:
      FilterSortTagsPage(draft: $draft)
        .navigationTitle("Sort_By")
    case .forms:
      FilterFormsTagsPage(draft: $draft)
        .navigationTitle("Filter_Forms")
    case .genres:
      FilterGenreTagsPage(draft: $draft, genres: catalog.genres)
        .navigationTitle("Genre")
    case .status:
      FilterStatusTagsPage(draft: $draft)
        .navigationTitle("Filter_Status")
    case .year:
      FilterYearTagsPage(draft: $draft)
        .navigationTitle("Filter_Year")
    case .decades:
      FilterDecadeTagsPage(draft: $draft, decades: decades)
        .navigationTitle("Filter_Decades")
    case .quality:
      FilterQualityTagsPage(draft: $draft)
        .navigationTitle("Quality")
    case .countries:
      FilterCountryTagsPage(draft: $draft, countries: catalog.countries)
        .navigationTitle("Country")
    case .ratings:
      FilterRatingTagsPage(draft: $draft)
        .navigationTitle("Filter_Rating")
    }
  }

  // MARK: - Preset models

  private struct PresetTag: Identifiable {
    let id: String
    let title: String
    let selected: Bool
    let toggle: (inout LibraryFilter) -> Void
  }

  private var presetTagModels: [PresetTag] {
    var tags: [PresetTag] = [
      PresetTag(id: "4k", title: "4K",
                selected: draft.want4K || draft.minimumQuality == .uhd4K) { filter in
        let on = filter.want4K || filter.minimumQuality == .uhd4K
        filter.want4K = !on
        filter.minimumQuality = on ? nil : .uhd4K
      },
      PresetTag(id: "hd", title: "HD", selected: draft.wantHD) { $0.wantHD.toggle() },
      PresetTag(id: "finished", title: "Status_Finished", selected: draft.finishedOnly) {
        $0.finishedOnly.toggle()
      },
      PresetTag(id: "year-\(currentYear)", title: "\(currentYear)",
                selected: draft.years == YearRange(from: currentYear, to: currentYear)
                  || (draft.yearFrom == currentYear && draft.yearTo == currentYear)) { filter in
        let year = YearRange(from: currentYear, to: currentYear)
        if filter.years == year || (filter.yearFrom == currentYear && filter.yearTo == currentYear) {
          filter.years = nil
          filter.yearFrom = nil
          filter.yearTo = nil
        } else {
          filter.years = year
          filter.yearFrom = nil
          filter.yearTo = nil
        }
      }
    ]
    for range in decades.prefix(3) {
      tags.append(PresetTag(id: "decade-\(range.id)", title: range.title,
                            selected: draft.years == range) { filter in
        filter.years = filter.years == range ? nil : range
        filter.yearFrom = nil
        filter.yearTo = nil
      })
    }
    return tags
  }

  private func ordered(_ tags: [PresetTag]) -> [PresetTag] {
    tags.filter(\.selected) + tags.filter { !$0.selected }
  }

  // MARK: - Trailing summaries

  private var anyLabel: String { String(localized: "Any") }

  private var sortSummary: String {
    let field = String(localized: String.LocalizationValue(draft.sort.titleKey))
    let direction = draft.sortDescending
      ? String(localized: "Sort_Desc_Short")
      : String(localized: "Sort_Asc_Short")
    return "\(field), \(direction)"
  }

  private var formsValue: String {
    let types = draft.contentTypes.union(draft.contentType.map { [$0] } ?? [])
    if types.isEmpty { return anyLabel }
    return summary(types.map { String(localized: String.LocalizationValue($0.title)) })
  }

  private var genresValue: String {
    let ids = Set(draft.genreIDs).union(draft.genreID.map { [$0] } ?? [])
    guard !ids.isEmpty else { return anyLabel }
    return summary(catalog.genres.filter { ids.contains($0.id) }.map(\.title))
  }

  private var statusValue: String {
    draft.finishedOnly ? String(localized: "Status_Finished") : anyLabel
  }

  private var yearValue: String {
    if let from = draft.yearFrom, let to = draft.yearTo {
      return from == to ? "\(from)" : "\(from)–\(to)"
    }
    if let from = draft.yearFrom { return "\(from)+" }
    if let to = draft.yearTo { return "≤\(to)" }
    if let years = draft.years { return years.title }
    return anyLabel
  }

  private var decadesValue: String { draft.years?.title ?? anyLabel }

  private var qualityValue: String {
    if let quality = draft.minimumQuality { return quality.title }
    if draft.want4K { return "4K" }
    if draft.wantHD { return "HD" }
    return anyLabel
  }

  private var countriesValue: String {
    let ids = draft.countryIDs.union(draft.countryID.map { [$0] } ?? [])
    guard !ids.isEmpty else { return anyLabel }
    return summary(catalog.countries.filter { ids.contains($0.id) }.map(\.title))
  }

  private var ratingsValue: String {
    var parts: [String] = []
    if let min = draft.kinopoiskMin { parts.append("KP \(Int(min))+") }
    if let min = draft.imdbMin { parts.append("IMDb \(Int(min))+") }
    return parts.isEmpty ? anyLabel : parts.joined(separator: ", ")
  }

  private func summary(_ titles: [String]) -> String {
    switch titles.count {
    case 0: return anyLabel
    case 1: return titles[0]
    case 2: return titles.joined(separator: ", ")
    default: return "\(titles[0]) +\(titles.count - 1)"
    }
  }
}

// MARK: - Routes

private enum FilterSheetRoute: Hashable {
  case sort, forms, genres, status, year, decades, quality, countries, ratings
}

// MARK: - Shared chrome

private struct FilterCategoryRow: View {
  let systemImage: String
  let title: LocalizedStringKey
  let value: String

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: systemImage)
        .foregroundStyle(.blue)
        .frame(width: 28)
      Text(title)
        .foregroundStyle(.primary)
      Spacer(minLength: 8)
      Text(value)
        .foregroundStyle(.secondary)
        .lineLimit(1)
      Image(systemName: "chevron.right")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.tertiary)
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 12)
    .contentShape(Rectangle())
  }
}

private struct FilterTagChip: View {
  let title: String
  let selected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Text(LocalizedStringKey(title))
        .font(.subheadline.weight(.medium))
        .lineLimit(1)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
    .buttonStyle(.plain)
    .foregroundStyle(selected ? Color.white : Color.primary)
    .background(
      Capsule(style: .continuous)
        .fill(selected ? Color.accentColor : Color.primary.opacity(0.08))
        .overlay(
          Capsule(style: .continuous)
            .strokeBorder(Color.primary.opacity(selected ? 0 : 0.12), lineWidth: 1)
        )
    )
  }
}

/// Left-to-right wrap stack (~3 lines of tags), not a square adaptive grid.
private struct FilterTagWrap: Layout {
  var spacing: CGFloat = 8

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let maxWidth = proposal.width ?? .infinity
    var x: CGFloat = 0
    var y: CGFloat = 0
    var rowHeight: CGFloat = 0
    var height: CGFloat = 0
    for subview in subviews {
      let size = subview.sizeThatFits(.unspecified)
      if x > 0, x + size.width > maxWidth {
        x = 0
        y += rowHeight + spacing
        rowHeight = 0
      }
      rowHeight = max(rowHeight, size.height)
      x += size.width + spacing
      height = y + rowHeight
    }
    return CGSize(width: maxWidth.isFinite ? maxWidth : x, height: height)
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    var x = bounds.minX
    var y = bounds.minY
    var rowHeight: CGFloat = 0
    for subview in subviews {
      let size = subview.sizeThatFits(.unspecified)
      if x > bounds.minX, x + size.width > bounds.maxX {
        x = bounds.minX
        y += rowHeight + spacing
        rowHeight = 0
      }
      subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
      rowHeight = max(rowHeight, size.height)
      x += size.width + spacing
    }
  }
}

private struct FilterTagPage<Content: View>: View {
  @ViewBuilder var content: () -> Content

  var body: some View {
    ScrollView {
      content()
        .padding(16)
    }
  }
}

// MARK: - Tag pages

private struct FilterSelectableTag: Identifiable, Equatable {
  let id: String
  let title: String
  let selected: Bool
}

private struct FilterTagWrapContent: View {
  let tags: [FilterSelectableTag]
  let onToggle: (String) -> Void

  var body: some View {
    let ordered = tags.filter(\.selected) + tags.filter { !$0.selected }
    FilterTagWrap(spacing: 8) {
      ForEach(ordered) { tag in
        FilterTagChip(title: tag.title, selected: tag.selected) {
          withAnimation(.easeOut(duration: 0.22)) { onToggle(tag.id) }
        }
      }
    }
    .animation(.easeOut(duration: 0.22), value: ordered.map(\.id))
  }
}

private struct FilterSortTagsPage: View {
  @Binding var draft: LibraryFilter

  var body: some View {
    FilterTagPage {
      VStack(alignment: .leading, spacing: 16) {
        Text("Sort_By").font(.subheadline).foregroundStyle(.secondary)
        FilterTagWrapContent(
          tags: MediaSortOrder.allCases.map {
            FilterSelectableTag(id: $0.rawValue, title: $0.titleKey, selected: draft.sort == $0)
          }
        ) { id in
          guard let order = MediaSortOrder(rawValue: id) else { return }
          draft.sort = order
          draft.sortDescending = order.prefersDescending
        }
        Text("Sort_Order").font(.subheadline).foregroundStyle(.secondary)
        FilterTagWrapContent(
          tags: [
            FilterSelectableTag(id: "desc", title: draft.sort.descendingTitleKey,
                                selected: draft.sortDescending),
            FilterSelectableTag(id: "asc", title: draft.sort.ascendingTitleKey,
                                selected: !draft.sortDescending)
          ]
        ) { id in
          draft.sortDescending = (id == "desc")
        }
      }
    }
  }
}

private struct FilterFormsTagsPage: View {
  @Binding var draft: LibraryFilter

  private var selected: Set<MediaType> {
    draft.contentTypes.union(draft.contentType.map { [$0] } ?? [])
  }

  var body: some View {
    FilterTagPage {
      FilterTagWrapContent(
        tags: [FilterSelectableTag(id: "any", title: "Any", selected: selected.isEmpty)]
          + MediaType.allCases.map {
            FilterSelectableTag(id: $0.rawValue, title: $0.title, selected: selected.contains($0))
          }
      ) { id in
        if id == "any" {
          draft.contentType = nil
          draft.contentTypes = []
          draft.kinds = []
          return
        }
        guard let type = MediaType(rawValue: id) else { return }
        var types = draft.contentTypes
        if let one = draft.contentType { types.insert(one) }
        draft.contentType = nil
        draft.kinds = []
        if types.contains(type) { types.remove(type) } else { types.insert(type) }
        draft.contentTypes = types
      }
    }
  }
}

private struct FilterGenreTagsPage: View {
  @Binding var draft: LibraryFilter
  let genres: [MediaGenre]

  private var selected: Set<Int> {
    Set(draft.genreIDs).union(draft.genreID.map { [$0] } ?? [])
  }

  var body: some View {
    FilterTagPage {
      FilterTagWrapContent(
        tags: [FilterSelectableTag(id: "any", title: "Any", selected: selected.isEmpty)]
          + genres.map {
            FilterSelectableTag(id: "\($0.id)", title: $0.title, selected: selected.contains($0.id))
          }
      ) { id in
        if id == "any" {
          draft.genreID = nil
          draft.genreIDs = []
          return
        }
        guard let genreID = Int(id) else { return }
        var ids = Set(draft.genreIDs)
        if let one = draft.genreID { ids.insert(one) }
        draft.genreID = nil
        if ids.contains(genreID) { ids.remove(genreID) } else { ids.insert(genreID) }
        draft.genreIDs = ids.sorted()
      }
    }
  }
}

private struct FilterStatusTagsPage: View {
  @Binding var draft: LibraryFilter

  var body: some View {
    FilterTagPage {
      FilterTagWrapContent(
        tags: [
          FilterSelectableTag(id: "any", title: "Any", selected: !draft.finishedOnly),
          FilterSelectableTag(id: "finished", title: "Status_Finished", selected: draft.finishedOnly)
        ]
      ) { id in
        draft.finishedOnly = (id == "finished")
      }
    }
  }
}

private struct FilterYearTagsPage: View {
  @Binding var draft: LibraryFilter

  private var years: [Int] {
    let current = Calendar.current.component(.year, from: Date())
    return Array(stride(from: current, through: 1950, by: -1))
  }

  var body: some View {
    FilterTagPage {
      FilterTagWrapContent(
        tags: [FilterSelectableTag(
          id: "any",
          title: "Any_Plural",
          selected: draft.yearFrom == nil && draft.yearTo == nil && draft.years == nil
        )]
          + years.map {
            FilterSelectableTag(id: "\($0)", title: "\($0)",
                                selected: draft.yearFrom == $0 && draft.yearTo == $0)
          }
      ) { id in
        if id == "any" {
          draft.yearFrom = nil
          draft.yearTo = nil
          draft.years = nil
          return
        }
        guard let year = Int(id) else { return }
        draft.years = nil
        if draft.yearFrom == year && draft.yearTo == year {
          draft.yearFrom = nil
          draft.yearTo = nil
        } else {
          draft.yearFrom = year
          draft.yearTo = year
        }
      }
    }
  }
}

private struct FilterDecadeTagsPage: View {
  @Binding var draft: LibraryFilter
  let decades: [YearRange]

  var body: some View {
    FilterTagPage {
      FilterTagWrapContent(
        tags: [FilterSelectableTag(id: "any", title: "Any_Plural", selected: draft.years == nil)]
          + decades.map {
            FilterSelectableTag(id: $0.id, title: $0.title, selected: draft.years == $0)
          }
      ) { id in
        if id == "any" {
          draft.years = nil
          draft.yearFrom = nil
          draft.yearTo = nil
          return
        }
        guard let range = decades.first(where: { $0.id == id }) else { return }
        draft.yearFrom = nil
        draft.yearTo = nil
        draft.years = draft.years == range ? nil : range
      }
    }
  }
}

private struct FilterQualityTagsPage: View {
  @Binding var draft: LibraryFilter

  var body: some View {
    FilterTagPage {
      FilterTagWrapContent(
        tags: [FilterSelectableTag(
          id: "any",
          title: "Any_Neuter",
          selected: draft.minimumQuality == nil && !draft.want4K && !draft.wantHD
        )]
          + VideoQuality.allCases.map {
            FilterSelectableTag(id: "\($0.rawValue)", title: $0.title,
                                selected: draft.minimumQuality == $0)
          }
      ) { id in
        if id == "any" {
          draft.minimumQuality = nil
          draft.want4K = false
          draft.wantHD = false
          return
        }
        guard let raw = Int(id), let quality = VideoQuality(rawValue: raw) else { return }
        if draft.minimumQuality == quality {
          draft.minimumQuality = nil
          draft.want4K = false
          draft.wantHD = false
        } else {
          draft.minimumQuality = quality
          draft.want4K = quality == .uhd4K
          draft.wantHD = quality.rawValue >= VideoQuality.hd720.rawValue
        }
      }
    }
  }
}

private struct FilterCountryTagsPage: View {
  @Binding var draft: LibraryFilter
  let countries: [Country]

  private var selected: Set<Int> {
    draft.countryIDs.union(draft.countryID.map { [$0] } ?? [])
  }

  var body: some View {
    FilterTagPage {
      FilterTagWrapContent(
        tags: [FilterSelectableTag(id: "any", title: "Any_Feminine", selected: selected.isEmpty)]
          + countries.map {
            FilterSelectableTag(id: "\($0.id)", title: $0.title, selected: selected.contains($0.id))
          }
      ) { id in
        if id == "any" {
          draft.countryID = nil
          draft.countryIDs = []
          return
        }
        guard let countryID = Int(id) else { return }
        var ids = draft.countryIDs
        if let one = draft.countryID { ids.insert(one) }
        draft.countryID = nil
        if ids.contains(countryID) { ids.remove(countryID) } else { ids.insert(countryID) }
        draft.countryIDs = ids
      }
    }
  }
}

private struct FilterRatingTagsPage: View {
  @Binding var draft: LibraryFilter
  private let floors: [Double] = [6, 7, 8, 9]

  var body: some View {
    FilterTagPage {
      VStack(alignment: .leading, spacing: 16) {
        Text("Filter_Kinopoisk").font(.subheadline).foregroundStyle(.secondary)
        FilterTagWrapContent(
          tags: [FilterSelectableTag(id: "kp-any", title: "Any", selected: draft.kinopoiskMin == nil)]
            + floors.map {
              FilterSelectableTag(id: "kp-\(Int($0))", title: "KP \(Int($0))+",
                                  selected: draft.kinopoiskMin == $0)
            }
        ) { id in
          if id == "kp-any" {
            draft.kinopoiskMin = nil
            return
          }
          guard let value = Double(id.replacingOccurrences(of: "kp-", with: "")) else { return }
          draft.kinopoiskMin = draft.kinopoiskMin == value ? nil : value
        }
        Text("IMDb").font(.subheadline).foregroundStyle(.secondary)
        FilterTagWrapContent(
          tags: [FilterSelectableTag(id: "imdb-any", title: "Any", selected: draft.imdbMin == nil)]
            + floors.map {
              FilterSelectableTag(id: "imdb-\(Int($0))", title: "IMDb \(Int($0))+",
                                  selected: draft.imdbMin == $0)
            }
        ) { id in
          if id == "imdb-any" {
            draft.imdbMin = nil
            return
          }
          guard let value = Double(id.replacingOccurrences(of: "imdb-", with: "")) else { return }
          draft.imdbMin = draft.imdbMin == value ? nil : value
        }
      }
    }
  }
}
#endif
