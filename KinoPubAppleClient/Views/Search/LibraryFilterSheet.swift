//
//  LibraryFilterSheet.swift
//  KinoPubAppleClient
//
//  Filter sheet / trailing panel for Catalog + Search: preset tags plus typed
//  sections (type, genre, country, years, quality, ratings). Replaces the nested
//  filter menus.
//

import SwiftUI
import KinoPubUI
import KinoPubBackend

#if !os(tvOS)
struct LibraryFilterSheet<Catalog: FilterBarDriver>: View {
  @ObservedObject var catalog: Catalog
  @Environment(\.dismiss) private var dismiss

  private var years: [YearRange] {
    YearRange.decades(upTo: Calendar.current.component(.year, from: Date()))
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 28) {
          presetSection
          typeSection
          if !catalog.genres.isEmpty {
            genreSection
          }
          if !catalog.countries.isEmpty {
            countrySection
          }
          yearSection
          qualitySection
          ratingSection
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
      }
      .background(Color.KinoPub.background)
      .navigationTitle("Filters")
#if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
#endif
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          if catalog.filter.hasActiveFilters {
            Button("Clear") { catalog.clearFilters() }
          }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
            .fontWeight(.semibold)
        }
      }
    }
#if os(macOS)
    .frame(minWidth: 380, idealWidth: 420, minHeight: 520)
#endif
  }

  // MARK: - Presets

  private var presetSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      sectionTitle("Filter_Presets")
      FlowTags {
        presetTag("4K", selected: catalog.filter.want4K || catalog.filter.minimumQuality == .uhd4K) {
          catalog.update {
            if $0.want4K || $0.minimumQuality == .uhd4K {
              $0.want4K = false
              if $0.minimumQuality == .uhd4K { $0.minimumQuality = nil }
            } else {
              $0.want4K = true
              $0.minimumQuality = .uhd4K
            }
          }
        }
        presetTag("HD", selected: catalog.filter.wantHD) {
          catalog.update { $0.wantHD.toggle() }
        }
        presetTag("Status_Finished", selected: catalog.filter.finishedOnly) {
          catalog.update { $0.finishedOnly.toggle() }
        }
        ForEach(years.prefix(4)) { range in
          presetTag(LocalizedStringKey(range.title),
                    selected: catalog.filter.years == range) {
            catalog.update {
              $0.years = $0.years == range ? nil : range
              $0.yearFrom = nil
              $0.yearTo = nil
            }
          }
        }
      }
    }
  }

  // MARK: - Type

  private var typeSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      sectionTitle("Type")
      FlowTags {
        presetTag("Any", selected: selectedTypes.isEmpty) {
          catalog.update {
            $0.contentType = nil
            $0.contentTypes = []
            $0.kinds = []
          }
        }
        ForEach(MediaType.allCases) { type in
          presetTag(LocalizedStringKey(type.title), selected: selectedTypes.contains(type)) {
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
    }
  }

  private var selectedTypes: Set<MediaType> {
    catalog.filter.contentTypes.union(catalog.filter.contentType.map { [$0] } ?? [])
  }

  // MARK: - Genre / country / years

  private var genreSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      sectionTitle("Genre")
      FlowTags {
        presetTag("Any", selected: selectedGenreIDs.isEmpty) {
          catalog.update {
            $0.genreID = nil
            $0.genreIDs = []
          }
        }
        ForEach(catalog.genres) { genre in
          presetTag(LocalizedStringKey(genre.title),
                    selected: selectedGenreIDs.contains(genre.id)) {
            catalog.update { filter in
              var ids = Set(filter.genreIDs)
              if let one = filter.genreID { ids.insert(one) }
              filter.genreID = nil
              if ids.contains(genre.id) { ids.remove(genre.id) } else { ids.insert(genre.id) }
              filter.genreIDs = ids.sorted()
            }
          }
        }
      }
    }
  }

  private var selectedGenreIDs: Set<Int> {
    Set(catalog.filter.genreIDs).union(catalog.filter.genreID.map { [$0] } ?? [])
  }

  private var countrySection: some View {
    VStack(alignment: .leading, spacing: 12) {
      sectionTitle("Country")
      FlowTags {
        presetTag("Any_Feminine", selected: selectedCountryIDs.isEmpty) {
          catalog.update {
            $0.countryID = nil
            $0.countryIDs = []
          }
        }
        ForEach(catalog.countries.prefix(24), id: \.id) { country in
          presetTag(LocalizedStringKey(country.title),
                    selected: selectedCountryIDs.contains(country.id)) {
            catalog.update { filter in
              var ids = filter.countryIDs
              if let one = filter.countryID { ids.insert(one) }
              filter.countryID = nil
              if ids.contains(country.id) { ids.remove(country.id) } else { ids.insert(country.id) }
              filter.countryIDs = ids
            }
          }
        }
      }
    }
  }

  private var selectedCountryIDs: Set<Int> {
    catalog.filter.countryIDs.union(catalog.filter.countryID.map { [$0] } ?? [])
  }

  private var yearSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      sectionTitle("Years")
      FlowTags {
        presetTag("Any_Plural", selected: catalog.filter.years == nil
                  && catalog.filter.yearFrom == nil
                  && catalog.filter.yearTo == nil) {
          catalog.update {
            $0.years = nil
            $0.yearFrom = nil
            $0.yearTo = nil
          }
        }
        ForEach(years) { range in
          presetTag(LocalizedStringKey(range.title),
                    selected: catalog.filter.years == range) {
            catalog.update {
              $0.years = $0.years == range ? nil : range
              $0.yearFrom = nil
              $0.yearTo = nil
            }
          }
        }
      }
    }
  }

  private var qualitySection: some View {
    VStack(alignment: .leading, spacing: 12) {
      sectionTitle("Quality")
      FlowTags {
        presetTag("Any_Neuter", selected: catalog.filter.minimumQuality == nil
                  && !catalog.filter.want4K && !catalog.filter.wantHD) {
          catalog.update {
            $0.minimumQuality = nil
            $0.want4K = false
            $0.wantHD = false
          }
        }
        ForEach(VideoQuality.allCases, id: \.rawValue) { quality in
          presetTag(LocalizedStringKey(quality.title),
                    selected: catalog.filter.minimumQuality == quality) {
            catalog.update {
              $0.minimumQuality = $0.minimumQuality == quality ? nil : quality
              $0.want4K = quality == .uhd4K && $0.minimumQuality == .uhd4K
              if quality == .uhd4K || quality == .fullHD1080 || quality == .hd720 {
                $0.wantHD = $0.minimumQuality != nil
              }
            }
          }
        }
      }
    }
  }

  private var ratingSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      sectionTitle("Filter_Rating")
      FlowTags {
        ForEach([7.0, 8.0, 9.0], id: \.self) { floor in
          let label = "KP \(Int(floor))+"
          presetTag(LocalizedStringKey(label),
                    selected: catalog.filter.kinopoiskMin == floor) {
            catalog.update {
              $0.kinopoiskMin = $0.kinopoiskMin == floor ? nil : floor
            }
          }
        }
      }
    }
  }

  // MARK: - Building blocks

  private func sectionTitle(_ key: LocalizedStringKey) -> some View {
    Text(key)
      .font(.headline)
      .foregroundStyle(Color.KinoPub.text)
  }

  private func presetTag(_ title: LocalizedStringKey,
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
        .fill(selected ? Color.KinoPub.text : Color.KinoPub.text.opacity(0.12))
    )
  }
}

/// Simple wrapping tag cloud without GeometryReader gymnastics.
private struct FlowTags<Content: View>: View {
  @ViewBuilder var content: () -> Content

  var body: some View {
    // LazyVGrid with adaptive columns approximates a chip cloud well enough for
    // filter sheets; true left-to-right flow is not worth a custom layout here.
    LazyVGrid(
      columns: [GridItem(.adaptive(minimum: 88), spacing: 8, alignment: .leading)],
      alignment: .leading,
      spacing: 8
    ) {
      content()
    }
  }
}
#endif
