#if os(tvOS)
//
//  TVPageScoreSummaryCell.swift
//  KinoPubUI
//
//  The viewers' and the critics' card on the tvOS page. Borderless, like the specification
//  columns (`TVPageSpecCell`): a quiet fill at rest, a shade lighter on focus, never the white
//  inverted platter of a `TVCardView` (Sasha, 2026-11-09).
//
//  What it draws is `ScoreSummaryCardContent`, the pointer platforms' own view, **as a still**
//  (`ImageRenderer`), rendered on the next turn of the run loop. Hosting it live
//  (`UIHostingConfiguration`) crashed at launch: the embedded page measures itself from inside
//  SwiftUI's update (`TVEmbeddedPage.sizeThatFits` → `contentHeight(forWidth:)` →
//  `layoutIfNeeded`), the hosted cell then updated a second view graph mid-update, and
//  AttributeGraph aborted (`AG::precondition_failure`, measured on tvOS 27.2, 2026-11-09).
//

import SwiftUI
import UIKit

@MainActor
final class TVPageScoreSummaryCell: UICollectionViewCell {
  private let highlight = UIView()
  private let imageView = UIImageView()
  private var summary: ScoreSummary?
  private var looksFocused = false
  private var renderedKey: String?
  private var renderScheduled = false

  /// The padding and what the rows need (`ScoreSummaryMetrics.cardHeight`).
  static func height(for summary: ScoreSummary) -> CGFloat {
    ScoreSummaryMetrics.cardHeight(for: summary)
  }

  override init(frame: CGRect) {
    super.init(frame: frame)
    clipsToBounds = false
    highlight.backgroundColor = TVPagePlatter.restingFill
    highlight.layer.cornerRadius = ScoreSummaryMetrics.cornerRadius
    highlight.layer.cornerCurve = .continuous
    imageView.contentMode = .topLeft
    for view in [highlight, imageView] {
      view.frame = contentView.bounds
      view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      contentView.addSubview(view)
    }
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func configure(_ summary: ScoreSummary) {
    accessibilityIdentifier = "kinopub.summary.\(summary.kind.rawValue)"
    accessibilityLabel = summary.accessibilityLabel
    accessibilityTraits = .button
    guard summary != self.summary else { return }
    self.summary = summary
    scheduleRender()
  }

  override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
    super.didUpdateFocus(in: context, with: coordinator)
    let focused = context.nextFocusedView === self
    guard focused != looksFocused else { return }
    looksFocused = focused
    coordinator.addCoordinatedAnimations({ [weak self] in
      self?.highlight.backgroundColor = focused
        ? UIColor.white.withAlphaComponent(0.16) : TVPagePlatter.restingFill
    })
    scheduleRender()
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    if renderKey != renderedKey { scheduleRender() }
  }

  override func prepareForReuse() {
    super.prepareForReuse()
    looksFocused = false
    highlight.backgroundColor = TVPagePlatter.restingFill
  }

  private var renderKey: String? {
    guard let summary, bounds.width > 1, bounds.height > 1 else { return nil }
    return "\(summary.hashValue)|\(bounds.size)|\(looksFocused)|\(traitCollection.userInterfaceStyle.rawValue)"
  }

  /// Never inside a layout pass: SwiftUI may be mid-update (see the file's header).
  private func scheduleRender() {
    guard !renderScheduled else { return }
    renderScheduled = true
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.renderScheduled = false
      self.render()
    }
  }

  private func render() {
    guard let summary, let key = renderKey, key != renderedKey else { return }
    let size = bounds.size
    let padding = ScoreSummaryMetrics.padding
    let content = ScoreSummaryCardContent(summary: summary, highlighted: looksFocused,
                                          showsChevron: true, animatesIn: false)
      .frame(width: size.width - padding * 2, height: size.height - padding * 2, alignment: .topLeading)
      .padding(padding)
      .environment(\.colorScheme, traitCollection.userInterfaceStyle == .light ? .light : .dark)
    let renderer = ImageRenderer(content: content)
    renderer.scale = traitCollection.displayScale
    renderer.proposedSize = ProposedViewSize(size)
    guard let image = renderer.uiImage else { return }
    let first = renderedKey == nil
    renderedKey = key
    if first {
      imageView.alpha = 0
      imageView.image = image
      UIView.animate(withDuration: 0.3) { self.imageView.alpha = 1 }
    } else {
      imageView.image = image
    }
  }
}
#endif
