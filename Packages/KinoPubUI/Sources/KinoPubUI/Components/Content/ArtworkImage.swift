//
//  ArtworkImage.swift
//  KinoPubUI
//
//  The artwork primitive: `AsyncImage`'s shape — a phase you switch on — running on the
//  shared `Artwork` pipeline instead of `URLCache`. Everything else in the stack is this
//  plus a configuration: `CachedRemoteImage` is the sticky, placeholder/failure form,
//  `FallbackRemoteImage` the try-these-in-order form.
//
//  It exists because a page's states are not always the same shape. A title logo that
//  fails becomes a text block with its own geometry, and the success image is framed to
//  the logo box — a fixed content mode cannot say that. Reach for `CachedRemoteImage`
//  first; take this when the states genuinely differ.
//

import SwiftUI

/// Mirrors `AsyncImagePhase` so a call site converts by changing the type name.
public enum ArtworkPhase {
  case empty
  case success(Image)
  case failure(any Error)

  public var image: Image? {
    guard case .success(let image) = self else { return nil }
    return image
  }

  public var error: (any Error)? {
    guard case .failure(let error) = self else { return nil }
    return error
  }
}

public struct ArtworkImage<Content: View>: View {
  private let url: URL?
  private let animation: Animation?
  private let content: (ArtworkPhase) -> Content
  @State private var phase: ArtworkPhase = .empty

  public init(
    url: URL?,
    transaction: Transaction = Transaction(),
    @ViewBuilder content: @escaping (ArtworkPhase) -> Content
  ) {
    self.url = url
    self.animation = transaction.animation
    self.content = content
  }

  public var body: some View {
    content(phase)
      .task(id: url?.absoluteString) {
        await load()
      }
  }

  @MainActor
  private func load() async {
    guard let url else {
      apply(.empty)
      return
    }
    if let cached = Artwork.cachedImage(for: url) {
      apply(.success(Image(platformImage: cached)))
      return
    }
    apply(.empty)
    do {
      let loaded = try await Artwork.image(for: url)
      apply(.success(Image(platformImage: loaded)))
    } catch is CancellationError {
      return
    } catch {
      apply(.failure(error))
    }
  }

  private func apply(_ new: ArtworkPhase) {
    if let animation {
      withAnimation(animation) { phase = new }
    } else {
      phase = new
    }
  }
}
