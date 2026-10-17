//
//  TVChannelsView.swift
//  KinoPubAppleClient
//

#if os(tvOS)
import SwiftUI
import UIKit
import KinoPubUI
import KinoPubBackend

/// The TV tab: kino.pub's live channels as a grid of their logos, each named under its
/// tile. Select plays the channel's stream in the app's one player, in live mode
/// (`Route.livePlayer`).
///
/// A channel is a drawn tile in the 16:9 still cell — the same section every genre grid
/// is — with its logo letterboxed onto it (`TVPageTile.logoURL`). The schedule, and rows
/// under it, are later stages (ROADMAP).
struct TVChannelsView: View {
  @Environment(NavigationState.self) private var navigationState
  @StateObject private var model: TVChannelsModel

  init(model: @autoclosure @escaping () -> TVChannelsModel) {
    _model = StateObject(wrappedValue: model())
  }

  var body: some View {
    RouteStack(tab: .tv) {
      TVPage(
        sections: sections,
        status: status,
        accessibilityID: "kinopub.page.tv",
        onSelect: { _, item in
          guard case .tile(let tile) = item,
                let id = Int(tile.id),
                let channel = model.channel(id: id) else { return }
          navigationState.push(.livePlayer(channel, token: UUID()))
        },
        onRetry: { Task { await model.fetch() } }
      )
      // Under the tab bar, as every tab's page is (`MainView.page`).
      .ignoresSafeArea()
      .task { await model.fetch() }
      .onAppear { Task { await model.refreshIfStale() } }
    }
  }

  /// Five across — the HIG's 320 pt still, which is the logos' own 240×180 at 1080p.
  static let columns = 5

  private var sections: [TVPageSection] {
    if model.channels.isEmpty && model.isLoading {
      return [.placeholder(id: "channels", title: nil, kind: .still, columns: Self.columns, flow: .grid)]
    }
    guard !model.channels.isEmpty else { return [] }
    return [.tiles(id: "channels", title: nil, columns: Self.columns, flow: .grid,
                   tiles: model.channels.map(Self.tile))]
  }

  static func tile(for channel: TVChannel) -> TVPageTile {
    // A quiet plate while the logo loads, not a colour per channel: the logo is the art.
    TVPageTile(id: String(channel.id),
               title: channel.title,
               tint: UIColor(white: 0.16, alpha: 1),
               style: .flat,
               logoURL: channel.logo.flatMap(URL.init(string:)))
  }

  private var status: TVPageStatus {
    if model.channels.isEmpty, let error = model.loadError {
      return .failed(message: error.userFacingMessage, retryTitle: "Try Again".localized)
    }
    if model.channels.isEmpty && !model.isLoading {
      return .message("No channels on air right now".localized)
    }
    return .content
  }
}
#endif
