//
//  SectionsSettingsView.swift
//  KinoPubAppleClient
//

import SwiftUI

#if !os(tvOS)

/// Toggle and reorder screen for `SectionVisibilityStore`. Persists immediately and updates
/// `TabsNavigationView` and `HomeCatalog` live.
struct SectionsSettingsView: View {
  @ObservedObject private var store = SectionVisibilityStore.shared

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
        ForEach(Array(store.orderedHomeSections.enumerated()), id: \.element.id) { idx, section in
          HStack {
            Toggle(isOn: homeSectionBinding(for: section)) {
              VStack(alignment: .leading, spacing: 2) {
                Text(section.title)
                Text("\(section.subtitle) • \(section.sortingDescription)")
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
}

#Preview {
  NavigationStack {
    SectionsSettingsView()
  }
}

#endif
