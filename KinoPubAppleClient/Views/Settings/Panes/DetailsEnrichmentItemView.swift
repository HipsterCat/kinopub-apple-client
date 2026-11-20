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
#endif
