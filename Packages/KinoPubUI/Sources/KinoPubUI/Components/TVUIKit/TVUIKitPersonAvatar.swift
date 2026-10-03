#if os(tvOS)
//
//  TVUIKitPersonAvatar.swift
//  KinoPubUI
//
//  A single person circle. Not a control: it cannot take focus, and it draws no
//  plate. A photo is the circle; no photo is the same initials image the search
//  cards use. `TVMonogramContentConfiguration` is deliberately not used — it paints
//  a filled disc and a focus plate, and the header exposes no way to turn either off.
//

import SwiftUI
import UIKit

public struct TVUIKitPersonAvatar: UIViewRepresentable {
  public let name: String
  public let photoURL: URL?
  public let diameter: CGFloat

  public init(name: String, photoURL: URL?, diameter: CGFloat) {
    self.name = name
    self.photoURL = photoURL
    self.diameter = diameter
  }

  public func makeUIView(context: Context) -> TVUIKitPersonAvatarView {
    let view = TVUIKitPersonAvatarView()
    view.configure(name: name, photoURL: photoURL, diameter: diameter)
    return view
  }

  public func updateUIView(_ view: TVUIKitPersonAvatarView, context: Context) {
    view.configure(name: name, photoURL: photoURL, diameter: diameter)
  }

  public func sizeThatFits(_ proposal: ProposedViewSize,
                           uiView: TVUIKitPersonAvatarView,
                           context: Context) -> CGSize? {
    CGSize(width: diameter, height: diameter)
  }
}

@MainActor
public final class TVUIKitPersonAvatarView: UIView {
  public override var canBecomeFocused: Bool { false }

  private let imageView = UIImageView()
  private var imageTask: Task<Void, Never>?
  private var currentURL: URL?
  private var name = ""
  private var showsMonogram = false
  private var monogramDiameter: CGFloat = 0

  public override init(frame: CGRect) {
    super.init(frame: frame)
    isUserInteractionEnabled = false
    backgroundColor = .clear
    imageView.translatesAutoresizingMaskIntoConstraints = false
    imageView.contentMode = .scaleAspectFill
    imageView.clipsToBounds = true
    imageView.backgroundColor = .clear
    imageView.isUserInteractionEnabled = false
    imageView.adjustsImageWhenAncestorFocused = false
    addSubview(imageView)
    NSLayoutConstraint.activate([
      imageView.topAnchor.constraint(equalTo: topAnchor),
      imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
      imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
      imageView.trailingAnchor.constraint(equalTo: trailingAnchor)
    ])
    registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: TVUIKitPersonAvatarView, _) in
      view.redrawMonogramIfNeeded()
    }
  }

  public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  public func configure(name: String, photoURL: URL?, diameter: CGFloat) {
    imageTask?.cancel()
    imageTask = nil
    currentURL = photoURL
    self.name = name

    let cached = TVUIKitRemoteImage.cached(url: photoURL)
    if let photo = TVUIKitPersonPhoto.displayable(cached, url: photoURL) {
      showsMonogram = false
      imageView.image = photo
    } else {
      showsMonogram = true
      monogramDiameter = 0
      let side = diameter > 1 ? diameter : 180
      imageView.image = TVUIKitTileArtwork.monogram(name: name, diameter: side, traits: traitCollection)
    }

    guard let url = photoURL else {
      ArtworkLog.skipped(by: "person-hero/\(name)", reason: "no photo URL")
      return
    }
    if cached != nil, !showsMonogram {
      ArtworkLog.servedFromMemory(url, by: "person-hero/\(name)")
      return
    }
    ArtworkLog.requested(url, by: "person-hero/\(name)")
    imageTask = Task { [weak self] in
      let image = await TVUIKitRemoteImage.load(url: url)
      await MainActor.run {
        guard let self, self.currentURL == url else { return }
        if let photo = TVUIKitPersonPhoto.displayable(image, url: url) {
          self.showsMonogram = false
          self.imageView.image = photo
        }
      }
    }
  }

  public override func layoutSubviews() {
    super.layoutSubviews()
    let diameter = min(bounds.width, bounds.height)
    imageView.layer.cornerRadius = diameter / 2
    guard showsMonogram, diameter > 1, abs(diameter - monogramDiameter) > 0.5 else { return }
    monogramDiameter = diameter
    imageView.image = TVUIKitTileArtwork.monogram(name: name, diameter: diameter, traits: traitCollection)
  }

  private func redrawMonogramIfNeeded() {
    guard showsMonogram else { return }
    monogramDiameter = 0
    setNeedsLayout()
  }

  deinit {
    imageTask?.cancel()
  }
}
#endif
