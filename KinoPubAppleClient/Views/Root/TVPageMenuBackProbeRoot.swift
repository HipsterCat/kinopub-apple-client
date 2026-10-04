#if os(tvOS) && DEBUG
//
//  TVPageMenuBackProbeRoot.swift
//  KinoPubAppleClient
//
//  DEBUG `-KINOPUBMenuBackProbe`: the templates gallery inside production's
//  `.tabBarOnly` `TabView`. Rivulet's Menu interceptor exists because
//  `.sidebarAdaptable` swallows the press before `.onExitCommand` /
//  `pressesBegan`. We do not ship that interceptor; this root is how a UI test
//  records whether our tab bar delivers Menu to the page at all.
//

import SwiftUI
import KinoPubUI

struct TVPageMenuBackProbeRoot: View {
  var body: some View {
    TabView {
      Tab(value: 0) {
        TVPageTemplatesGallery()
      } label: {
        Text("Watch Now")
      }
      Tab(value: 1) {
        Color.clear
          .accessibilityIdentifier("kinopub.probe.movies")
      } label: {
        Text("Movies")
      }
    }
    .tabViewStyle(.tabBarOnly)
  }
}
#endif
