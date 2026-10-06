#if os(tvOS)
//
//  MediaItemTVPage.swift
//  KinoPubAppleClient
//
//  The tvOS detail page under the hero: `MediaItemTVSections` says what is on it, one
//  `TVEmbeddedPage` draws it, and this is what a Select on any of it does.
//
//  Navigation goes through the same hook the TVUIKit rails use (`mediaNavigation`), a card
//  that was cut short opens the shared info popup (the clipped thing is the trigger), a
//  hidden spoiler shows itself in place, and the stills open a gallery.
//

import SwiftUI
import KinoPubBackend
import KinoPubMetadata
import KinoPubUI

struct MediaItemTVPage: View {
  @ObservedObject var model: MediaItemModel
  /// One coordinator for every poster row on the page, shared with the page above it.
  @ObservedObject var cardMenu: MediaCardMenuCoordinator

  @Environment(NavigationState.self) private var navigationState
  @Environment(\.mediaNavigation) private var mediaNavigation

  @State private var revealedFacts: Set<String> = []
  @State private var popup: Popup?
  @State private var showsGallery = false
  @State private var showsVoteChoice = false

  /// What the info popup holds. Content comes from the model at the moment of the tap, so
  /// a popup is only the id of the thing that was selected.
  enum Popup: Identifiable, Equatable {
    case review(index: Int)
    case fact(text: String)
    case spec(id: String)

    var id: String {
      switch self {
      case .review(let index): return "review.\(index)"
      case .fact(let text): return "fact.\(text.hashValue)"
      case .spec(let id): return "spec.\(id)"
      }
    }
  }

  private var input: MediaItemTVSections.Input {
    .init(mediaItem: model.mediaItem,
          metadata: model.externalMetadata,
          likeCount: model.likeCount,
          dislikeCount: model.dislikeCount,
          relatedRows: model.relatedRows,
          pendingShelfTitles: model.pendingRelatedShelfTitles,
          revealedFacts: revealedFacts)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: MediaItemLayout.sectionSpacing) {
      TVEmbeddedPage(
        sections: MediaItemTVSections.make(input),
        accessibilityID: "kinopub.page.detail",
        onSelect: { _, item in select(item) },
        contextMenuProvider: { card in
          MediaCardContextMenus.entries(for: card,
                                        surface: .shelf,
                                        menu: cardMenu,
                                        pushRoute: { navigationState.push($0) },
                                        openURL: { _ in })
        }
      )
      // Without a full-width focus section Up from the right side of a row can miss the
      // hero and jump to the tab bar — the engine searches straight up.
      .focusSection()

      // Where the title came from and when — and the metadata debug log, a dev tool.
      MediaItemInfoColumns.InfoFooter(mediaItem: model.mediaItem,
                                      attribution: model.externalMetadata.attribution,
                                      tmdbId: model.externalMetadata.tmdbId,
                                      isSeries: model.mediaItem.isSeries,
                                      debugLog: model.externalMetadata.debugLog)
        .padding(.horizontal, MediaItemLayout.horizontalInset)
        // HIG: 60 pt from the bottom of the screen, which is where the page ends.
        .padding(.bottom, 60)
    }
    .infoPopup(popupTitle, isPresented: popupBinding) { popupContent }
    .fullScreenCover(isPresented: $showsGallery) {
      StillsGallery(stills: model.externalMetadata.stills)
    }
    .confirmationDialog("MediaItem_VoteChoice".localized, isPresented: $showsVoteChoice, titleVisibility: .visible) {
      Button("Like".localized) { model.vote(up: true) }
      Button("Dislike".localized) { model.vote(up: false) }
      Button("Cancel".localized, role: .cancel) {}
    }
  }

  // MARK: - Select

  private func select(_ item: TVPageItem) {
    switch item {
    case .card(let card):
      let destination = model.relatedItem(forCardID: card.id)
        .map { model.linkProvider.link(for: $0) } ?? Route.detailsById(card.id)
      mediaNavigation?(destination)

    case .person(let card):
      guard let person = MediaItemTVSections.person(from: card) else { return }
      mediaNavigation?(model.linkProvider.person(for: person))

    case .chip(let chip):
      guard let target = MediaItemTVSections.searchTarget(forChip: chip.id, in: model.mediaItem) else { return }
      navigationState.openSearch(filter: target.filter, title: target.title)

    case .info(let card):
      select(card)

    case .banner, .feature, .masthead, .groupTitle, .placeholder, .tile:
      break
    }
  }

  private func select(_ card: TVPageInfoCard) {
    switch card {
    case .rating(let rating):
      // kino.pub's own score is the one the viewer can add to — once: votes are one-shot.
      if rating.id == MediaItemTVSections.ID.kinoPubScore, model.myVote == .none {
        showsVoteChoice = true
      }

    case .review(let review):
      if let index = Int(review.id) { popup = .review(index: index) }

    case .fact(let fact):
      if fact.isHidden {
        revealedFacts.insert(fact.id)
      } else {
        popup = .fact(text: fact.text)
      }

    case .gallery:
      showsGallery = true

    case .spec(let spec):
      popup = .spec(id: spec.id)
    }
  }

  // MARK: - Popup

  private var popupBinding: Binding<Bool> {
    Binding(get: { popup != nil }, set: { if !$0 { popup = nil } })
  }

  private var popupTitle: Text {
    switch popup {
    case .review(let index):
      let reviews = model.externalMetadata.reviews
      guard reviews.indices.contains(index) else { return Text("Reviews") }
      let review = reviews[index]
      return Text(review.title.isEmpty ? review.author : review.title)
    case .fact:
      return Text("MediaItem_FactsTitle")
    case .spec(let id):
      return Text(specTitle(id))
    case nil:
      return Text("")
    }
  }

  @ViewBuilder
  private var popupContent: some View {
    switch popup {
    case .review(let index):
      let reviews = model.externalMetadata.reviews
      if reviews.indices.contains(index) {
        ReviewPopupBody(review: reviews[index])
      }
    case .fact(let text):
      Text(text)
        .font(InfoPopupMetrics.bodyFont)
        .foregroundStyle(Color.KinoPub.text)
        .multilineTextAlignment(.leading)
    case .spec(let id):
      if let spec = fullSpec(id) {
        SpecPopupBody(spec: spec)
      }
    case nil:
      EmptyView()
    }
  }

  /// A column with everything in it — every language, not the ones that fit.
  private func fullSpec(_ id: String) -> TVPageInfoCard.Spec? {
    var full = input
    full.showsEveryLanguage = true
    for section in MediaItemTVSections.specifications(full) {
      for group in section.groups {
        for case .info(.spec(let spec)) in group.items where spec.id == id { return spec }
      }
    }
    return nil
  }

  private func specTitle(_ id: String) -> String {
    fullSpec(id)?.title ?? ""
  }
}

// MARK: - Popup bodies

/// A review read in full: the text, then who wrote it, when, and how it was meant.
private struct ReviewPopupBody: View {
  let review: Review

  var body: some View {
    VStack(alignment: .leading, spacing: InfoPopupMetrics.contentSpacing) {
      Text(review.body)
        .font(InfoPopupMetrics.bodyFont)
        .foregroundStyle(Color.KinoPub.text)
        .multilineTextAlignment(.leading)
      HStack(spacing: 16) {
        if let sentiment = review.sentimentTitle {
          Text(sentiment).foregroundStyle(review.sentimentColor)
        }
        Text(review.author).foregroundStyle(.secondary)
        if let date = review.displayDate {
          Text(date).foregroundStyle(.secondary)
        }
      }
      .font(.callout)
    }
  }
}

/// A specification column as a list, nothing folded.
private struct SpecPopupBody: View {
  let spec: TVPageInfoCard.Spec

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      ForEach(spec.rows, id: \.id) { row in
        HStack(spacing: 12) {
          switch row.leading {
          case .emoji(let emoji)?: Text(emoji)
          case .symbol(let name)?: Image(systemName: name).foregroundStyle(.secondary)
          case nil: EmptyView()
          }
          Text(row.text)
            .font(font(for: row.style))
            .foregroundStyle(row.style == .caption || row.style == .detail ? Color.secondary : Color.KinoPub.text)
          if let secondary = row.secondary {
            Text(secondary).font(.caption).foregroundStyle(.secondary)
          }
          ForEach(row.badges, id: \.self) { badge in
            Text(badge)
              .font(.caption2.weight(.bold))
              .padding(.horizontal, 6)
              .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.KinoPub.text, lineWidth: 1.5))
          }
        }
        .padding(.top, row.style == .language || row.style == .caption ? 8 : 0)
      }
    }
  }

  private func font(for style: TVPageInfoCard.Spec.Row.Style) -> Font {
    switch style {
    case .caption, .detail: return .caption
    case .language: return .body.weight(.medium)
    default: return .body
    }
  }
}

// MARK: - Gallery

/// The title's stills, one to a page: Left and Right turn it (a swipe on the remote's
/// surface is the same move), Menu closes it. Paged by hand rather than by a page-style
/// `TabView` — that pages on swipes only, and a D-pad press went nowhere.
private struct StillsGallery: View {
  let stills: [StillImage]
  @State private var page = 0

  var body: some View {
    ZStack(alignment: .bottom) {
      Color.black.ignoresSafeArea()
      if stills.indices.contains(page) {
        CachedRemoteImage(url: stills[page].url, contentMode: .fit,
                          placeholder: { ProgressView() },
                          failure: {
                            Image(systemName: "photo.badge.exclamationmark")
                              .font(.largeTitle)
                              .foregroundStyle(.secondary)
                          })
          .id(page)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .padding(60)
          .transition(.opacity)
      }
      Text("\(page + 1) / \(stills.count)")
        .font(.callout.monospacedDigit())
        .foregroundStyle(.secondary)
        .padding(.bottom, 24)
    }
    .animation(.easeOut(duration: 0.2), value: page)
    // Nothing here is a control; a focusable surface is what receives the remote's moves.
    .focusable()
    .onMoveCommand { direction in
      switch direction {
      case .left: page = max(page - 1, 0)
      case .right: page = min(page + 1, max(stills.count - 1, 0))
      default: break
      }
    }
  }
}
#endif
