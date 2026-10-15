//
//  TopShelfRouter.swift
//  KinoPubAppleClient
//

#if os(tvOS)
import Foundation
import KinoPubUI
import OSLog
import KinoPubLogging

/// Opens a `kinopub://` link from the Top Shelf on Watch Now's stack, the way the same
/// card on Home would: the title's page, or the player over it for a Continue Watching
/// card. Menu from either lands on the title, then Home.
@MainActor
enum TopShelfRouter {
  static func open(_ link: TopShelfLink, navigation: NavigationState, context: AppContext = .shared) {
    let itemID: Int
    switch link {
    case .title(let id), .play(let id): itemID = id
    }
    navigation.selectBrowseTab(.home)
    navigation.mainRoutes = [.detailsById(itemID)]

    // Play resumes what Continue Watching offers. A title that is not there (a catalog
    // poster, or a card that left the row since the shelf was written) has nothing to
    // resume, so its page is the answer.
    guard case .play = link,
          let card = HomeCatalog.paintedContinueWatchingCards(store: context.contentStore,
                                                              localProgressStore: context.localProgressStore)
            .first(where: { $0.itemID == itemID }) else { return }
    Task {
      do {
        let (_, playable) = try await MediaCardMenuCoordinator.resolve(card, using: context.contentService)
        // The viewer may have moved on while the details loaded.
        guard navigation.mainRoutes == [.detailsById(itemID)] else { return }
        navigation.mainRoutes.append(.player(playable, token: UUID()))
      } catch {
        Logger.app.error("TopShelf: could not resolve \(itemID) for playback: \(error)")
      }
    }
  }
}
#endif
