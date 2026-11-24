//
//  DetailsEnrichmentItemView.swift
//  KinoPubAppleClient
//
//  One Details › Items row: enable + optional jump to its Integration.
//

import SwiftUI

#if !os(tvOS)
struct DetailsEnrichmentItemView: View {
  let item: DetailsEnrichmentItem
  @AppStorage private var isEnabled: Bool
  @AppStorage(DetailsEnrichmentPreferences.metadataFetchingKey)
  private var metadataFetching = true

  init(item: DetailsEnrichmentItem) {
    self.item = item
    _isEnabled = AppStorage(wrappedValue: true, item.enabledKey)
  }

  var body: some View {
    Form {
      Section {
        Toggle("Enabled", isOn: $isEnabled)
          .disabled(!metadataFetching)
      } footer: {
        Text(LocalizedStringKey(item.footerKey))
      }

      if let integration = item.relatedIntegration {
        Section {
          NavigationLink(value: SettingsDetailRoute.integration(integration)) {
            HStack(spacing: 10) {
              IntegrationIconView(integration: integration)
                .frame(width: SettingsLeadingIcon.width, alignment: .center)
              VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: integration.name)
                Text("Keys, proxy, playback options")
                  .font(.footnote)
                  .foregroundStyle(.secondary)
              }
            }
          }
        } header: {
          Text("Source")
        } footer: {
          Text("Opens Integrations for this source.")
        }
      }
    }
    .formStyle(.grouped)
    .navigationTitle(LocalizedStringKey(item.titleKey))
#if os(iOS)
    .navigationBarTitleDisplayMode(.inline)
#endif
  }
}

/// One Details › Items NavigationLink with equal-width icon + On/Off before the chevron.
struct DetailsEnrichmentItemRow: View {
  let item: DetailsEnrichmentItem
  var masterEnabled: Bool
  @AppStorage private var isEnabled: Bool

  init(item: DetailsEnrichmentItem, masterEnabled: Bool) {
    self.item = item
    self.masterEnabled = masterEnabled
    _isEnabled = AppStorage(wrappedValue: true, item.enabledKey)
  }

  var body: some View {
    NavigationLink(value: SettingsDetailRoute.detailsItem(item)) {
      HStack(spacing: 10) {
        SettingsLeadingIcon(systemImage: item.systemImage)
        Text(LocalizedStringKey(item.titleKey))
        Spacer(minLength: 8)
        Text(isEnabled ? "On" : "Off")
          .foregroundStyle(.secondary)
      }
    }
    .disabled(!masterEnabled)
  }
}

/// Fixed-width SF Symbol so Image / Info rows share one leading column.
struct SettingsLeadingIcon: View {
  static let width: CGFloat = 22
  let systemImage: String

  var body: some View {
    Image(systemName: systemImage)
      .frame(width: Self.width, alignment: .center)
      .foregroundStyle(.secondary)
  }
}
#endif
