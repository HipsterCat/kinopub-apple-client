//
//  TitleLogoSession.swift
//  KinoPubUI
//
//  One state machine for every title-logo slot (SwiftUI hero, UIKit banner).
//  The lettered name waits until a miss is confirmed; a pending metadata lookup
//  does not time out into text, so a late URL cannot swap text → logo.
//

import Combine
import Foundation
import KinoPubMetadata
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Loads a title-logo image. ``ArtworkTitleLogoImages`` is the production source;
/// tests inject a stand-in.
#if os(macOS)
typealias TitleLogoImage = NSImage
#else
typealias TitleLogoImage = UIImage
#endif

struct TitleLogoImageLoad: Sendable {
  let image: TitleLogoImage
  let deliveredLanguage: WorkerArtworkLanguageTag?
}

protocol TitleLogoImageLoading: Sendable {
  func cachedImage(for url: URL) -> TitleLogoImage?
  func deliveredLanguage(for url: URL) -> WorkerArtworkLanguageTag?
  func load(for url: URL) async throws -> TitleLogoImageLoad
}

struct ArtworkTitleLogoImages: TitleLogoImageLoading {
  func cachedImage(for url: URL) -> TitleLogoImage? {
    Artwork.cachedImage(for: url)
  }

  func deliveredLanguage(for url: URL) -> WorkerArtworkLanguageTag? {
    Artwork.workerLanguage(on: url)
  }

  func load(for url: URL) async throws -> TitleLogoImageLoad {
    do {
      let loaded = try await Artwork.imageWithSource(for: url)
#if os(tvOS)
      ArtworkLog.source("logo", id: nil, asked: url, answered: loaded.answered, tier: loaded.tier)
#endif
      return TitleLogoImageLoad(image: loaded.image, deliveredLanguage: loaded.language)
    } catch {
#if os(tvOS)
      ArtworkLog.exhausted("logo", id: nil, tried: [url])
#endif
      throw error
    }
  }
}

/// Shared title-logo slot state. SwiftUI observes it; the banner cell paints from it.
/// Completions are request-scoped so a stale decode cannot overwrite a newer title.
@MainActor
public final class TitleLogoSession: ObservableObject {

  @Published public private(set) var mark: TitleLogoMark = .empty
  @Published public private(set) var deliveredLanguage: WorkerArtworkLanguageTag?
  @Published private(set) var image: TitleLogoImage?

  /// UIKit call sites that are not SwiftUI views.
  var onChange: (() -> Void)?

  private let policy: TitleLogoPresentationPolicy
  private let images: any TitleLogoImageLoading
  private var resolution: TitleLogoResolution = .pending
  private var requestID = 0
  private var imageReady = false
  private var imageFailed = false
  private var timedOut = false
  private var loadTask: Task<Void, Never>?
  private var startedAt = Date()

  public init(policy: TitleLogoPresentationPolicy = .whenResolved) {
    self.policy = policy
    self.images = ArtworkTitleLogoImages()
  }

  init(policy: TitleLogoPresentationPolicy = .whenResolved, images: any TitleLogoImageLoading) {
    self.policy = policy
    self.images = images
  }

  /// Drive the slot. Pending → URL / missing is the same title settling, not a new
  /// request: already-shown text is kept, and an empty slot stays empty until the
  /// image is ready.
  public func setResolution(_ new: TitleLogoResolution) {
    let continuing = Self.isContinuation(from: resolution, to: new)
    if !continuing {
      requestID += 1
      image = nil
      deliveredLanguage = nil
      imageReady = false
      imageFailed = false
      timedOut = false
      loadTask?.cancel()
      loadTask = nil
    }
    resolution = new
    let id = requestID

    if let url = new.url, let cached = images.cachedImage(for: url) {
      image = cached
      deliveredLanguage = images.deliveredLanguage(for: url)
      imageReady = true
      imageFailed = false
      timedOut = false
      loadTask?.cancel()
      loadTask = nil
      republish()
      return
    }

    republish()

    switch new {
    case .missing:
      loadTask?.cancel()
      loadTask = nil
    case .pending:
      // Metadata is still in flight. Do not start the miss timeout — that is what
      // painted the lettered title, then swapped it for a late logo.
      break
    case .url(let url):
      if loadTask != nil, continuing, !imageReady, !imageFailed, !timedOut { return }
      startLoad(url: url, requestID: id, resetTimeout: mark != .text)
    }
  }

  public func reset() {
    loadTask?.cancel()
    loadTask = nil
    requestID += 1
    resolution = .pending
    image = nil
    deliveredLanguage = nil
    imageReady = false
    imageFailed = false
    timedOut = false
    republish()
  }

  /// The image-load miss timeout. No-op while metadata is still pending, so a hung
  /// details call cannot flash the lettered title ahead of a logo that is about to
  /// land. Tests call this without waiting.
  func handleTimeout() {
    guard resolution.url != nil, image == nil, !imageFailed else { return }
    timedOut = true
    republish()
  }

  func handleLoaded(_ payload: TitleLogoImageLoad, elapsed: TimeInterval) {
    let showingText = mark == .text
    guard policy.shouldAdoptLogo(elapsed: elapsed, alreadyShowingText: showingText) else {
      return
    }
    image = payload.image
    deliveredLanguage = payload.deliveredLanguage
    imageReady = true
    imageFailed = false
    republish()
  }

  func handleFailed() {
    imageFailed = true
    republish()
  }

  private func startLoad(url: URL, requestID id: Int, resetTimeout: Bool) {
    loadTask?.cancel()
    startedAt = Date()
    imageFailed = false
    if resetTimeout { timedOut = false }
    let timeout = TitleLogoPresentationPolicy.missTimeout
    let images = self.images
    loadTask = Task { [weak self] in
      await withTaskGroup(of: LoadEvent.self) { group in
        group.addTask {
          try? await Task.sleep(
            nanoseconds: UInt64(timeout * 1_000_000_000)
          )
          return .timeout
        }
        group.addTask {
          do {
            let payload = try await images.load(for: url)
            return .loaded(payload)
          } catch is CancellationError {
            return .cancelled
          } catch {
            return .fail
          }
        }
        while let event = await group.next() {
          guard let self else { return }
          guard self.policy.shouldApply(requestID: id, current: self.requestID) else {
            group.cancelAll()
            return
          }
          switch event {
          case .loaded(let payload):
            let elapsed = Date().timeIntervalSince(self.startedAt)
            self.handleLoaded(payload, elapsed: elapsed)
            group.cancelAll()
            return
          case .fail:
            self.handleFailed()
            group.cancelAll()
            return
          case .timeout:
            self.handleTimeout()
          case .cancelled:
            group.cancelAll()
            return
          }
        }
      }
    }
  }

  private func republish() {
    let cached = resolution.url.flatMap { images.cachedImage(for: $0) }
    mark = policy.mark(
      hasCachedLogo: cached != nil,
      lookupComplete: resolution != .pending,
      hasLogoURL: resolution.url != nil,
      imageReady: imageReady || image != nil,
      imageFailed: imageFailed || timedOut,
      elapsed: timedOut ? TitleLogoPresentationPolicy.missTimeout : 0
    )
    onChange?()
  }

  private enum LoadEvent {
    case loaded(TitleLogoImageLoad)
    case fail
    case timeout
    case cancelled
  }

  static func isContinuation(from old: TitleLogoResolution, to new: TitleLogoResolution) -> Bool {
    switch (old, new) {
    case (.pending, .pending), (.pending, .url), (.pending, .missing):
      return true
    case (.url(let a), .url(let b)) where a == b:
      return true
    case (.missing, .missing):
      return true
    default:
      return false
    }
  }
}
