//
//  LibraryFilterSheet.swift
//  KinoPubAppleClient
//
//  Filter & Sort sheet — list rows with drill-down pickers (not a genre/year chip
//  cloud). Preset tags stay at the top only. Matches the iOS Filter & Sort reference.
//

import SwiftUI
import KinoPubUI
import KinoPubBackend

#if !os(tvOS)
struct LibraryFilterSheet<Catalog: FilterBarDriver>: View {
  @ObservedObject var catalog: Catalog
  @Environment(\.dismiss) private var dismiss

  private var decades: [YearRange] {
    YearRange.decades(upTo: Calendar.current.component(.year, from: Date()))
  }

  private var currentYear: Int {
    Calendar.current.component(.year, from: Date())
  }

  var body: some View {
    NavigationStack {
      List {
        presetsSection
        sortSection
        filterRowsSection
      }
#if os(iOS)
      .listStyle(.insetGrouped)
#else
      .listStyle(.inset)
#endif
      .navigationTitle("Filter_And_Sort")
#if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
#endif
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button {
            dismiss()
          } label: {
            Image(systemName: "xmark")
          }
          .accessibilityLabel(Text("Close"))
        }
        if catalog.filter.hasActiveFilters {
          ToolbarItem(placement: .primaryAction) {
            Button("Clear") { catalog.clearFilters() }
          }
        }
      }
    }
#if os(macOS)
    .frame(minWidth: 420, idealWidth: 460, minHeight: 560)
#endif
  }

  // MARK: - Presets (only place for pills)

  private var presetsSection: some View {
    Section {
      FilterPresetTags(catalog: catalog, decades: decades, currentYear: currentYear)
        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
        .listRowBackground(Color.clear)
    }
  }

  // MARK: - Sort By

  private var sortSection: some View {
    Section {
      NavigationLink {
        LibrarySortPickerPage(catalog: catalog)
      } label: {
        FilterSheetRow(
          systemImage: "arrow.up.arrow.down",
          title: "Sort_By",
          value: sortSummary
        )
      }
    }
  }

  private var sortSummary: String {
    let field = String(localized: String.LocalizationValue(catalog.filter.sort.titleKey))
    let direction = catalog.filter.sortDescending
      ? String(localized: "Sort_Desc_Short")
      : String(localized: "Sort_Asc_Short")
    return "\(field), \(direction)"
  }

  // MARK: - Filter rows

  private var filterRowsSection: some View {
    Section {
      NavigationLink {
        LibraryTypePickerPage(catalog: catalog)
      } label: {
        FilterSheetRow(
          systemImage: "square.stack.3d.up",
          title: "Filter_Forms",
          value: formsValue
        )
      }

      NavigationLink {
        LibraryGenrePickerPage(catalog: catalog)
      } label: {
        FilterSheetRow(
          systemImage: "theatermasks",
          title: "Genre",
          value: genresValue
        )
      }

      NavigationLink {
        LibraryStatusPickerPage(catalog: catalog)
      } label: {
        FilterSheetRow(
          systemImage: "flag",
          title: "Filter_Status",
          value: statusValue
        )
      }

      NavigationLink {
        LibraryYearPickerPage(catalog: catalog)
      } label: {
        FilterSheetRow(
          systemImage: "calendar",
          title: "Filter_Year",
          value: yearValue
        )
      }

      NavigationLink {
        LibraryDecadePickerPage(catalog: catalog)
      } label: {
        FilterSheetRow(
          systemImage: "calendar.badge.clock",
          title: "Filter_Decades",
          value: decadesValue
        )
      }

      NavigationLink {
        LibraryQualityPickerPage(catalog: catalog)
      } label: {
        FilterSheetRow(
          systemImage: "rectangle.badge.checkmark",
          title: "Quality",
          value: qualityValue
        )
      }

      NavigationLink {
        LibraryCountryPickerPage(catalog: catalog)
      } label: {
        FilterSheetRow(
          systemImage: "globe",
          title: "Country",
          value: countriesValue
        )
      }

      NavigationLink {
        LibraryRatingPickerPage(catalog: catalog)
      } label: {
        FilterSheetRow(
          systemImage: "star",
          title: "Filter_Rating",
          value: ratingsValue
        )
      }
    }
  }

  // MARK: - Trailing values

  private var anyLabel: String { String(localized: "Any") }

  private var formsValue: String {
    let types = catalog.filter.contentTypes.union(catalog.filter.contentType.map { [$0] } ?? [])
    if types.isEmpty, catalog.filter.kinds.isEmpty { return anyLabel }
    if !catalog.filter.kinds.isEmpty {
      let titles = CatalogKind.allCases.filter(catalog.filter.kinds.contains)
        .map { String(localized: String.LocalizationValue($0.titleKey)) }
      return summary(titles)
    }
    return summary(types.map { String(localized: String.LocalizationValue($0.title)) })
  }

  private var genresValue: String {
    let ids = Set(catalog.filter.genreIDs).union(catalog.filter.genreID.map { [$0] } ?? [])
    guard !ids.isEmpty else { return anyLabel }
    return summary(catalog.genres.filter { ids.contains($0.id) }.map(\.title))
  }

  private var statusValue: String {
    catalog.filter.finishedOnly
      ? String(localized: "Status_Finished")
      : anyLabel
  }

  private var yearValue: String {
    if let from = catalog.filter.yearFrom, let to = catalog.filter.yearTo {
      return from == to ? "\(from)" : "\(from)–\(to)"
    }
    if let from = catalog.filter.yearFrom { return "\(from)+" }
    if let to = catalog.filter.yearTo { return "≤\(to)" }
    if let years = catalog.filter.years { return years.title }
    return anyLabel
  }

  private var decadesValue: String {
    catalog.filter.years?.title ?? anyLabel
  }

  private var qualityValue: String {
    if let quality = catalog.filter.minimumQuality { return quality.title }
    if catalog.filter.want4K { return "4K" }
    if catalog.filter.wantHD { return "HD" }
    return anyLabel
  }

  private var countriesValue: String {
    let ids = catalog.filter.countryIDs.union(catalog.filter.countryID.map { [$0] } ?? [])
    guard !ids.isEmpty else { return anyLabel }
    return summary(catalog.countries.filter { ids.contains($0.id) }.map(\.title))
  }

  private var ratingsValue: String {
    var parts: [String] = []
    if let min = catalog.filter.kinopoiskMin {
      parts.append("KP \(formatRating(min))+")
    }
    if let min = catalog.filter.imdbMin {
      parts.append("IMDb \(formatRating(min))+")
    }
    return parts.isEmpty ? anyLabel : parts.joined(separator: ", ")
  }

  private func formatRating(_ value: Double) -> String {
    value == value.rounded() ? String(Int(value)) : String(value)
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

// MARK: - Row chrome

private struct FilterSheetRow: View {
  let systemImage: String
  let title: LocalizedStringKey
  let value: String

  var body: some View {
    Label {
      HStack {
        Text(title)
        Spacer(minLength: 8)
        Text(value)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
    } icon: {
      Image(systemName: systemImage)
        .foregroundStyle(.blue)
    }
  }
}

// MARK: - Preset tags

private struct FilterPresetTags<Catalog: FilterBarDriver>: View {
  @ObservedObject var catalog: Catalog
  let decades: [YearRange]
  let currentYear: Int

  var body: some View {
    // Adaptive wrap — presets only. Values for genres/years live in drill-downs.
    LazyVGrid(
      columns: [GridItem(.adaptive(minimum: 96), spacing: 8, alignment: .leading)],
      alignment: .leading,
      spacing: 8
    ) {
      tag("4K", selected: catalog.filter.want4K || catalog.filter.minimumQuality == .uhd4K) {
        catalog.update {
          let on = $0.want4K || $0.minimumQuality == .uhd4K
          $0.want4K = !on
          $0.minimumQuality = on ? nil : .uhd4K
        }
      }
      tag("HD", selected: catalog.filter.wantHD) {
        catalog.update { $0.wantHD.toggle() }
      }
      tag("Status_Finished", selected: catalog.filter.finishedOnly) {
        catalog.update { $0.finishedOnly.toggle() }
      }
      tag(LocalizedStringKey("\(currentYear)"),
          selected: catalog.filter.years == YearRange(from: currentYear, to: currentYear)
            || (catalog.filter.yearFrom == currentYear && catalog.filter.yearTo == currentYear)) {
        let year = YearRange(from: currentYear, to: currentYear)
        catalog.update {
          if $0.years == year || ($0.yearFrom == currentYear && $0.yearTo == currentYear) {
            $0.years = nil
            $0.yearFrom = nil
            $0.yearTo = nil
          } else {
            $0.years = year
            $0.yearFrom = nil
            $0.yearTo = nil
          }
        }
      }
      ForEach(decades.prefix(3)) { range in
        tag(LocalizedStringKey(range.title), selected: catalog.filter.years == range) {
          catalog.update {
            $0.years = $0.years == range ? nil : range
            $0.yearFrom = nil
            $0.yearTo = nil
          }
        }
      }
    }
  }

  private func tag(_ title: LocalizedStringKey,
                   selected: Bool,
                   action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Text(title)
        .font(.subheadline.weight(.medium))
        .lineLimit(1)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }
    .buttonStyle(.plain)
    .foregroundStyle(selected ? Color.primary : Color.primary)
    .background(
      Capsule(style: .continuous)
        .fill(selected ? Color.primary.opacity(0.18) : Color.primary.opacity(0.08))
        .overlay(
          Capsule(style: .continuous)
            .strokeBorder(Color.primary.opacity(selected ? 0.35 : 0.12), lineWidth: 1)
        )
    )
  }
}

// MARK: - Drill-down pages

private struct LibrarySortPickerPage<Catalog: FilterBarDriver>: View {
  @ObservedObject var catalog: Catalog

  var body: some View {
    List {
      Section {
        ForEach(MediaSortOrder.allCases) { order in
          Button {
            catalog.update {
              $0.sort = order
              $0.sortDescending = order.prefersDescending
            }
          } label: {
            HStack {
              Text(LocalizedStringKey(order.titleKey))
                .foregroundStyle(.primary)
              Spacer()
              if catalog.filter.sort == order {
                Image(systemName: "checkmark")
                  .foregroundStyle(.blue)
              }
            }
          }
        }
      }
      Section {
        Button {
          catalog.update { $0.sortDescending = true }
        } label: {
          HStack {
            Text(LocalizedStringKey(catalog.filter.sort.descendingTitleKey))
              .foregroundStyle(.primary)
            Spacer()
            if catalog.filter.sortDescending {
              Image(systemName: "checkmark").foregroundStyle(.blue)
            }
          }
        }
        Button {
          catalog.update { $0.sortDescending = false }
        } label: {
          HStack {
            Text(LocalizedStringKey(catalog.filter.sort.ascendingTitleKey))
              .foregroundStyle(.primary)
            Spacer()
            if !catalog.filter.sortDescending {
              Image(systemName: "checkmark").foregroundStyle(.blue)
            }
          }
        }
      }
    }
    .navigationTitle("Sort_By")
#if os(iOS)
    .navigationBarTitleDisplayMode(.inline)
#endif
  }
}

private struct LibraryTypePickerPage<Catalog: FilterBarDriver>: View {
  @ObservedObject var catalog: Catalog

  private var selected: Set<MediaType> {
    catalog.filter.contentTypes.union(catalog.filter.contentType.map { [$0] } ?? [])
  }

  var body: some View {
    List {
      Button {
        catalog.update {
          $0.contentType = nil
          $0.contentTypes = []
          $0.kinds = []
        }
      } label: {
        checkRow("Any", on: selected.isEmpty && catalog.filter.kinds.isEmpty)
      }
      ForEach(MediaType.allCases) { type in
        Button {
          catalog.update { filter in
            var types = filter.contentTypes
            if let one = filter.contentType { types.insert(one) }
            filter.contentType = nil
            filter.kinds = []
            if types.contains(type) { types.remove(type) } else { types.insert(type) }
            filter.contentTypes = types
          }
        } label: {
          checkRow(LocalizedStringKey(type.title), on: selected.contains(type))
        }
      }
    }
    .navigationTitle("Filter_Forms")
#if os(iOS)
    .navigationBarTitleDisplayMode(.inline)
#endif
  }
}

private struct LibraryGenrePickerPage<Catalog: FilterBarDriver>: View {
  @ObservedObject var catalog: Catalog

  private var selected: Set<Int> {
    Set(catalog.filter.genreIDs).union(catalog.filter.genreID.map { [$0] } ?? [])
  }

  var body: some View {
    List {
      Button {
        catalog.update {
          $0.genreID = nil
          $0.genreIDs = []
        }
      } label: {
        checkRow("Any", on: selected.isEmpty)
      }
      ForEach(catalog.genres) { genre in
        Button {
          catalog.update { filter in
            var ids = Set(filter.genreIDs)
            if let one = filter.genreID { ids.insert(one) }
            filter.genreID = nil
            if ids.contains(genre.id) { ids.remove(genre.id) } else { ids.insert(genre.id) }
            filter.genreIDs = ids.sorted()
          }
        } label: {
          checkRow(LocalizedStringKey(genre.title), on: selected.contains(genre.id))
        }
      }
    }
    .navigationTitle("Genre")
#if os(iOS)
    .navigationBarTitleDisplayMode(.inline)
#endif
  }
}

private struct LibraryStatusPickerPage<Catalog: FilterBarDriver>: View {
  @ObservedObject var catalog: Catalog

  var body: some View {
    List {
      Button {
        catalog.update { $0.finishedOnly = false }
      } label: {
        checkRow("Any", on: !catalog.filter.finishedOnly)
      }
      Button {
        catalog.update { $0.finishedOnly = true }
      } label: {
        checkRow("Status_Finished", on: catalog.filter.finishedOnly)
      }
    }
    .navigationTitle("Filter_Status")
#if os(iOS)
    .navigationBarTitleDisplayMode(.inline)
#endif
  }
}

private struct LibraryYearPickerPage<Catalog: FilterBarDriver>: View {
  @ObservedObject var catalog: Catalog

  private var years: [Int] {
    let current = Calendar.current.component(.year, from: Date())
    return Array(stride(from: current, through: 1950, by: -1))
  }

  var body: some View {
    List {
      Button {
        catalog.update {
          $0.yearFrom = nil
          $0.yearTo = nil
          $0.years = nil
        }
      } label: {
        checkRow("Any_Plural", on: catalog.filter.yearFrom == nil
                 && catalog.filter.yearTo == nil
                 && catalog.filter.years == nil)
      }
      ForEach(years, id: \.self) { year in
        Button {
          catalog.update {
            $0.years = nil
            if $0.yearFrom == year && $0.yearTo == year {
              $0.yearFrom = nil
              $0.yearTo = nil
            } else {
              $0.yearFrom = year
              $0.yearTo = year
            }
          }
        } label: {
          checkRow(LocalizedStringKey("\(year)"),
                   on: catalog.filter.yearFrom == year && catalog.filter.yearTo == year)
        }
      }
    }
    .navigationTitle("Filter_Year")
#if os(iOS)
    .navigationBarTitleDisplayMode(.inline)
#endif
  }
}

private struct LibraryDecadePickerPage<Catalog: FilterBarDriver>: View {
  @ObservedObject var catalog: Catalog

  private var decades: [YearRange] {
    YearRange.decades(upTo: Calendar.current.component(.year, from: Date()))
  }

  var body: some View {
    List {
      Button {
        catalog.update {
          $0.years = nil
          $0.yearFrom = nil
          $0.yearTo = nil
        }
      } label: {
        checkRow("Any_Plural", on: catalog.filter.years == nil)
      }
      ForEach(decades) { range in
        Button {
          catalog.update {
            $0.yearFrom = nil
            $0.yearTo = nil
            $0.years = $0.years == range ? nil : range
          }
        } label: {
          checkRow(LocalizedStringKey(range.title), on: catalog.filter.years == range)
        }
      }
    }
    .navigationTitle("Filter_Decades")
#if os(iOS)
    .navigationBarTitleDisplayMode(.inline)
#endif
  }
}

private struct LibraryQualityPickerPage<Catalog: FilterBarDriver>: View {
  @ObservedObject var catalog: Catalog

  var body: some View {
    List {
      Button {
        catalog.update {
          $0.minimumQuality = nil
          $0.want4K = false
          $0.wantHD = false
        }
      } label: {
        checkRow("Any_Neuter", on: catalog.filter.minimumQuality == nil
                 && !catalog.filter.want4K && !catalog.filter.wantHD)
      }
      ForEach(VideoQuality.allCases, id: \.rawValue) { quality in
        Button {
          catalog.update {
            if $0.minimumQuality == quality {
              $0.minimumQuality = nil
              $0.want4K = false
              $0.wantHD = false
            } else {
              $0.minimumQuality = quality
              $0.want4K = quality == .uhd4K
              $0.wantHD = quality.rawValue >= VideoQuality.hd720.rawValue
            }
          }
        } label: {
          checkRow(LocalizedStringKey(quality.title),
                   on: catalog.filter.minimumQuality == quality)
        }
      }
    }
    .navigationTitle("Quality")
#if os(iOS)
    .navigationBarTitleDisplayMode(.inline)
#endif
  }
}

private struct LibraryCountryPickerPage<Catalog: FilterBarDriver>: View {
  @ObservedObject var catalog: Catalog

  private var selected: Set<Int> {
    catalog.filter.countryIDs.union(catalog.filter.countryID.map { [$0] } ?? [])
  }

  var body: some View {
    List {
      Button {
        catalog.update {
          $0.countryID = nil
          $0.countryIDs = []
        }
      } label: {
        checkRow("Any_Feminine", on: selected.isEmpty)
      }
      ForEach(catalog.countries, id: \.id) { country in
        Button {
          catalog.update { filter in
            var ids = filter.countryIDs
            if let one = filter.countryID { ids.insert(one) }
            filter.countryID = nil
            if ids.contains(country.id) { ids.remove(country.id) } else { ids.insert(country.id) }
            filter.countryIDs = ids
          }
        } label: {
          checkRow(LocalizedStringKey(country.title), on: selected.contains(country.id))
        }
      }
    }
    .navigationTitle("Country")
#if os(iOS)
    .navigationBarTitleDisplayMode(.inline)
#endif
  }
}

private struct LibraryRatingPickerPage<Catalog: FilterBarDriver>: View {
  @ObservedObject var catalog: Catalog

  private let floors: [Double] = [6, 7, 8, 9]

  var body: some View {
    List {
      Section("Filter_Kinopoisk") {
        Button {
          catalog.update { $0.kinopoiskMin = nil }
        } label: {
          checkRow("Any", on: catalog.filter.kinopoiskMin == nil)
        }
        ForEach(floors, id: \.self) { floor in
          Button {
            catalog.update {
              $0.kinopoiskMin = $0.kinopoiskMin == floor ? nil : floor
            }
          } label: {
            checkRow(LocalizedStringKey("KP \(Int(floor))+"),
                     on: catalog.filter.kinopoiskMin == floor)
          }
        }
      }
      Section("IMDb") {
        Button {
          catalog.update { $0.imdbMin = nil }
        } label: {
          checkRow("Any", on: catalog.filter.imdbMin == nil)
        }
        ForEach(floors, id: \.self) { floor in
          Button {
            catalog.update {
              $0.imdbMin = $0.imdbMin == floor ? nil : floor
            }
          } label: {
            checkRow(LocalizedStringKey("IMDb \(Int(floor))+"),
                     on: catalog.filter.imdbMin == floor)
          }
        }
      }
    }
    .navigationTitle("Filter_Rating")
#if os(iOS)
    .navigationBarTitleDisplayMode(.inline)
#endif
  }
}

@ViewBuilder
private func checkRow(_ title: LocalizedStringKey, on: Bool) -> some View {
  HStack {
    Text(title)
      .foregroundStyle(.primary)
    Spacer()
    if on {
      Image(systemName: "checkmark")
        .foregroundStyle(.blue)
    }
  }
}
#endif
