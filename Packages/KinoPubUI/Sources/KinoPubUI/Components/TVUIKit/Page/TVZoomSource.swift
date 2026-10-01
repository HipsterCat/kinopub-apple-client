#if os(tvOS)
//
//  TVZoomSource.swift
//  KinoPubUI
//
//  The card a page was opened from, for `TVZoomPresentedController`.
//
//  Selecting a card, or opening its context menu (whose "Go to title" opens the title),
//  records which item of which page it was. The app asks for it by zoom id when it opens
//  the matching page, and the presentation grows the page out of that card and shrinks it
//  back into it on Menu.
//
//  The cell itself is never kept. It is looked up again by the item's id each time the
//  transition needs it: by the time the page is dismissed the row may have reloaded, and
//  the cell that showed the card may be showing another title.
//
//  Two earlier shapes, so they are not tried a third time. Both were SwiftUI's
//  `navigationTransition(.zoom)` on a push:
//  - with no source on tvOS at all: the card jumped and vanished in one frame
//    (Sasha, on device, 2026-09-28);
//  - with a clear `matchedTransitionSource` laid over the selected cell: a plain
//    cross-fade on device (2026-10-01).
//

import SwiftUI
import UIKit

/// A card cell that knows where its art is.
@MainActor
protocol TVZoomSourceCell: UICollectionViewCell {
  /// The zoom grows out of this view's frame and shrinks back into it: the art, not the
  /// caption under it.
  var zoomSourceView: UIView { get }
  /// The rounding of that frame's corners.
  var zoomCornerRadius: CGFloat { get }
  /// The picture the card shows, once it has loaded.
  var zoomArtwork: UIImage? { get }
  /// The card as the zoom starts from it. The page fades in under it while it grows.
  func zoomSnapshot() -> UIView?
}

extension TVZoomSourceCell {
  func zoomSnapshot() -> UIView? {
    zoomSourceView.snapshotView(afterScreenUpdates: false)
  }
}

/// The card a page is being opened from.
@MainActor
public final class TVZoomSource {

  /// Matches the app's `Route.zoomSourceID` for the page this card opens.
  public let id: String
  private weak var page: TVPageCollectionViewController?
  private let item: TVPageItemID
  private let artwork: UIImage?

  init(id: String, page: TVPageCollectionViewController, item: TVPageItemID, artwork: UIImage?) {
    self.id = id
    self.page = page
    self.item = item
    self.artwork = artwork
  }

  /// What the card showed, reduced to its colours: the page's ground while its own
  /// artwork loads, so the zoom grows the card's light instead of an empty frame.
  public private(set) lazy var backdrop: UIImage? = artwork.map(TVZoomSource.colours(of:))

  /// The window the card is in, while it is on screen.
  public var window: UIWindow? { sourceView?.window }

  // MARK: - For the transition

  private var cell: UICollectionViewCell? { page?.visibleCell(for: item) }

  /// Where the card is right now; nil once it has scrolled away or its page has gone.
  var sourceView: UIView? {
    guard let cell else { return nil }
    let view = (cell as? TVZoomSourceCell)?.zoomSourceView ?? cell.contentView
    return view.window == nil ? nil : view
  }

  var cornerRadius: CGFloat {
    (cell as? TVZoomSourceCell)?.zoomCornerRadius ?? 16
  }

  func snapshot() -> UIView? {
    guard let cell else { return nil }
    return (cell as? TVZoomSourceCell)?.zoomSnapshot()
      ?? cell.contentView.snapshotView(afterScreenUpdates: false)
  }

  // MARK: - The pending card

  private static var pending: TVZoomSource?

  /// Called by the page as a card is picked, or its menu opens.
  static func record(_ source: TVZoomSource) {
    pending = source
  }

  /// The card a page with this zoom id is being opened from — only if one was just
  /// picked and is still on screen. Taken once.
  public static func take(id: String) -> TVZoomSource? {
    guard let source = pending, source.id == id, source.sourceView != nil else { return nil }
    pending = nil
    return source
  }

  // MARK: - Art

  /// An image view of the art alone, for a card that is all art.
  static func artworkSnapshot(_ image: UIImage?, cornerRadius: CGFloat) -> UIView? {
    guard let image else { return nil }
    let view = UIImageView(image: image)
    view.contentMode = .scaleAspectFill
    view.clipsToBounds = true
    view.layer.cornerRadius = cornerRadius
    view.layer.cornerCurve = .continuous
    return view
  }

  /// The art averaged down to a few pixels across, then drawn back up to a small smooth
  /// bitmap: its colours and where they sit, nothing of the picture. Stretched over the
  /// screen it reads as the card's light rather than a blurry copy of it, and it is two
  /// tiny draws instead of a blur pass over a full-screen layer on every frame.
  nonisolated private static func colours(of image: UIImage) -> UIImage {
    let aspect = max(image.size.width, 1) / max(image.size.height, 1)
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    let tiny = CGSize(width: 6, height: max(2, (6 / aspect).rounded()))
    let averaged = UIGraphicsImageRenderer(size: tiny, format: format).image { context in
      context.cgContext.interpolationQuality = .high
      image.draw(in: CGRect(origin: .zero, size: tiny))
    }
    let smooth = CGSize(width: 48, height: max(16, (48 / aspect).rounded()))
    return UIGraphicsImageRenderer(size: smooth, format: format).image { context in
      context.cgContext.interpolationQuality = .high
      averaged.draw(in: CGRect(origin: .zero, size: smooth))
    }
  }
}

/// The card's colours, handed to the page it opened. The page draws them only while it
/// has nothing of its own and only if it is the page the card opened (`id`): a page
/// pushed further down the same stack gets the same environment.
public struct TVZoomBackdrop {
  public let id: String
  public let image: UIImage

  public init(id: String, image: UIImage) {
    self.id = id
    self.image = image
  }
}

public extension EnvironmentValues {
  @Entry var zoomBackdrop: TVZoomBackdrop? = nil
}

extension TVPageItem {
  /// Matches the app's `Route.zoomSourceID` for the route this item opens.
  var zoomSourceID: String? {
    switch self {
    case .card(let card): return "media-\(card.id)"
    case .feature(let feature): return "media-\(feature.card.id)"
    case .person(let person): return "person-\(person.id)"
    case .chip, .tile, .placeholder: return nil
    }
  }
}
#endif
