//
//  RouteStack.swift
//  KinoPubAppleClient
//
//  One place where a tab's stack, its path, and the destination registry meet.
//
//  Before this file, ten screens each wrote the same four lines — a `NavigationStack`
//  bound to one of `NavigationState`'s arrays, a `.navigationDestination(for: Route.self)`
//  building a `RouteDestination`, and a `.navigationStackActive` gate — and they had
//  already drifted: two passed a zoom namespace, eight didn't, and only some carried the
//  gate. A destination registry that exists in ten copies is the catalogue rule being
//  broken at the navigation layer (.claude/skills/tvos-surface/SKILL.md).
//

import SwiftUI
import KinoPubUI

/// A tab's whole navigation surface: the stack, the path it is bound to, the shared
/// destination registry, and the "only the selected tab exposes a stack" gate.
///
/// `zoom` is opt-in per stack, not a default, because the zoom source modifier is
/// `#if os(iOS)`-only (`KinoPubUI.MediaZoomSourceModifier`) and publishing a namespace
/// on a stack whose cards never mark a source gives the destination a transition with
/// nothing to match. Home and the catalog tabs publish one; the rest deliberately do not.
struct RouteStack<Content: View>: View {

  let tab: NavigationTabs
  var zoom: Bool = false
  @ViewBuilder var content: () -> Content

  @Environment(NavigationState.self) private var navigationState
  @Namespace private var zoomNamespace

  var body: some View {
    NavigationStack(path: navigationState.path(for: tab)) {
      content()
        .environment(\.scrollToTopRequest, navigationState.scrollToTopRequests[tab] ?? 0)
        // The registry as a view of its own, beside the root rather than around it: its
        // one input is the namespace, so a root that re-renders (Home's `MainView` does
        // on every catalog change, several times in a launch frame) leaves it alone. On
        // the root, every pass re-registered the destinations and SwiftUI warned
        // `Update NavigationRequestObserver tried to update multiple times per frame`.
        .background { RouteDestinationRegistry(zoom: zoom ? zoomNamespace : nil) }
#if os(tvOS)
        .tvNavigationZoom()
#endif
    }
    .environment(\.zoomTransitionNamespace, zoom ? zoomNamespace : nil)
    .navigationStackActive(for: tab, selected: navigationState.selectedTab)
  }
}

/// `appRouteDestinations` on nothing, so it re-runs only when the namespace does.
private struct RouteDestinationRegistry: View {
  let zoom: Namespace.ID?

  var body: some View {
    Color.clear
      .accessibilityHidden(true)
      .appRouteDestinations(zoom: zoom, zoomsRoot: false)
  }
}

extension View {
  /// The app's single `Route` destination registry.
  ///
  /// Use this directly only on a stack `RouteStack` cannot own — one whose path is local
  /// `@State` rather than a tab's shared array (bookmark-folder tabs, tvOS Settings).
  /// Everything else should be a `RouteStack`.
  ///
  /// `zoomsRoot`: tvOS's zoom on the view this sits on, the stack's root — off where the
  /// registry is not the root (`RouteStack`, which zooms its root itself).
  func appRouteDestinations(zoom namespace: Namespace.ID? = nil, zoomsRoot: Bool = true) -> some View {
    navigationDestination(for: Route.self) { route in
      RouteDestination(route: route,
                       linkProvider: AppRoutesLinkProvider(),
                       transitionNamespace: namespace)
        // A pushed page does not scroll with its section's memory; a title page brings
        // its own (`MediaItemModel.scrollMemory`).
        .environment(\.scrollMemory, nil)
        // Nor with its section's side margins: a page that bleeds measures its own
        // (`PageMargins`).
        .environment(\.pageMargins, nil)
#if os(tvOS)
        // On every page too: a stack opened straight onto a title never shows its root.
        .tvNavigationZoom()
#endif
    }
#if os(tvOS)
    // tvOS's own scale in/out instead of the stack's crossfade (`TVNavigationZoom`).
    .modifier(TVRootZoom(isOn: zoomsRoot))
#endif
  }
}

#if os(tvOS)
private struct TVRootZoom: ViewModifier {
  let isOn: Bool

  func body(content: Content) -> some View {
    if isOn { content.tvNavigationZoom() } else { content }
  }
}
#endif
