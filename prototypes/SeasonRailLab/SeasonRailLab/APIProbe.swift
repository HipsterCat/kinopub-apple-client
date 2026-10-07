import UIKit
import TVUIKit
import ObjectiveC
import os

/// One pass at launch. Public views are laid out off to the side and their
/// label frames recorded; private TVUIKit classes exported by the TBD are
/// asked what they implement. Nothing here is shown.
enum APIProbe {
  private static let log = Logger(subsystem: "pub.kino.SeasonRailLab", category: "probe")

  @MainActor
  static func run(in host: UIView) -> String {
    var lines: [String] = []
    lines.append("—— TVMediaItemContentView ——")
    lines.append(mediaItemProbe(in: host))
    lines.append("—— TVCaptionButtonView ——")
    lines.append(captionProbe(in: host))
    lines.append("—— private classes ——")
    for name in [
      "_TVRibbonView", "_TVRibbonCell", "_TVCarouselView", "_TVFocusableTextView",
      "_TVLockupLabel", "_TVContentRatingTextBadgeView", "_TVStackedMediaView",
    ] {
      lines.append(methods(named: name))
    }
    let report = lines.joined(separator: "\n")
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("season-rail-probe.txt")
    try? report.write(to: url, atomically: true, encoding: .utf8)
    log.log("\(report, privacy: .public)")
    NSLog("PROBE_FILE %@", url.path as NSString)
    return report
  }

  @MainActor
  private static func mediaItemProbe(in host: UIView) -> String {
    var config = TVMediaItemContentConfiguration.wideCell()
    config.text = "Primary caption"
    config.secondaryText = "Secondary synopsis that should wrap when the label allows more than one line."
    config.secondaryTextProperties.font = UIFont.preferredFont(forTextStyle: .callout)
    config.secondaryTextProperties.color = .label
    let view = TVMediaItemContentView(configuration: config)
    view.frame = CGRect(x: -2000, y: 0, width: 420, height: 460)
    host.addSubview(view)
    view.layoutIfNeeded()
    var lines = dump(view)
    var state = UICellConfigurationState(traitCollection: host.traitCollection)
    state.isFocused = true
    let updated = config.updated(for: state)
    lines.append("updated secondaryText=\(updated.secondaryText ?? "nil")")
    view.removeFromSuperview()
    return lines.joined(separator: "\n")
  }

  @MainActor
  private static func captionProbe(in host: UIView) -> String {
    let caption = TVCaptionButtonView(frame: CGRect(x: -2000, y: 0, width: 420, height: 460))
    caption.contentImage = UIImage(systemName: "photo")
    caption.title = "1 серия"
    caption.subtitle = String(repeating: "Синопсис серии. ", count: 12)
    host.addSubview(caption)
    caption.layoutIfNeeded()
    var lines = dump(caption)
    if let footer = caption.footerView {
      lines.append("footer title=\(footer.titleLabel?.text ?? "nil") lines=\(footer.subtitleLabel?.numberOfLines ?? -1) subtitleFrame=\(footer.subtitleLabel?.frame ?? .zero)")
      footer.subtitleLabel?.numberOfLines = 3
      footer.showsOnlyWhenAncestorFocused = false
      caption.layoutIfNeeded()
      lines.append("after numberOfLines=3 subtitleFrame=\(footer.subtitleLabel?.frame ?? .zero) footerFrame=\(footer.frame)")
    } else {
      lines.append("footerView nil")
    }
    caption.removeFromSuperview()
    return lines.joined(separator: "\n")
  }

  private static func dump(_ view: UIView, indent: Int = 0) -> [String] {
    var lines: [String] = []
    var extra = ""
    if let label = view as? UILabel {
      let text = label.text ?? "nil"
      extra = " text=\"\(text)\" lines=\(label.numberOfLines) hidden=\(label.isHidden) font=\(label.font.pointSize)"
    }
    lines.append(String(repeating: " ", count: indent) + "\(type(of: view)) \(view.frame.integral)\(extra)")
    for subview in view.subviews {
      lines.append(contentsOf: dump(subview, indent: indent + 2))
    }
    return lines
  }

  private static func methods(named name: String) -> String {
    guard let cls = NSClassFromString(name) else { return "\(name): ABSENT" }
    var selectors: [String] = []
    var current: AnyClass? = cls
    var depth = 0
    while let type = current, depth < 1 {
      var count: UInt32 = 0
      if let list = class_copyMethodList(type, &count) {
        for index in 0..<Int(count) {
          selectors.append(NSStringFromSelector(method_getName(list[index])))
        }
        free(list)
      }
      current = class_getSuperclass(type)
      depth += 1
    }
    let interesting = selectors.filter { selector in
      let lower = selector.lowercased()
      return lower.contains("text") || lower.contains("title") || lower.contains("image")
        || lower.contains("item") || lower.contains("focus") || lower.contains("badge")
        || lower.contains("subtitle") || lower.contains("season")
    }.sorted()
    return "\(name): \(selectors.count) methods, interesting [\(interesting.joined(separator: ", "))]"
  }
}
