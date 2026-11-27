//
//  WhatsNewSheet.swift
//  Piratic
//
//  What's New, in the shared `InfoPopup`: once at launch for the bullets this device
//  has not shown yet (Continue / Done / Menu / tap outside / the cross marks them
//  seen), and the whole history from Settings › About. Previous marketing versions
//  ride under the new bullets in the same scroll (Brink-style, from whats-new.json).
//

import SwiftUI
import PiraticUI

/// Notes as a bulleted list, at the popup's body size.
struct ChangelogBullets: View {
  let bullets: [String]

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      ForEach(Array(bullets.enumerated()), id: \.offset) { _, bullet in
        HStack(alignment: .firstTextBaseline, spacing: 14) {
          Text(verbatim: "•")
            .foregroundStyle(Color.Piratic.text)
          Text(verbatim: bullet)
            .foregroundStyle(Color.Piratic.text)
            .fixedSize(horizontal: false, vertical: true)
        }
        .font(InfoPopupMetrics.bodyFont)
      }
    }
  }
}

/// Every version's notes, newest first.
struct ChangelogHistory: View {
  var catalog: AppChangelog = .load()
  var languageCode: String

  var body: some View {
    let entries = catalog.newestFirst.filter { !$0.bullets(languageCode: languageCode).isEmpty }
    if entries.isEmpty {
      Text("WhatsNew_EmptyHistory")
        .font(InfoPopupMetrics.bodyFont)
        .foregroundStyle(Color.Piratic.subtitle)
    } else {
      VStack(alignment: .leading, spacing: InfoPopupMetrics.contentSpacing * 1.5) {
        ForEach(entries) { entry in
          versionBlock(entry)
        }
      }
    }
  }

  private func versionBlock(_ entry: AppChangelog.Entry) -> some View {
    VStack(alignment: .leading, spacing: InfoPopupMetrics.contentSpacing) {
      Text(verbatim: String(format: "Version %@".localized, entry.version))
        .font(InfoPopupMetrics.subtitleFont)
        .foregroundStyle(Color.Piratic.subtitle)
      ChangelogBullets(bullets: entry.bullets(languageCode: languageCode))
    }
  }
}

/// New bullets, then older marketing versions from the same JSON (no separate store).
struct WhatsNewUpdateBody: View {
  let pendingBullets: [String]
  var catalog: AppChangelog = .load()
  var languageCode: String
  /// When the launch popup shows every bullet (DEBUG), skip the previous section.
  var showPreviousReleases: Bool = true

  var body: some View {
    let previous = previousEntries
    VStack(alignment: .leading, spacing: InfoPopupMetrics.contentSpacing * 1.5) {
      ChangelogBullets(bullets: pendingBullets)
      if showPreviousReleases, !previous.isEmpty {
        VStack(alignment: .leading, spacing: InfoPopupMetrics.contentSpacing) {
          Text("WhatsNew_PreviousReleases")
            .font(InfoPopupMetrics.sectionFont)
            .foregroundStyle(Color.Piratic.text)
          ForEach(previous) { entry in
            VStack(alignment: .leading, spacing: InfoPopupMetrics.contentSpacing * 0.75) {
              Text(verbatim: String(format: "Version %@".localized, entry.version))
                .font(InfoPopupMetrics.subtitleFont)
                .foregroundStyle(Color.Piratic.subtitle)
              ChangelogBullets(bullets: entry.bullets(languageCode: languageCode))
            }
          }
        }
        .padding(.top, InfoPopupMetrics.contentSpacing * 0.5)
      }
    }
  }

  /// Older marketing versions than the running one, with notes — from whats-new.json.
  private var previousEntries: [AppChangelog.Entry] {
    let current = Bundle.main.appVersionLong
    return catalog.newestFirst.filter { entry in
      guard !entry.bullets(languageCode: languageCode).isEmpty else { return false }
      return AppChangelog.compareVersions(entry.version, current) == .orderedAscending
    }
  }
}

enum WhatsNewText {
  /// «Версия 1.0 • Сборка 10» — the running build, as the About preview writes it.
  static var currentBuild: Text {
    Text(verbatim: String(format: "Version %@ • Build %@".localized,
                          Bundle.main.appVersionLong, Bundle.main.appBuild))
  }

  /// Primary dismiss on the update popup: Continue on phone / pad / Mac, Done on tvOS.
  static var confirmTitle: Text {
#if os(tvOS)
    Text("Done")
#else
    Text("Continue")
#endif
  }
}

/// Presents What's New over the signed-in app when some bullet has not been shown on
/// this device. Continue / Done / Menu / outside / the cross records every bullet as seen.
struct WhatsNewPresentation: ViewModifier {
  var isSignedIn: Bool
  @AppStorage("selectedLanguage") private var selectedLanguage: String = (
    Locale.current.language.languageCode?.identifier ?? "en"
  )
  @State private var pending: WhatsNew?
  @State private var showingAllForDebug = false

  func body(content: Content) -> some View {
    content
      .infoPopup(Text("What's new"),
                 subtitle: WhatsNewText.currentBuild,
                 confirmTitle: WhatsNewText.confirmTitle,
                 isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
                 onDismiss: markSeen) {
        WhatsNewUpdateBody(
          pendingBullets: pending?.bullets ?? [],
          languageCode: selectedLanguage,
          showPreviousReleases: !showingAllForDebug
        )
      }
      .onAppear(perform: considerPresenting)
      .onChange(of: isSignedIn) { _, _ in
        considerPresenting()
      }
  }

  private func considerPresenting() {
    guard pending == nil, isSignedIn else { return }
    let catalog = AppChangelog.load()
#if DEBUG
    // `-PIRATICWhatsNew YES` shows every bullet, seen or not — to look at the popup.
    if UserDefaults.standard.bool(forKey: "PIRATICWhatsNew") {
      showingAllForDebug = true
      pending = WhatsNew(version: Bundle.main.appVersionLong,
                         bullets: catalog.newestFirst.flatMap { $0.bullets(languageCode: selectedLanguage) })
      return
    }
#endif
    showingAllForDebug = false
    pending = catalog.pendingWhatsNew(currentVersion: Bundle.main.appVersionLong,
                                      languageCode: selectedLanguage)
  }

  private func markSeen() {
    AppChangelog.load().markSeen(currentVersion: Bundle.main.appVersionLong)
  }
}

extension View {
  func presentsWhatsNew(isSignedIn: Bool) -> some View {
    modifier(WhatsNewPresentation(isSignedIn: isSignedIn))
  }
}

#Preview("What's New") {
  InfoPopupView(title: Text("What's new"),
                subtitle: Text(verbatim: "Версия 1.0 • Сборка 10"),
                confirmTitle: WhatsNewText.confirmTitle) {
    WhatsNewUpdateBody(
      pendingBullets: [
        "В Медиатеке слева — таблетки: Слежу, Продолжить, История и папки закладок.",
        "Баннер на главной снова по центру, соседние карточки выглядывают.",
      ],
      languageCode: "ru",
      showPreviousReleases: false
    )
  }
}

#if !os(tvOS)
#Preview("What's New · one bullet") {
  InfoPopupView(title: Text("What's new"),
                subtitle: Text(verbatim: "Version 1.0 • Build 1"),
                confirmTitle: Text("Continue")) {
    WhatsNewUpdateBody(
      pendingBullets: [
        "iPhone and iPad: Download on a title page no longer quits the app.",
      ],
      languageCode: "en",
      showPreviousReleases: false
    )
  }
}
#endif
