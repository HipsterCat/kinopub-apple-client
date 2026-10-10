//
//  WhatsNewSheet.swift
//  KinoPubAppleClient
//
//  Shown once after an update to a marketing version that has bullets in
//  `whats-new.json`. Continue (or Menu) dismisses and records the version.
//

import SwiftUI
import KinoPubUI

struct WhatsNewSheet: View {
  let entry: AppChangelog.Entry
  var languageCode: String
  var onContinue: () -> Void

  @FocusState private var continueFocused: Bool

  private var bullets: [String] { entry.bullets(languageCode: languageCode) }

  var body: some View {
    VStack(alignment: .leading, spacing: 24) {
      Text("What's new")
        .font(TypeScale.heroTitle)
        .foregroundStyle(.primary)

      Text(versionLine)
        .font(TypeScale.heroSecondary)
        .foregroundStyle(.secondary)

      VStack(alignment: .leading, spacing: 12) {
        ForEach(Array(bullets.enumerated()), id: \.offset) { _, bullet in
          HStack(alignment: .top, spacing: 12) {
            Text("•")
              .font(TypeScale.detailBody)
              .foregroundStyle(.secondary)
            Text(verbatim: bullet)
              .font(TypeScale.detailBody)
              .foregroundStyle(.primary)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
      }

      Spacer(minLength: 0)

      Button("Continue", action: onContinue)
        .buttonStyle(.borderedProminent)
        .focused($continueFocused)
#if os(tvOS)
        .defaultFocus($continueFocused, true, priority: .userInitiated)
#endif
        .frame(maxWidth: .infinity)
    }
    .padding(sheetPadding)
    .frame(maxWidth: 720, maxHeight: .infinity, alignment: .topLeading)
    .background(Color.KinoPub.background.ignoresSafeArea())
    .task { continueFocused = true }
  }

  private var versionLine: String {
    if let date = entry.date, !date.isEmpty {
      return "\(entry.version) · \(date)"
    }
    return entry.version
  }

  private var sheetPadding: CGFloat {
#if os(tvOS)
    60
#else
    28
#endif
  }
}

/// Presents `WhatsNewSheet` when the running marketing version is newer than the
/// last one the viewer dismissed. First launch records the version and stays quiet.
struct WhatsNewPresentation: ViewModifier {
  var isSignedIn: Bool
  @AppStorage("selectedLanguage") private var selectedLanguage: String = (
    Locale.current.language.languageCode?.identifier ?? "en"
  )
  @State private var pending: AppChangelog.Entry?

  func body(content: Content) -> some View {
    content
      .sheet(item: $pending, onDismiss: markSeen) { entry in
        WhatsNewSheet(entry: entry, languageCode: selectedLanguage, onContinue: {
          pending = nil
        })
#if os(tvOS)
        .environment(\.colorScheme, .dark)
#endif
      }
      .onAppear(perform: considerPresenting)
      .onChange(of: isSignedIn) { _, _ in
        considerPresenting()
      }
  }

  private func considerPresenting() {
    guard pending == nil, isSignedIn else { return }
    pending = AppChangelog.load().pendingSheetEntry(currentVersion: Bundle.main.appVersionLong)
  }

  private func markSeen() {
    AppChangelog.markSeen(Bundle.main.appVersionLong)
  }
}

extension View {
  func presentsWhatsNew(isSignedIn: Bool) -> some View {
    modifier(WhatsNewPresentation(isSignedIn: isSignedIn))
  }
}

#Preview("What's New") {
  WhatsNewSheet(
    entry: AppChangelog.Entry(
      version: "1.0",
      date: "2026-10-10",
      ru: [
        "В Медиатеке слева — таблетки: Слежу, Продолжить, История и папки закладок.",
        "Баннер на главной снова по центру, соседние карточки выглядывают."
      ],
      en: [
        "Library has a pill sidebar: Following, Continue, History, and bookmark folders.",
        "The Home banner is the centred card row again, with neighbours peeking."
      ]
    ),
    languageCode: "ru",
    onContinue: {}
  )
}
