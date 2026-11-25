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
  private var showAgeRatingBadge = true
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
        Text("Certification chip(s) on the title’s upper info strip and matching info modal. Always listed in Facts.")
      }

      Section {
        Toggle("Convert to local age", isOn: $convertAgeRating)
          .disabled(!metadataFetching || !showAgeRatingBadge)
        Toggle("Show foreign rating", isOn: $showForeignAgeRating)
          .disabled(!metadataFetching || !showAgeRatingBadge)
      } header: {
        Text("Age rating")
      } footer: {
        Text("Convert turns R / PG-13 into 16+ / 12+. Show foreign keeps the MPA or TV mark. Both on → both chips (16+ and R). Foreign only → R. Convert only → 16+.")
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
