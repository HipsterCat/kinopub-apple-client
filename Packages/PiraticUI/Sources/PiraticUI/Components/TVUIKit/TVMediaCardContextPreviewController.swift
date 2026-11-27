#if os(tvOS)
//
//  TVMediaCardContextPreviewController.swift
//  PiraticUI
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
  private let timeLabel = UILabel()
  private let footer = UIView()
  private let captions = UIStackView()
  private let card = UIView()
  private var cardWidth: NSLayoutConstraint!
  private var cardHeight: NSLayoutConstraint!
  private var artHeight: NSLayoutConstraint!
  private var artworkTask: Task<Void, Never>?

  public init(spec: MediaCardContextPreviewSpec) {
    self.spec = spec
    super.init(nibName: nil, bundle: nil)
    configureLabels()
    preferredContentSize = previewSize(art: spec.artSize)
  }

  public convenience init(url: URL?, aspect: CardAspect, title: String = "", subtitle: String? = nil) {
    self.init(spec: MediaCardContextPreviewSpec(url: url, aspect: aspect, title: title, subtitle: subtitle))
  }

  @available(*, unavailable)
  public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  deinit { artworkTask?.cancel() }

  private func configureLabels() {
    titleLabel.text = spec.title
    titleLabel.font = .preferredFont(forTextStyle: .headline)
    titleLabel.adjustsFontForContentSizeCategory = true
    titleLabel.textColor = .label
    titleLabel.numberOfLines = 2

    subtitleLabel.text = spec.subtitle
    subtitleLabel.font = .preferredFont(forTextStyle: .subheadline)
    subtitleLabel.adjustsFontForContentSizeCategory = true
    subtitleLabel.textColor = .secondaryLabel
    subtitleLabel.numberOfLines = 2
    subtitleLabel.isHidden = spec.subtitle == nil

    timeLabel.text = spec.time
    timeLabel.font = .preferredFont(forTextStyle: .subheadline)
    timeLabel.adjustsFontForContentSizeCategory = true
    timeLabel.textColor = .secondaryLabel
    timeLabel.isHidden = spec.time == nil
  }

  private func previewSize(art: CGSize) -> CGSize {
    let bounds = CGSize(width: max(1, art.width - 28), height: .greatestFiniteMagnitude)
    let labels = [titleLabel, subtitleLabel, timeLabel].filter { !$0.isHidden }
    let textHeight = labels.reduce(CGFloat.zero) { $0 + $1.sizeThatFits(bounds).height }
    let gaps = CGFloat(max(0, labels.count - 1)) * 2
    return CGSize(width: art.width, height: art.height + ceil(textHeight + gaps) + 24)
  }

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

    captions.axis = .vertical
    captions.spacing = 2
    captions.translatesAutoresizingMaskIntoConstraints = false
    captions.addArrangedSubview(titleLabel)
    captions.addArrangedSubview(subtitleLabel)
    captions.addArrangedSubview(timeLabel)
    footer.addSubview(captions)

    cardWidth = card.widthAnchor.constraint(equalToConstant: art.width)
    cardHeight = card.heightAnchor.constraint(equalToConstant: preferredContentSize.height)
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

      captions.topAnchor.constraint(equalTo: footer.topAnchor, constant: 12),
      captions.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: 14),
      captions.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -14)
    ])

    loadArtwork()
  }

  private func loadArtwork() {
    guard !spec.artworkURLs.isEmpty else { return }
    spinner.startAnimating()
    artworkTask = Task { [weak self, spec] in
      let image = await spec.loadImage()
      guard !Task.isCancelled, let self else { return }
      self.spinner.stopAnimating()
      if let image {
        self.apply(image: image)
      }
    }
  }

  private func apply(image: UIImage) {
    let art = spec.artDisplaySize(forImageSize: image.size)
    let peek = previewSize(art: art)
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
