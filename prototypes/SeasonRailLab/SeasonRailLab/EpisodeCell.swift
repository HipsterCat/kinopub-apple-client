import UIKit

/// Mirrors `VideosUI.EpisodeLockup`, the view Apple hosts in
/// `PlatformHostingCellView<EpisodeLockup>`.
///
/// Demangled body, top to bottom: an image, then `StandardTextView` plus a
/// `DescriptionView` (its own accessibility element — the second focus ring
/// in the TV app's hierarchy), then `LockupAccessoryContainerView` for
/// playback status and the context control. Those accessories sit on the
/// image. `UICellAccessory` only has leading and trailing placements, and
/// this cell does not use it.
///
/// The cover is a borderless button: no platter at rest. The description is
/// a selectable text view (`isEditable` does not exist on tvOS; `isSelectable`
/// is what makes it focusable). It is empty until the cover or the text
/// itself is focused, which is the `ConditionalContent` / `EmptyView` pair
/// in the lockup body.
final class EpisodeCell: UICollectionViewCell {
  static var placeholder = ImageStore.placeholder(
    color: .systemGray,
    size: CGSize(width: RailMetrics.imageWidth, height: RailMetrics.imageHeight),
    scale: 2
  )

  private let cover = UIButton(configuration: .borderless())
  private let still = UIImageView()
  /// Playback status, badges, play. Apple's `LockupAccessoryContainerView`.
  private let accessories = StillOverlay()
  private let titleLabel = UILabel()
  private let descriptionView = SynopsisTextView()
  private var loadToken = 0
  private var imageTask: Task<Void, Never>?
  private var usingPlaceholder = true
  private var canPlay = false
  private var overview: String?
  private var relatedFocused = false

  override init(frame: CGRect) {
    super.init(frame: frame)
    clipsToBounds = false
    contentView.clipsToBounds = false

    var config = UIButton.Configuration.borderless()
    config.background.backgroundColor = .clear
    config.background.backgroundColorTransformer = UIConfigurationColorTransformer { _ in .clear }
    config.contentInsets = .zero
    cover.configuration = config
    cover.addAction(UIAction { [weak self] _ in self?.activate() }, for: .primaryActionTriggered)
    cover.translatesAutoresizingMaskIntoConstraints = false
    contentView.addSubview(cover)

    still.contentMode = .scaleAspectFill
    still.clipsToBounds = true
    still.layer.cornerRadius = 20
    still.layer.cornerCurve = .continuous
    still.adjustsImageWhenAncestorFocused = true
    still.isUserInteractionEnabled = false
    still.translatesAutoresizingMaskIntoConstraints = false
    cover.addSubview(still)

    accessories.isUserInteractionEnabled = false
    cover.addSubview(accessories)

    titleLabel.font = UIFont.preferredFont(forTextStyle: .headline)
    titleLabel.textColor = .label
    titleLabel.numberOfLines = 1
    titleLabel.translatesAutoresizingMaskIntoConstraints = false
    contentView.addSubview(titleLabel)

    descriptionView.backgroundColor = .clear
    descriptionView.isSelectable = true
    descriptionView.isScrollEnabled = true
    descriptionView.showsVerticalScrollIndicator = true
    descriptionView.font = UIFont.preferredFont(forTextStyle: .callout)
    descriptionView.textColor = .secondaryLabel
    descriptionView.tintColor = .clear
    descriptionView.textContainerInset = .zero
    descriptionView.textContainer.lineFragmentPadding = 0
    descriptionView.textContainer.lineBreakMode = .byWordWrapping
    descriptionView.onSelect = { [weak self] in self?.activate() }
    descriptionView.translatesAutoresizingMaskIntoConstraints = false
    contentView.addSubview(descriptionView)

    let body = UIFont.preferredFont(forTextStyle: .callout).lineHeight * 5
    NSLayoutConstraint.activate([
      cover.topAnchor.constraint(equalTo: contentView.topAnchor),
      cover.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      cover.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      cover.heightAnchor.constraint(equalToConstant: RailMetrics.imageHeight),
      still.topAnchor.constraint(equalTo: cover.topAnchor),
      still.leadingAnchor.constraint(equalTo: cover.leadingAnchor),
      still.trailingAnchor.constraint(equalTo: cover.trailingAnchor),
      still.bottomAnchor.constraint(equalTo: cover.bottomAnchor),
      titleLabel.topAnchor.constraint(equalTo: cover.bottomAnchor, constant: 12),
      titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      descriptionView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
      descriptionView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      descriptionView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      descriptionView.heightAnchor.constraint(equalToConstant: body),
    ])
    setStill(Self.placeholder)
  }

  required init?(coder: NSCoder) { nil }

  override func layoutSubviews() {
    super.layoutSubviews()
    accessories.frame = cover.bounds
  }

  override func prepareForReuse() {
    super.prepareForReuse()
    imageTask?.cancel()
    imageTask = nil
    loadToken += 1
    canPlay = false
    overview = nil
    relatedFocused = false
    usingPlaceholder = true
    titleLabel.attributedText = nil
    applyDescription()
    accessories.apply(episode: nil, focused: false)
    setStill(Self.placeholder)
  }

  override var canBecomeFocused: Bool { false }

  override var preferredFocusEnvironments: [any UIFocusEnvironment] { [cover] }

  override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
    super.didUpdateFocus(in: context, with: coordinator)
    let inside = context.nextFocusedView?.isDescendant(of: self) == true
    let coverFocused = context.nextFocusedView === cover
    coordinator.addCoordinatedAnimations { [weak self] in
      guard let self else { return }
      self.relatedFocused = inside
      self.applyDescription()
      self.accessories.setFocused(coverFocused && self.canPlay)
    }
  }

  func refreshPlaceholderIfNeeded() {
    guard usingPlaceholder else { return }
    setStill(Self.placeholder)
  }

  func configure(_ item: RailItem) {
    switch item {
    case .skeleton:
      canPlay = false
      overview = nil
      titleLabel.attributedText = nil
      applyDescription()
      accessories.apply(episode: nil, focused: false)
      cover.accessibilityLabel = "Загрузка"
      show(url: nil)
    case .episode(let episode):
      canPlay = episode.onService
      overview = episode.overview
      titleLabel.attributedText = Self.title(episode.title, marks: episode.onService)
      applyDescription()
      accessories.apply(episode: episode, focused: cover.isFocused && canPlay)
      let synopsis = episode.overview ?? ""
      let label = [episode.title, episode.summary, synopsis].filter { !$0.isEmpty }.joined(separator: ". ")
      cover.accessibilityLabel = label
      descriptionView.accessibilityLabel = label
      show(url: episode.stillURL)
    }
  }

  private func activate() {}

  private func applyDescription() {
    let show = relatedFocused || descriptionView.isFocused
    descriptionView.text = show ? overview : nil
    descriptionView.isHidden = descriptionView.text == nil
    descriptionView.canFocus = overview != nil
    descriptionView.textColor = descriptionView.isFocused ? .label : .secondaryLabel
  }

  private func show(url: URL?) {
    loadToken += 1
    let token = loadToken
    imageTask?.cancel()
    guard let url else {
      usingPlaceholder = true
      setStill(Self.placeholder)
      return
    }
    if let cached = ImageStore.cached(url) {
      usingPlaceholder = false
      setStill(cached)
      return
    }
    usingPlaceholder = true
    setStill(Self.placeholder)
    let scale = traitCollection.displayScale
    let size = CGSize(width: RailMetrics.imageWidth, height: RailMetrics.imageHeight)
    imageTask = Task { [weak self] in
      let image = await ImageStore.load(url, pointSize: size, scale: scale)
      guard let self, self.loadToken == token, let image else { return }
      self.usingPlaceholder = false
      UIView.transition(with: self.still, duration: 0.25, options: [.transitionCrossDissolve, .curveEaseOut]) {
        self.setStill(image)
      }
    }
  }

  private func setStill(_ image: UIImage) {
    still.image = image
  }

  private static func title(_ title: String, marks: Bool) -> NSAttributedString {
    let headline = UIFont.preferredFont(forTextStyle: .headline)
    let text = NSMutableAttributedString(string: title, attributes: [
      .font: headline,
      .foregroundColor: UIColor.label,
    ])
    guard marks else { return text }
    let caption = UIFont.preferredFont(forTextStyle: .caption2)
    text.append(NSAttributedString(string: "  4K", attributes: [
      .font: caption,
      .foregroundColor: UIColor.secondaryLabel,
    ]))
    let symbol = UIImage.SymbolConfiguration(textStyle: .caption1, scale: .small)
    for name in ["bubble.left", "waveform"] {
      guard let image = UIImage(systemName: name, withConfiguration: symbol)?
        .withTintColor(.secondaryLabel, renderingMode: .alwaysOriginal) else { continue }
      text.append(NSAttributedString(string: " "))
      let attachment = NSTextAttachment()
      attachment.image = image
      text.append(NSAttributedString(attachment: attachment))
    }
    return text
  }
}

final class SynopsisTextView: UITextView {
  var canFocus = false
  var onSelect: (() -> Void)?

  override var canBecomeFocused: Bool { canFocus && !isHidden }

  override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
    if presses.contains(where: { $0.type == .select }) {
      onSelect?()
      return
    }
    super.pressesEnded(presses, with: event)
  }
}

/// Playback progress, watch badges, play glyph. Sits on the still, the way
/// `LockupAccessoryContainerView` sits on `AsyncImageView`.
final class StillOverlay: UIView {
  private let durationLabel = UILabel()
  private let play = UIImageView()
  private let progressTrack = UIView()
  private let progressFill = UIView()
  private let badgeIcon = UIImageView()
  private let badgeLabel = UILabel()
  private var showsProgress = false
  private var progressFraction: CGFloat = 0

  override init(frame: CGRect) {
    super.init(frame: frame)
    durationLabel.font = UIFont.preferredFont(forTextStyle: .caption1)
    durationLabel.textColor = .label
    addSubview(durationLabel)

    let playSymbol = UIImage.SymbolConfiguration(pointSize: 56, weight: .medium)
    play.image = UIImage(systemName: "play.circle.fill", withConfiguration: playSymbol)
    play.tintColor = .label
    play.alpha = 0
    addSubview(play)

    progressTrack.backgroundColor = .separator
    progressFill.backgroundColor = .label
    progressTrack.addSubview(progressFill)
    addSubview(progressTrack)

    badgeIcon.tintColor = .label
    badgeIcon.contentMode = .scaleAspectFit
    addSubview(badgeIcon)

    badgeLabel.font = UIFont.preferredFont(forTextStyle: .caption1)
    badgeLabel.textColor = .label
    addSubview(badgeLabel)
  }

  required init?(coder: NSCoder) { nil }

  override func layoutSubviews() {
    super.layoutSubviews()
    let barHeight: CGFloat = 6
    progressTrack.frame = CGRect(x: 0, y: bounds.height - barHeight, width: bounds.width, height: barHeight)
    progressTrack.isHidden = !showsProgress
    progressFill.frame = CGRect(x: 0, y: 0, width: bounds.width * progressFraction, height: barHeight)
    let playSide: CGFloat = 64
    play.frame = CGRect(
      x: (bounds.width - playSide) / 2,
      y: (bounds.height - playSide) / 2,
      width: playSide,
      height: playSide
    )
    let durationHeight = durationLabel.font.lineHeight
    let durationBottom = showsProgress ? barHeight + 10 : 12
    let durationWidth = min(durationLabel.intrinsicContentSize.width, bounds.width * 0.5)
    durationLabel.frame = CGRect(
      x: 14,
      y: bounds.height - durationBottom - durationHeight,
      width: durationWidth,
      height: durationHeight
    )
    let iconSide = badgeLabel.font.lineHeight
    badgeIcon.frame = CGRect(x: bounds.width - 14 - iconSide, y: 12, width: badgeIcon.isHidden ? 0 : iconSide, height: iconSide)
    let badgeWidth = min(badgeLabel.intrinsicContentSize.width, bounds.width * 0.55)
    badgeLabel.frame = CGRect(
      x: badgeIcon.frame.minX - 6 - badgeWidth,
      y: 12,
      width: badgeLabel.isHidden ? 0 : badgeWidth,
      height: iconSide
    )
  }

  func setFocused(_ focused: Bool) {
    play.alpha = focused ? 1 : 0
  }

  func apply(episode: Episode?, focused: Bool) {
    guard let episode else {
      showsProgress = false
      progressFraction = 0
      durationLabel.text = nil
      badgeIcon.isHidden = true
      badgeLabel.isHidden = true
      isHidden = true
      setFocused(false)
      return
    }
    isHidden = false
    let minutes = episode.runtimeMinutes
    durationLabel.text = (episode.onService && minutes != nil) ? "\(minutes!) мин" : nil
    switch episode.availability {
    case .inProgress(let fraction):
      showsProgress = true
      progressFraction = CGFloat(fraction)
      badgeIcon.isHidden = true
      badgeLabel.isHidden = true
    case .watched:
      showsProgress = false
      progressFraction = 0
      badgeIcon.image = UIImage(systemName: "checkmark.circle.fill", withConfiguration: badgeSymbol)
      badgeIcon.isHidden = false
      badgeLabel.isHidden = true
    case .missing:
      showsProgress = false
      progressFraction = 0
      badgeIcon.image = UIImage(systemName: "lock.fill", withConfiguration: badgeSymbol)
      badgeIcon.isHidden = false
      badgeLabel.isHidden = true
    case .upcoming(let date):
      showsProgress = false
      progressFraction = 0
      badgeIcon.image = UIImage(systemName: "calendar", withConfiguration: badgeSymbol)
      badgeIcon.isHidden = false
      if let date {
        badgeLabel.text = Episode.when(date)
        badgeLabel.isHidden = false
      } else {
        badgeLabel.isHidden = true
      }
    case .playable:
      showsProgress = false
      progressFraction = 0
      badgeIcon.isHidden = true
      badgeLabel.isHidden = true
    }
    setFocused(focused && episode.onService)
    setNeedsLayout()
  }

  private var badgeSymbol: UIImage.SymbolConfiguration {
    UIImage.SymbolConfiguration(textStyle: .caption1, scale: .large)
  }
}
