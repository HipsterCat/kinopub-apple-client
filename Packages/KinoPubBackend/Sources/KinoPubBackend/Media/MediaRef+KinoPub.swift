//
//  MediaRef+KinoPub.swift
//
//  kino.pub's ways of naming a thing, as one `MediaRef`.
//

import Foundation
import KinoPubMedia

public extension WatchingMetadata {
  /// Nil for an episode never stamped with its series id (`isResolved`): a ref to item 0
  /// would read and write some other title's state.
  var mediaRef: MediaRef? {
    isResolved ? MediaRef(itemID: id, season: season, number: video) : nil
  }

  /// What `/v1/watching` takes for a ref.
  init(_ ref: MediaRef) {
    self.init(id: ref.itemID, video: ref.number, season: ref.season)
  }
}

public extension PlayableItem {
  /// The thing playing: an episode, a film's version, a download.
  var mediaRef: MediaRef? { metadata.mediaRef }
}

public extension MediaItem {
  /// The title as a whole — what watchlist, bookmarks and a film's watched mark are
  /// kept under.
  var titleRef: MediaRef { .title(id) }
}
