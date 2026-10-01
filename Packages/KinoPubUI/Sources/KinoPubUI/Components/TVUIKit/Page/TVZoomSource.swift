#if os(tvOS)
//
//  TVZoomSource.swift
//  KinoPubUI
//
//  The system zoom transition (`navigationTransition(.zoom)`, tvOS 18+) for cards that
//  live in a UIKit collection.
//
//  SwiftUI's zoom needs a SwiftUI source view (`matchedTransitionSource`), and every
//  tvOS card is a UIKit cell inside `TVPage`. So the page reports the selected cell's
//  frame, and an invisible SwiftUI view laid over the page at exactly that frame is the
//  source. The detail page zooms out of the card's rectangle and back into it on Menu;
//  the transition itself is the system's.
//
//  Two earlier shapes are worth remembering:
//  - `matchedTransitionSource` on the card itself masked the lockup and clipped the
//    system focus lift (`MediaZoomSourceModifier`, iOS only for that reason). The source
//    here is a separate clear view; the cell is untouched.
//  - The destination used to ask for a zoom whenever its stack published a namespace,
//    with no source on tvOS at all — the card jumped and vanished in one frame
//    (Sasha, on device, 2026-09-28). The destination now zooms only for an id a page has
//    registered (`hasSource(for:)`), and pushes plainly otherwise.
//

import SwiftUI
import Observation

/// One per navigation stack: which card the next push zooms out of.
@MainActor
@Observable
public final class TVZoomSourceStore {

  public struct Anchor: Equatable {
    public let id: String
    /// In the reporting page's own coordinate space.
    public let frame: CGRect
    let owner: UUID
  }

  /// Read only by the overlay of the page that owns it, so a selection re-renders that
  /// one clear view and nothing else.
  public private(set) var anchor: Anchor?

  /// Every id a page has offered as a source. Not observed: the destination checks it
  /// once when it is built, and it only ever grows, so a destination rebuilt later keeps
  /// the transition it was pushed with.
  @ObservationIgnored private var registeredIDs: Set<String> = []
  /// The art the card was showing, by zoom id. The detail page has nothing to draw
  /// until its item loads, and a zoom out of a card into an empty page reads as a blink;
  /// this lets it open on the card's own picture, blurred.
  @ObservationIgnored private var art: [String: URL] = [:]

  public init() {}

  func register(id: String, frame: CGRect, owner: UUID, art url: URL?) {
    registeredIDs.insert(id)
    if let url { art[id] = url }
    let next = Anchor(id: id, frame: frame, owner: owner)
    if anchor != next { anchor = next }
  }

  /// Whether a push to this zoom id has a source to zoom out of.
  public func hasSource(for id: String) -> Bool {
    registeredIDs.contains(id)
  }

  /// What the source card was showing, for a page that has nothing of its own yet.
  public func art(for id: String) -> URL? {
    art[id]
  }
}

public extension EnvironmentValues {
  /// Published by a tab's stack together with `zoomTransitionNamespace`.
  @Entry var zoomSourceStore: TVZoomSourceStore? = nil
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

/// The clear stand-in laid over the page at the selected card's frame.
struct TVZoomSourceOverlay: View {
  let store: TVZoomSourceStore
  let owner: UUID
  let namespace: Namespace.ID

  var body: some View {
    if let anchor = store.anchor, anchor.owner == owner {
      Color.clear
        .frame(width: anchor.frame.width, height: anchor.frame.height)
        .matchedTransitionSource(id: anchor.id, in: namespace)
        // Layout, not `.offset`: the transition reads the source's laid-out frame.
        .padding(EdgeInsets(top: anchor.frame.minY, leading: anchor.frame.minX,
                            bottom: 0, trailing: 0))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
  }
}
#endif
