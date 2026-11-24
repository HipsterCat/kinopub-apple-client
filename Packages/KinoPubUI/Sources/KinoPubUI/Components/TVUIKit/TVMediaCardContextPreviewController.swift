#if os(tvOS)
//
//  TVMediaCardContextPreviewController.swift
//  KinoPubUI
//
//  UIKit sneak peek for poster / video context menus: plate hugs the loaded
//  art's aspect (no letterbox gutters), metadata footer, spinner while loading.
//  Same layout as `MediaCardContextPreview`.
//

import UIKit

@MainActor
public final class TVMediaCardContextPreviewController: UIViewController {
  private let spec: MediaCardContextPreviewSpec
  private let imageView = UIImageView()
  private let artContainer = UIView()
  private let spinner = UIActivityIndicatorView(style: .large)
  private let titleLabel = UILabel()
  private let subtitleLabel = UILabel()
  private let footer = UIView()
  private let card = UIView()
  private var cardWidth: NSLayoutConstraint!
  private var cardHeight: NSLayoutConstraint!
  private var artHeight: NSLayoutConstraint!

  public init(spec: MediaCardContextPreviewSpec) {
    self.spec = spec
    super.init(nibName: nil, bundle: nil)
    preferredContentSize = spec.preferredSize
  }

  public convenience init(url: URL?, aspect: CardAspect, title: String = "", subtitle: String? = nil) {
    self.init(spec: MediaCardContextPreviewSpec(url: url, aspect: aspect, title: title, subtitle: subtitle))
  }

  @available(*, unavailable)
  public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  public override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .clear

    let art = spec.artSize
    let radius: CGFloat = 20

    card.backgroundColor = .clear
    card.layer.cornerRadius = radius
    card.layer.cornerCurve = .continuous
    card.clipsToBounds = true
    card.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(card)

    artContainer.backgroundColor = UIColor.white.withAlphaComponent(0.08)
    artContainer.translatesAutoresizingMaskIntoConstraints = false
    card.addSubview(artContainer)

    // Fill the hugged frame — the container is already sized to the bitmap.
    imageView.contentMode = .scaleAspectFill
    imageView.clipsToBounds = true
    imageView.translatesAutoresizingMaskIntoConstraints = false
    artContainer.addSubview(imageView)

    spinner.color = .white
    spinner.hidesWhenStopped = true
    spinner.translatesAutoresizingMaskIntoConstraints = false
    artContainer.addSubview(spinner)

    footer.backgroundColor = UIColor(white: 0.12, alpha: 1)
    footer.translatesAutoresizingMaskIntoConstraints = false
    card.addSubview(footer)

    titleLabel.text = spec.title
    titleLabel.font = .preferredFont(forTextStyle: .headline)
    titleLabel.textColor = .label
    titleLabel.numberOfLines = 2
    titleLabel.translatesAutoresizingMaskIntoConstraints = false
    footer.addSubview(titleLabel)

    subtitleLabel.text = spec.subtitle
    subtitleLabel.font = .preferredFont(forTextStyle: .subheadline)
    subtitleLabel.textColor = .secondaryLabel
    subtitleLabel.numberOfLines = 2
    subtitleLabel.isHidden = spec.subtitle == nil
    subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
    footer.addSubview(subtitleLabel)

    cardWidth = card.widthAnchor.constraint(equalToConstant: art.width)
    cardHeight = card.heightAnchor.constraint(equalToConstant: spec.preferredSize.height)
    artHeight = artContainer.heightAnchor.constraint(equalToConstant: art.height)

    NSLayoutConstraint.activate([
      card.topAnchor.constraint(equalTo: view.topAnchor),
      card.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      cardWidth,
      cardHeight,

      artContainer.topAnchor.constraint(equalTo: card.topAnchor),
      artContainer.leadingAnchor.constraint(equalTo: card.leadingAnchor),
      artContainer.trailingAnchor.constraint(equalTo: card.trailingAnchor),
      artHeight,

      imageView.topAnchor.constraint(equalTo: artContainer.topAnchor),
      imageView.bottomAnchor.constraint(equalTo: artContainer.bottomAnchor),
      imageView.leadingAnchor.constraint(equalTo: artContainer.leadingAnchor),
      imageView.trailingAnchor.constraint(equalTo: artContainer.trailingAnchor),

      spinner.centerXAnchor.constraint(equalTo: artContainer.centerXAnchor),
      spinner.centerYAnchor.constraint(equalTo: artContainer.centerYAnchor),

      footer.topAnchor.constraint(equalTo: artContainer.bottomAnchor),
      footer.leadingAnchor.constraint(equalTo: card.leadingAnchor),
      footer.trailingAnchor.constraint(equalTo: card.trailingAnchor),
      footer.bottomAnchor.constraint(equalTo: card.bottomAnchor),
      footer.heightAnchor.constraint(equalToConstant: spec.footerHeight),

      titleLabel.topAnchor.constraint(equalTo: footer.topAnchor, constant: 12),
      titleLabel.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: 14),
      titleLabel.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -14),

      subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
      subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
      subtitleLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
      subtitleLabel.bottomAnchor.constraint(lessThanOrEqualTo: footer.bottomAnchor, constant: -12)
    ])

    loadArtwork()
  }

  private func loadArtwork() {
    Artwork.prefetch([spec.url])
    let decodeBox = spec.artSize
    if let cached = TVUIKitRemoteImage.cached(url: spec.url, size: decodeBox, mode: .fit) {
      apply(image: cached)
      return
    }
    spinner.startAnimating()
    Task { [weak self] in
      guard let self else { return }
      let image = await TVUIKitRemoteImage.load(url: self.spec.url, size: decodeBox, mode: .fit)
      self.spinner.stopAnimating()
      if let image {
        self.apply(image: image)
      }
    }
  }

  private func apply(image: UIImage) {
    let art = spec.artDisplaySize(forImageSize: image.size)
    let peek = spec.preferredSize(art: art)
    preferredContentSize = peek
    cardWidth.constant = art.width
    cardHeight.constant = peek.height
    artHeight.constant = art.height
    artContainer.backgroundColor = .clear
    imageView.image = image
    view.setNeedsLayout()
  }
}

public extension TVUIKitContextMenuBuilder {
  /// Menu + sneak-peek preview for a poster / video card.
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
