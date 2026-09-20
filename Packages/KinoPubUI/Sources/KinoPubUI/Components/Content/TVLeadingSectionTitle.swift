#if os(tvOS)
import SwiftUI
import UIKit

/// tvOS `Section` headers compact-hug then **center** — light shots landed at
/// ~795 pt (x≈1589px). Sketch 1920 artboard is leading **x=80**, same column as
/// the first card. A SwiftUI `frame(maxWidth:)` is ignored when the header slot
/// proposes compact width; this view’s size is the canvas and the label is
/// placed in **screen** space so a centered parent cannot shift it.
struct TVLeadingSectionTitle: UIViewRepresentable {
  var title: String
  var accessibilityText: String

  func makeUIView(context: Context) -> TVLeadingSectionTitleView {
    TVLeadingSectionTitleView()
  }

  func updateUIView(_ view: TVLeadingSectionTitleView, context: Context) {
    view.apply(title: title, accessibilityText: accessibilityText)
  }

  func sizeThatFits(
    _ proposal: ProposedViewSize,
    uiView: TVLeadingSectionTitleView,
    context: Context
  ) -> CGSize? {
    CGSize(width: 1920, height: uiView.preferredHeight)
  }
}

final class TVLeadingSectionTitleView: UIView {
  private let label = UILabel()

  var preferredHeight: CGFloat {
    max(label.intrinsicContentSize.height, 1)
  }

  override init(frame: CGRect) {
    super.init(frame: frame)
    isUserInteractionEnabled = false
    isOpaque = false
    backgroundColor = .clear
    clipsToBounds = false
    setContentHuggingPriority(.defaultLow, for: .horizontal)
    setContentCompressionResistancePriority(.required, for: .horizontal)
    label.numberOfLines = 1
    label.textAlignment = .left
    label.adjustsFontForContentSizeCategory = true
    label.textColor = .secondaryLabel
    addSubview(label)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func apply(title: String, accessibilityText: String) {
    label.text = title
    accessibilityLabel = accessibilityText
    let headline = UIFont.preferredFont(forTextStyle: .headline)
    if let descriptor = headline.fontDescriptor.withSymbolicTraits(.traitBold) {
      label.font = UIFont(descriptor: descriptor, size: 0)
    } else {
      label.font = headline
    }
    invalidateIntrinsicContentSize()
    setNeedsLayout()
  }

  override var intrinsicContentSize: CGSize {
    CGSize(width: 1920, height: preferredHeight)
  }

  override func didMoveToSuperview() {
    super.didMoveToSuperview()
    superview?.clipsToBounds = false
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    // Screen x, not view x: a centered compact header still paints the label
    // on the 80 pt column if the ancestor does not clip.
    let screenX = convert(CGPoint.zero, to: nil).x
    let x = ShelfMetrics.tvContentMargin - screenX
    let height = bounds.height > 0 ? bounds.height : preferredHeight
    let width = max(label.intrinsicContentSize.width, 1)
    label.frame = CGRect(x: x, y: 0, width: width, height: height)
  }
}
#endif
