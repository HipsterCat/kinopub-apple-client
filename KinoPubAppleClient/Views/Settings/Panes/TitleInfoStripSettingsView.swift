//
//  TitleInfoStripSettingsView.swift
//  KinoPubAppleClient
//
//  Settings › Details › Info › Age rating badge — upper info strip only.
//

import SwiftUI

#if !os(tvOS)
struct TitleInfoStripSettingsView: View {
  @AppStorage(MediaItemDisplayPreferences.showAgeRatingBadgeKey)
  private var showAgeRatingBadge = false
  @AppStorage(MediaItemDisplayPreferences.showForeignAgeRatingKey)
  private var showForeignAgeRating = true
  @AppStorage(MediaItemDisplayPreferences.convertAgeRatingKey)
  private var convertAgeRating = true
  @AppStorage(MediaItemDisplayPreferences.showQualityBadgesKey)
  private var showQualityBadges = true
  @AppStorage(MediaItemDisplayPreferences.showVoicingBadgesKey)
  private var showVoicingBadges = true
  @AppStorage(MediaItemDisplayPreferences.showCaptionsBadgeKey)
  private var showCaptionsBadge = true
  @AppStorage(DetailsEnrichmentPreferences.metadataFetchingKey)
  private var metadataFetching = true

  var body: some View {
    Form {
      Section {
        Toggle("Age rating badge", isOn: $showAgeRatingBadge)
          .disabled(!metadataFetching)
      } footer: {
        Text("Certification chip on the title’s upper info strip. Always listed in Facts.")
      }

      Section {
        Toggle("Show foreign ratings when missing", isOn: $showForeignAgeRating)
          .disabled(!metadataFetching || !showAgeRatingBadge)
        Toggle("Convert to local age", isOn: $convertAgeRating)
          .disabled(!metadataFetching || !showAgeRatingBadge)
      } header: {
        Text("Age rating")
      } footer: {
        Text("Foreign codes (PG-13, TV-MA) can stay as-is, convert to 12+ / 18+, or hide when there is no local age.")
      }

      Section {
        Toggle("Quality", isOn: $showQualityBadges)
          .disabled(!metadataFetching)
        Toggle("Dub / MVO", isOn: $showVoicingBadges)
          .disabled(!metadataFetching)
        Toggle("Captions", isOn: $showCaptionsBadge)
          .disabled(!metadataFetching)
      } header: {
        Text("Badges")
      } footer: {
        Text("Only the upper info strip under the title — not poster cards or the whole page.")
      }
    }
    .formStyle(.grouped)
    .navigationTitle("Age rating badge")
#if os(iOS)
    .navigationBarTitleDisplayMode(.inline)
#endif
  }
}
#endif
