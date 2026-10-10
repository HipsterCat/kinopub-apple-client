//
//  ChangelogHistoryView.swift
//  KinoPubAppleClient
//
//  Full What's New history for Settings › About on iOS and macOS. tvOS draws
//  the same entries as TVSettingKit / SwiftUI Settings rows.
//

import SwiftUI
import KinoPubUI

struct ChangelogHistoryView: View {
  var catalog: AppChangelog = .load()
  var languageCode: String

  var body: some View {
    let entries = catalog.newestFirst
    if entries.isEmpty {
      Section {
        Text("WhatsNew_EmptyHistory")
          .font(TypeScale.detailBody)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    } else {
      ForEach(entries) { entry in
        Section(header: Text(verbatim: sectionTitle(entry))) {
          ForEach(Array(entry.bullets(languageCode: languageCode).enumerated()), id: \.offset) { _, bullet in
            Text(verbatim: bullet)
              .font(TypeScale.detailBody)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
      }
    }
  }

  private func sectionTitle(_ entry: AppChangelog.Entry) -> String {
    if let date = entry.date, !date.isEmpty {
      return "\(entry.version) · \(date)"
    }
    return entry.version
  }
}

#if !os(tvOS)
#Preview("History") {
  List {
    ChangelogHistoryView(languageCode: "ru")
  }
}
#endif
