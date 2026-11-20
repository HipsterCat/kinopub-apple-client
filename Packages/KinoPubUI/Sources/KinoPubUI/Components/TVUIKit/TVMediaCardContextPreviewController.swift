#if os(tvOS)
//
//  TVMediaCardContextPreviewController.swift
//  KinoPubUI
//
//  UIKit preview for poster / video context menus: enlarged art, dark underlay,
//  spinner while loading. Same box sizes as `MediaCardContextPreview`.
//

import UIKit

@MainActor
public final class TVMediaCardContextPreviewController: UIViewController {
  private let url: URL?
  private let aspect: CardAspect
  private let imageView = UIImageView()
  private let spinner = UIActivityIndicatorView(style: .large)
  private let underlay = UIView()

  public init(url: URL?, aspect: CardAspect) {
    self.url = url
    self.aspect = aspect
    super.init(nibName: nil, bundle: nil)
    let size = MediaCardContextPreviewSpec(url: url, aspect: aspect).preferredSize
    preferredContentSize = size
  }

  public convenience init(spec: MediaCardContextPreviewSpec) {
    self.init(url: spec.url, aspect: spec.aspect)
  }

  @available(*, unavailable)
  public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  public override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .clear

    underlay.backgroundColor = UIColor.black.withAlphaComponent(0.55)
    underlay.layer.cornerRadius = 16
    underlay.layer.cornerCurve = .continuous
    underlay.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(underlay)

    imageView.contentMode = .scaleAspectFill
    imageView.clipsToBounds = true
    imageView.layer.cornerRadius = 16
    imageView.layer.cornerCurve = .continuous
    imageView.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(imageView)

    spinner.color = .white
    spinner.hidesWhenStopped = true
    spinner.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(spinner)

    NSLayoutConstraint.activate([
      underlay.topAnchor.constraint(equalTo: view.topAnchor),
      underlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      underlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      underlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),

      imageView.topAnchor.constraint(equalTo: view.topAnchor),
      imageView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      imageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      imageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

      spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor)
    ])

    loadArtwork()
  }

  private func loadArtwork() {
    Artwork.prefetch([url])
    let size = preferredContentSize
    if let cached = TVUIKitRemoteImage.cached(url: url, size: size) {
      imageView.image = cached
      return
    }
    spinner.startAnimating()
    Task { [weak self] in
      guard let self else { return }
      let image = await TVUIKitRemoteImage.load(url: self.url, size: size)
      self.spinner.stopAnimating()
      self.imageView.image = image
    }
  }
}

public extension TVUIKitContextMenuBuilder {
  /// Menu + artwork preview for a poster / video card.
  @MainActor
  static func configuration(
    identifier: (any NSCopying)?,
    preview: MediaCardContextPreviewSpec?,
    entries: [MediaCardContextEntry]
  ) -> UIContextMenuConfiguration {
    UIContextMenuConfiguration(
      identifier: identifier,
      previewProvider: {
        guard let preview else { return nil }
        return TVMediaCardContextPreviewController(spec: preview)
      },
      actionProvider: { _ in menu(from: entries) }
    )
  }
}
#endif
