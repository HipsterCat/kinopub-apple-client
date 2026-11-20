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
    // `@Bindable` projects `$navigationState.*Routes` so `NavigationStack` is not handed
    // a brand-new `Binding` value from `path(for:)` on every body pass — that was one
    // source of `Update NavigationAuthority bound path tried to update multiple times
    // per frame` when several tab stacks stayed mounted.
    @Bindable var navigationState = navigationState
    NavigationStack(path: guardedPath(bindable: navigationState)) {
      content()
        .environment(\.scrollToTopRequest, navigationState.scrollToTopRequests[tab] ?? 0)
        .appRouteDestinations(zoom: zoom ? zoomNamespace : nil)
    }
    .environment(\.zoomTransitionNamespace, zoom ? zoomNamespace : nil)
    .navigationStackActive(for: tab, selected: navigationState.selectedTab)
  }

  /// The tab's route array as a Binding, with the unselected-empty and no-op guards that
  /// `NavigationState.path(for:)` also applies for non-`RouteStack` call sites.
  private func guardedPath(bindable state: NavigationState) -> Binding<[Route]> {
    let tab = self.tab
    let base = Binding<[Route]>(
      get: {
        guard let keyPath = NavigationState.routeKeyPath(for: tab) else { return [] }
        return state[keyPath: keyPath]
      },
      set: { routes in
        guard let keyPath = NavigationState.routeKeyPath(for: tab) else { return }
        // A section's stack torn down on leaving it writes back an empty path; that is
        // not the viewer going back (Sasha, 2026-10-31).
        if routes.isEmpty, tab != state.selectedTab, !state[keyPath: keyPath].isEmpty {
          return
        }
        guard state[keyPath: keyPath] != routes else { return }
        state[keyPath: keyPath] = routes
        let ids = MediaItemModelCache.itemIDs(in: routes)
        MediaItemModelCache.shared.keep(only: ids, on: tab)
      }
    )
    return base
  }
}

extension View {
  /// The app's single `Route` destination registry.
  ///
  /// Use this directly only on a stack `RouteStack` cannot own — one whose path is local
  /// `@State` rather than a tab's shared array (bookmark-folder tabs, tvOS Settings).
  /// Everything else should be a `RouteStack`.
  func appRouteDestinations(zoom namespace: Namespace.ID? = nil) -> some View {
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
    .tvNavigationZoom()
#endif
  }
}
