#if os(tvOS) && DEBUG
//
//  TVSearchFixtureRoot.swift
//  KinoPubAppleClient
//
//  DEBUG `-KINOPUBSearchFixture`: the tvOS search screen as production has it — first tab
//  of a `.tabBarOnly` `TabView`, the system keyboard, suggestions, our results page — with
//  the templates gallery's posters for any query and no session. For layout tests of the
//  results against both system keyboards (`-ForceGridKeyboard YES` puts it on the left).
//

import SwiftUI
import KinoPubUI

struct TVSearchFixtureRoot: View {
  @State private var tab = 0
  @State private var text = DebugLaunch.searchQuery ?? "ма"

  var body: some View {
    tabRoot
  }

  /// Pre-warm runs before the `TabView` builds Search, so the keyboard is already stood up.
  private var tabRoot: some View {
    TVSearchChrome.prewarm()
    return TabView(selection: $tab) {
      Tab(value: 0) {
        TVSearchPage(
          sections: TVPageTemplatesGallery.searchSections,
          text: text,
          placeholder: "Search".localized,
          suggestions: [TVSearchSuggestion("Нолан", kind: .recent),
                        TVSearchSuggestion("Тарантино", kind: .suggested),
                        TVSearchSuggestion("Вильнёв", kind: .suggested)],
          onTextChange: { text = $0 },
          onSelect: { _, _ in }
        )
      } label: {
        Image(systemName: "magnifyingglass")
      }
      Tab(value: 1) {
        Color.clear
      } label: {
        Text("Watch Now")
      }
    }
    .tabViewStyle(.tabBarOnly)
  }
}
#endif
