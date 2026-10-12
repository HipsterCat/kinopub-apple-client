//
//  TitleLogoSlot.swift
//  KinoPubUI
//
//  One slot: the title logo, or the lettered name after a confirmed miss. Empty
//  (layout reserved) while a lookup is in flight. Completions are request-scoped.
//

import SwiftUI

/// The hero / banner title slot. See ``TitleLogoPresentationPolicy``.
public struct TitleLogoSlot<Title: View>: View {
  private let url: URL?
  private let lookupComplete: Bool
  private let maxWidth: CGFloat
  private let maxHeight: CGFloat
  private let policy: TitleLogoPresentationPolicy
  private let title: () -> Title

  @State private var requestID = 0
  @State private var image: Image?
  @State private var imageFailed = false
  @State private var timedOut = false

  public init(
    url: URL?,
    lookupComplete: Bool,
    maxWidth: CGFloat,
    maxHeight: CGFloat,
    policy: TitleLogoPresentationPolicy = .whenResolved,
    @ViewBuilder title: @escaping () -> Title
  ) {
    self.url = url
    self.lookupComplete = lookupComplete
    self.maxWidth = maxWidth
    self.maxHeight = maxHeight
    self.policy = policy
    self.title = title
  }

  public var body: some View {
    let cached = url.flatMap { Artwork.cachedImage(for: $0) }
    let mark = policy.mark(
      hasCachedLogo: cached != nil,
      lookupComplete: lookupComplete,
      hasLogoURL: url != nil,
      imageReady: image != nil,
      imageFailed: imageFailed || timedOut,
      elapsed: timedOut ? TitleLogoPresentationPolicy.missTimeout : 0
    )
    Group {
      switch mark {
      case .logo:
        logoView(image ?? cached.map { Image(platformImage: $0) })
      case .text:
        title()
      case .empty:
        Color.clear
          .frame(maxWidth: maxWidth, maxHeight: maxHeight, alignment: .leading)
      }
    }
    .frame(maxWidth: maxWidth, maxHeight: maxHeight, alignment: .leading)
    .task(id: requestKey) { await resolve() }
  }

  @ViewBuilder
  private func logoView(_ image: Image?) -> some View {
    if let image {
      image
        .resizable()
        .scaledToFit()
        .frame(maxWidth: maxWidth, maxHeight: maxHeight, alignment: .leading)
    } else {
      Color.clear
        .frame(maxWidth: maxWidth, maxHeight: maxHeight, alignment: .leading)
    }
  }

  /// URL plus whether metadata has settled — a title that gains a URL later must
  /// not keep the previous request's miss.
  private var requestKey: String {
    "\(url?.absoluteString ?? "none")|\(lookupComplete)"
  }

  private enum LoadEvent {
    case loaded
    case fail
    case timeout
    case cancelled
  }

  @MainActor
  private func resolve() async {
    requestID += 1
    let id = requestID
    image = nil
    imageFailed = false
    timedOut = false

    if let url, let cached = Artwork.cachedImage(for: url) {
      image = Image(platformImage: cached)
      return
    }

    if lookupComplete, url == nil {
      return
    }

    let started = Date()
    let logoURL = url
    await withTaskGroup(of: LoadEvent.self) { group in
      group.addTask {
        try? await Task.sleep(
          nanoseconds: UInt64(TitleLogoPresentationPolicy.missTimeout * 1_000_000_000)
        )
        return .timeout
      }
      if let logoURL {
        group.addTask {
          do {
            _ = try await Artwork.image(for: logoURL)
            return .loaded
          } catch is CancellationError {
            return .cancelled
          } catch {
            return .fail
          }
        }
      }
      while let event = await group.next() {
        guard policy.shouldApply(requestID: id, current: requestID) else {
          group.cancelAll()
          return
        }
        switch event {
        case .loaded:
          let elapsed = Date().timeIntervalSince(started)
          if policy.shouldAdoptLogo(elapsed: elapsed, alreadyShowingText: timedOut),
             let logoURL, let decoded = Artwork.cachedImage(for: logoURL) {
            image = Image(platformImage: decoded)
            imageFailed = false
          }
          group.cancelAll()
          return
        case .fail:
          imageFailed = true
          group.cancelAll()
          return
        case .timeout:
          if image == nil, !imageFailed { timedOut = true }
          // Let a late decode finish so it warms the cache; it will not replace text.
        case .cancelled:
          group.cancelAll()
          return
        }
      }
    }
  }
}
