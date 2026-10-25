//
//  SectionsSettingsView.swift
//  KinoPubAppleClient
//

import SwiftUI
import KinoPubBackend

#if !os(tvOS)

/// Toggle and reorder screen for `SectionVisibilityStore`. Persists immediately and updates
/// `TabsNavigationView` and `HomeCatalog` live.
struct SectionsSettingsView: View {
  @ObservedObject private var store = SectionVisibilityStore.shared
  @AppStorage(ContinueWatchingPreferences.weeksKey)
  private var continueWatchingWeeks = ContinueWatchingOrder.Rules.defaultWeeks
  @AppStorage(ContinueWatchingPreferences.includesBookmarksKey)
  private var continueWatchingBookmarks = true

  var body: some View {
    Form {
      Section {
        ForEach(Array(store.orderedBrowseTabs.enumerated()), id: \.element.id) { idx, spec in
          HStack {
            Toggle(spec.titleKey, isOn: tabBinding(for: spec))
              .disabled(!spec.canHide)
            if idx > 0 {
              Button {
                store.moveTabUp(id: spec.id)
              } label: {
                Image(systemName: "arrow.up")
              }
              .buttonStyle(.borderless)
            }
            if idx < store.orderedBrowseTabs.count - 1 {
              Button {
                store.moveTabDown(id: spec.id)
              } label: {
                Image(systemName: "arrow.down")
              }
              .buttonStyle(.borderless)
            }
          }
        }
        .onMove { indices, newOffset in
          store.moveTabs(fromOffsets: indices, toOffset: newOffset)
        }
      } header: {
        Text("Вкладки (Табы)")
      } footer: {
        Text("Включение, отключение и порядок вкладок верхнего меню и боковой панели.")
      }

      Section("Фильтры Главной") {
        Toggle("Без концертов на Главной", isOn: $store.excludeConcertsOnHome)
      }

      Section {
        Picker("Сколько недель учитывать", selection: $continueWatchingWeeks) {
          ForEach(ContinueWatchingOrder.Rules.weekOptions, id: \.self) { weeks in
            Text(verbatim: "\(weeks)").tag(weeks)
          }
        }
        Toggle("Добавлять закладки", isOn: $continueWatchingBookmarks)
      } header: {
        Text("Продолжить просмотр")
      } footer: {
        Text("Что не смотрели, не обновлялось и не добавлялось в закладки столько недель, в ряд не попадает. Закладки — по дате добавления, не больше четырёх.")
      }
      .onChange(of: continueWatchingWeeks) { _, weeks in ContinueWatchingPreferences.setWeeks(weeks) }
      .onChange(of: continueWatchingBookmarks) { _, isOn in ContinueWatchingPreferences.setIncludesBookmarks(isOn) }

      Section {
        ForEach(Array(store.orderedHomeSections.enumerated()), id: \.element.id) { idx, section in
          HStack {
            Toggle(isOn: homeSectionBinding(for: section)) {
              VStack(alignment: .leading, spacing: 2) {
                Text(section.title)
                Text(section.subtitle)
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            }
            if idx > 0 {
              Button {
                store.moveHomeSectionUp(id: section.id)
              } label: {
                Image(systemName: "arrow.up")
              }
              .buttonStyle(.borderless)
            }
            if idx < store.orderedHomeSections.count - 1 {
              Button {
                store.moveHomeSectionDown(id: section.id)
              } label: {
                Image(systemName: "arrow.down")
              }
              .buttonStyle(.borderless)
            }
          }
        }
        .onMove { indices, newOffset in
          store.moveHomeSections(fromOffsets: indices, toOffset: newOffset)
        }
      } header: {
        Text("Секции Главной (Watch Now)")
      }

      Section {
        ForEach(Array(store.orderedMovieSections.enumerated()), id: \.element.id) { idx, section in
          HStack {
            Toggle(isOn: movieSectionBinding(for: section)) {
              VStack(alignment: .leading, spacing: 2) {
                Text(section.title)
                Text(section.subtitle)
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            }
            if idx > 0 {
              Button {
                store.moveMovieSectionUp(id: section.id)
              } label: {
                Image(systemName: "arrow.up")
              }
              .buttonStyle(.borderless)
            }
            if idx < store.orderedMovieSections.count - 1 {
              Button {
                store.moveMovieSectionDown(id: section.id)
              } label: {
                Image(systemName: "arrow.down")
              }
              .buttonStyle(.borderless)
            }
          }
        }
        .onMove { indices, newOffset in
          store.moveMovieSections(fromOffsets: indices, toOffset: newOffset)
        }
      } header: {
        Text("Секции Фильмов (Movies)")
      }

      Section {
        ForEach(Array(store.orderedSeriesSections.enumerated()), id: \.element.id) { idx, section in
          HStack {
            Toggle(isOn: seriesSectionBinding(for: section)) {
              VStack(alignment: .leading, spacing: 2) {
                Text(section.title)
                Text(section.subtitle)
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            }
            if idx > 0 {
              Button {
                store.moveSeriesSectionUp(id: section.id)
              } label: {
                Image(systemName: "arrow.up")
              }
              .buttonStyle(.borderless)
            }
            if idx < store.orderedSeriesSections.count - 1 {
              Button {
                store.moveSeriesSectionDown(id: section.id)
              } label: {
                Image(systemName: "arrow.down")
              }
              .buttonStyle(.borderless)
            }
          }
        }
        .onMove { indices, newOffset in
          store.moveSeriesSections(fromOffsets: indices, toOffset: newOffset)
        }
      } header: {
        Text("Секции Сериалов и Шоу (Series)")
      }

      Section {
        Button("Сбросить по умолчанию", role: .destructive) {
          store.resetToDefaults()
        }
      }
    }
    .formStyle(.grouped)
    .platformNavigationTitle("Sections")
  }

  private func tabBinding(for spec: BrowseTabSpec) -> Binding<Bool> {
    Binding(
      get: { store.isTabVisible(spec.tab) },
      set: { store.setTabVisible($0, id: spec.id) }
    )
  }

  private func homeSectionBinding(for section: HomeSectionMeta) -> Binding<Bool> {
    Binding(
      get: { store.isHomeSectionVisible(section.id) },
      set: { store.setHomeSectionVisible($0, id: section.id) }
    )
  }

  private func movieSectionBinding(for section: HomeSectionMeta) -> Binding<Bool> {
    Binding(
      get: { store.isMovieSectionVisible(section.id) },
      set: { store.setMovieSectionVisible($0, id: section.id) }
    )
  }

  private func seriesSectionBinding(for section: HomeSectionMeta) -> Binding<Bool> {
    Binding(
      get: { store.isSeriesSectionVisible(section.id) },
      set: { store.setSeriesSectionVisible($0, id: section.id) }
    )
  }
}

#Preview {
  NavigationStack {
    SectionsSettingsView()
  }
}

#endif
