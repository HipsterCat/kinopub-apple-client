//
//  MediaCardPlaySplitLink.swift
//  PiraticUI
//
//  Continue Watching / Recently Watched landscape cards: still → player, title → detail.
//

import SwiftUI

/// Split hit targets for a play-primary landscape card. The still (and its play chrome)
/// resumes; the caption under it opens the title / episode page. Title fades to ~0.8
/// under the pointer.
public struct MediaCardPlaySplitLink: View {
  private let card: MediaCard
  private let caption: MediaCardCaption
  private let detail: any Hashable
  private let onPlay: () -> Void

#if !os(tvOS)
  @State private var titleHovered = false
#endif

  public init(card: MediaCard,
              caption: MediaCardCaption,
              detail: any Hashable,
              onPlay: @escaping () -> Void) {
    self.card = card
    self.caption = caption
    self.detail = detail
    self.onPlay = onPlay
  }

  public var body: some View {
    VStack(alignment: .center, spacing: Metrics.cardCaptionSpacing) {
      Button(action: onPlay) {
        MediaCardView(card: card, caption: .none)
      }
#if os(tvOS)
      .buttonStyle(.borderless)
#else
      .buttonStyle(MediaCardButtonStyle())
#endif

      NavigationLink(value: detail) {
        MediaCardView(card: card, caption: caption, showsArtwork: false)
      }
#if os(tvOS)
      .buttonStyle(.borderless)
#else
      .buttonStyle(MediaCardButtonStyle())
      .opacity(titleHovered ? 0.8 : 1)
      .onHover { titleHovered = $0 }
      .animation(.easeOut(duration: 0.2), value: titleHovered)
#endif
    }
  }
}
