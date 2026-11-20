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
/// is — with its logo letterboxed onto it (`TVPageTile.logoURL`), and under its name what
/// is on air now (`EPGService`). Rows by schedule are a later stage (Asana › TV).
struct TVChannelsView: View {
  @Environment(NavigationState.self) private var navigationState
  @StateObject private var model: TVChannelsModel

  init(model: @autoclosure @escaping () -> TVChannelsModel) {
    _model = StateObject(wrappedValue: model())
  }

  var body: some View {
    RouteStack(tab: .tv) {
      // Once a minute, so a programme that ended gives way to the next under its channel.
      TimelineView(.everyMinute) { timeline in
        page(at: timeline.date)
      }
      // Under the tab bar, as every tab's page is (`MainView.page`).
      .ignoresSafeArea()
      // `load` reuses a fresh `/v1/tv` answer (≤1 h); Retry still calls `fetch`.
      .task { await model.load() }
    }
  }

  private func page(at date: Date) -> some View {
    TVPage(
      sections: sections(at: date),
      status: status,
      accessibilityID: "kinopub.page.tv",
      onSelect: { _, item in
        guard case .tile(let tile) = item,
              let id = Int(tile.id),
              let channel = model.channel(id: id),
              TVChannelsModel.isPlayableStream(channel.stream) else { return }
        navigationState.push(.livePlayer(channel, token: UUID()))
      },
      onRetry: { Task { await model.fetch() } },
      // Stable across the minute TimelineView tick (EPG subtitles change; the list does not),
      // so focus memory survives the player pop.
      contentID: model.channels.map { String($0.id) }.joined(separator: ",")
    )
  }

  /// Five across — the HIG's 320 pt still, which is the logos' own 240×180 at 1080p.
  static let columns = 5

  private func sections(at date: Date) -> [TVPageSection] {
    if model.channels.isEmpty && model.isLoading {
      // The same cells the baked list paints, so a cold load is not a shorter grid.
      return [.placeholder(id: "channels", title: nil, kind: .still, columns: Self.columns,
                           flow: .grid, count: TVChannelCatalog.channels.count)]
    }
    guard !model.channels.isEmpty else { return [] }
    return [.tiles(id: "channels", title: nil, columns: Self.columns, flow: .grid,
                   tiles: model.channels.map { channel in
                     Self.tile(for: channel, onAir: model.nowPlaying(channelID: channel.id, at: date))
                   })]
  }

  /// The logo's plate, or the quiet grey a channel outside the baked list gets.
  private static func plate(for id: Int) -> UIColor {
    guard let hex = TVChannelCatalog.plateHex(for: id) else {
      return UIColor(white: 0.16, alpha: 1)
    }
    return UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
                   green: CGFloat((hex >> 8) & 0xFF) / 255,
                   blue: CGFloat(hex & 0xFF) / 255,
                   alpha: 1)
  }

  /// The line under the tile is what's on air (falling back to the channel name),
  /// focused and at rest — no channel-name swap. Long programmes marquee while
  /// focused (`TVMediaItemContentConfiguration` / system focus marquee).
  static func tile(for channel: TVChannel, onAir: EPGProgram? = nil) -> TVPageTile {
    let program = onAir?.title
    return TVPageTile(id: String(channel.id),
                      title: program ?? channel.title,
                      tint: Self.plate(for: channel.id),
                      style: .flat,
                      logo: Self.logo(for: channel))
  }

  /// Bundled asset when the catalog has one; otherwise the CDN / payload URL.
  static func logo(for channel: TVChannel) -> TVPageLogo? {
    switch TVChannelCatalog.bundledLogo(for: channel.id) {
    case .full(let name):
      return .bundled(name)
    case .mark(let logo, let focusBackground):
      return .bundledMark(logo: logo, focusBackground: focusBackground)
    case nil:
      return channel.logo.flatMap(URL.init(string:)).map { .remote($0) }
    }
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
