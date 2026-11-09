#if os(tvOS)
//
//  TVPageScoreSummaryCell.swift
//  KinoPubUI
//
//  The viewers' and the critics' card on the tvOS page: the same `ScoreSummaryCardContent` the
//  pointer platforms draw, hosted inside the page's `TVCardView` with `UIHostingConfiguration`.
//  The platter, its lift and its white fill stay the card view's; the hosted view only hears when
//  the platter turned white, to turn its ink dark — as every other info card's labels do.
//

import SwiftUI
import UIKit

@MainActor
final class TVPageScoreSummaryCell: TVPageInfoCardCell {
  private let body = TVPageScoreSummaryContent()

  override init(frame: CGRect) {
    super.init(frame: frame)
    install(body)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func configure(_ summary: ScoreSummary) {
    body.configure(summary)
    accessibilityIdentifier = "kinopub.summary.\(summary.kind.rawValue)"
    accessibilityLabel = summary.accessibilityLabel
  }
}

@MainActor
final class TVPageScoreSummaryContent: TVPageCardContent {
  private var summary: ScoreSummary?
  private var looksFocused = false
  private var host: (UIView & UIContentView)?

  /// The padding and what the rows need (`ScoreSummaryMetrics.contentHeight`).
  static func height(for summary: ScoreSummary) -> CGFloat {
    ceil(padding * 2 + ScoreSummaryMetrics.contentHeight(for: summary))
  }

  func configure(_ summary: ScoreSummary) {
    guard summary != self.summary else { return }
    self.summary = summary
    render()
  }

  override func applyFocusLook(_ focused: Bool) {
    guard focused != looksFocused else { return }
    looksFocused = focused
    render()
  }

  private func render() {
    guard let summary else { return }
    let configuration = UIHostingConfiguration {
      ScoreSummaryCardContent(summary: summary, focused: looksFocused)
    }
    .margins(.all, Self.padding)
    if let host {
      host.configuration = configuration
    } else {
      let view = configuration.makeContentView()
      view.isUserInteractionEnabled = false
      view.backgroundColor = .clear
      view.frame = bounds
      view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      addSubview(view)
      host = view
    }
  }
}
#endif
