//
//  WhatsNewSheet.swift
//  KinoPubAppleClient
//
//  What's New, in the shared `InfoPopup`: once at launch for the bullets this device
//  has not shown yet (Continue / Done / Menu / tap outside marks them seen), and the
//  whole history from Settings › About.
//

import SwiftUI
import KinoPubUI

/// Notes as a bulleted list, at the popup's body size.
struct ChangelogBullets: View {
  let bullets: [String]

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      ForEach(Array(bullets.enumerated()), id: \.offset) { _, bullet in
        HStack(alignment: .firstTextBaseline, spacing: 14) {
          Text(verbatim: "•")
            .foregroundStyle(Color.KinoPub.text)
          Text(verbatim: bullet)
            .foregroundStyle(Color.KinoPub.text)
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
        .foregroundStyle(Color.KinoPub.subtitle)
    } else {
      VStack(alignment: .leading, spacing: InfoPopupMetrics.contentSpacing * 1.5) {
        ForEach(entries) { entry in
          VStack(alignment: .leading, spacing: InfoPopupMetrics.contentSpacing) {
            Text(verbatim: String(format: "Version %@".localized, entry.version))
              .font(InfoPopupMetrics.subtitleFont)
              .foregroundStyle(Color.KinoPub.subtitle)
            ChangelogBullets(bullets: entry.bullets(languageCode: languageCode))
          }
        }
      }
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
/// this device. Continue / Done / Menu / outside dismiss records every bullet as seen.
struct WhatsNewPresentation: ViewModifier {
  var isSignedIn: Bool
  @AppStorage("selectedLanguage") private var selectedLanguage: String = (
    Locale.current.language.languageCode?.identifier ?? "en"
  )
  @State private var pending: WhatsNew?

  func body(content: Content) -> some View {
    content
      .infoPopup(Text("What's new"),
                 subtitle: WhatsNewText.currentBuild,
                 confirmTitle: WhatsNewText.confirmTitle,
                 isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
                 onDismiss: markSeen) {
        ChangelogBullets(bullets: pending?.bullets ?? [])
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
    // `-KINOPUBWhatsNew YES` shows every bullet, seen or not — to look at the popup.
    if UserDefaults.standard.bool(forKey: "KINOPUBWhatsNew") {
      pending = WhatsNew(version: Bundle.main.appVersionLong,
                         bullets: catalog.newestFirst.flatMap { $0.bullets(languageCode: selectedLanguage) })
      return
    }
#endif
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
    ChangelogBullets(bullets: [
      "В Медиатеке слева — таблетки: Слежу, Продолжить, История и папки закладок.",
      "Баннер на главной снова по центру, соседние карточки выглядывают.",
    ])
  }
}

#if !os(tvOS)
#Preview("What's New · one bullet") {
  InfoPopupView(title: Text("What's new"),
                subtitle: Text(verbatim: "Version 1.0 • Build 1"),
                confirmTitle: Text("Continue")) {
    ChangelogBullets(bullets: [
      "iPhone and iPad: Download on a title page no longer quits the app.",
    ])
  }
}
#endif
