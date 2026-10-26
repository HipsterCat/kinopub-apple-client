//
//  WorkerAdminTextEntryViewController.swift
//
//  Pattern borrowed from Rivulet `TextEntryViewController` (Bain Gurley, 2025–2026):
//  UITextField + system tvOS keyboard, `preferredFocusEnvironments`, Done / Menu.
//

#if os(tvOS)
import UIKit

@MainActor
final class WorkerAdminTextEntryViewController: UIViewController {
  private let initialText: String
  private let onCommit: (String) -> Void
  private let onCancel: (() -> Void)?

  private let textField = UITextField()
  private var doneButton: WorkerAdminTextPillButton!
  private var cancelButton: WorkerAdminTextPillButton!

  init(
    initialText: String,
    onCommit: @escaping (String) -> Void,
    onCancel: (() -> Void)? = nil
  ) {
    self.initialText = initialText
    self.onCommit = onCommit
    self.onCancel = onCancel
    super.init(nibName: nil, bundle: nil)
    modalPresentationStyle = .overFullScreen
    modalTransitionStyle = .crossDissolve
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = UIColor.black.withAlphaComponent(0.45)

    let effect: UIVisualEffect
    if #available(tvOS 26.0, *) { effect = UIGlassEffect() }
    else { effect = UIBlurEffect(style: .regular) }
    let blur = UIVisualEffectView(effect: effect)
    blur.translatesAutoresizingMaskIntoConstraints = false
    blur.layer.cornerRadius = 38
    blur.layer.cornerCurve = .continuous
    blur.clipsToBounds = true

    let card = UIView()
    card.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(card)
    card.addSubview(blur)

    let titleLabel = UILabel()
    titleLabel.text = String(localized: "Password")
    titleLabel.font = .systemFont(ofSize: 32, weight: .semibold)
    titleLabel.textColor = UIColor.white.withAlphaComponent(0.55)
    titleLabel.textAlignment = .center

    textField.text = initialText
    textField.placeholder = String(localized: "Bearer token")
    textField.font = .systemFont(ofSize: 36, weight: .regular)
    textField.textColor = .white
    textField.isSecureTextEntry = true
    textField.keyboardType = .asciiCapable
    textField.autocorrectionType = .no
    textField.autocapitalizationType = .none
    textField.spellCheckingType = .no
    textField.clearButtonMode = .whileEditing
    textField.returnKeyType = .done
    textField.delegate = self
    textField.translatesAutoresizingMaskIntoConstraints = false
    textField.addTarget(self, action: #selector(textChanged), for: .editingChanged)

    let hintLabel = UILabel()
    hintLabel.text = String(localized: "WorkerAdminToken_TVInputTip")
    hintLabel.font = .systemFont(ofSize: 24, weight: .regular)
    hintLabel.textColor = UIColor.white.withAlphaComponent(0.45)
    hintLabel.textAlignment = .center
    hintLabel.numberOfLines = 0

    let stack = UIStackView(arrangedSubviews: [titleLabel, textField, hintLabel])
    stack.axis = .vertical
    stack.alignment = .fill
    stack.spacing = 20

    cancelButton = WorkerAdminTextPillButton(title: String(localized: "Cancel"), prominent: false) { [weak self] in
      self?.cancel()
    }
    doneButton = WorkerAdminTextPillButton(title: String(localized: "Done"), prominent: true) { [weak self] in
      self?.commit()
    }
    let buttonRow = UIStackView(arrangedSubviews: [cancelButton, doneButton])
    buttonRow.axis = .horizontal
    buttonRow.alignment = .center
    buttonRow.distribution = .fillEqually
    buttonRow.spacing = 24
    stack.setCustomSpacing(36, after: hintLabel)
    stack.addArrangedSubview(buttonRow)
    stack.translatesAutoresizingMaskIntoConstraints = false
    blur.contentView.addSubview(stack)

    let pad: CGFloat = 48
    NSLayoutConstraint.activate([
      card.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      card.centerYAnchor.constraint(equalTo: view.centerYAnchor),
      card.widthAnchor.constraint(equalToConstant: 1000),

      blur.topAnchor.constraint(equalTo: card.topAnchor),
      blur.leadingAnchor.constraint(equalTo: card.leadingAnchor),
      blur.trailingAnchor.constraint(equalTo: card.trailingAnchor),
      blur.bottomAnchor.constraint(equalTo: card.bottomAnchor),

      stack.topAnchor.constraint(equalTo: blur.contentView.topAnchor, constant: pad),
      stack.leadingAnchor.constraint(equalTo: blur.contentView.leadingAnchor, constant: pad),
      stack.trailingAnchor.constraint(equalTo: blur.contentView.trailingAnchor, constant: -pad),
      stack.bottomAnchor.constraint(equalTo: blur.contentView.bottomAnchor, constant: -pad),

      textField.heightAnchor.constraint(equalToConstant: 76),
      buttonRow.heightAnchor.constraint(equalToConstant: 72),
    ])

    let menuTap = UITapGestureRecognizer(target: self, action: #selector(menuPressed))
    menuTap.allowedPressTypes = [NSNumber(value: UIPress.PressType.menu.rawValue)]
    view.addGestureRecognizer(menuTap)
  }

  override var preferredFocusEnvironments: [UIFocusEnvironment] {
    [textField]
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    setNeedsFocusUpdate()
    updateFocusIfNeeded()
  }

  @objc private func menuPressed() { cancel() }

  @objc private func textChanged() {
    let raw = textField.text ?? ""
    let filtered = WorkerAdminTokenSanitizer.filter(raw)
    if filtered != raw { textField.text = filtered }
  }

  private func commit() {
    let value = WorkerAdminTokenSanitizer.filter(textField.text ?? "")
    let finish = { [onCommit] in onCommit(value) }
    if presentingViewController != nil {
      dismiss(animated: true, completion: finish)
    } else {
      finish()
    }
  }

  private func cancel() {
    let finish: () -> Void = { [onCancel] in onCancel?() }
    if presentingViewController != nil {
      dismiss(animated: true, completion: finish)
    } else {
      finish()
    }
  }
}

extension WorkerAdminTextEntryViewController: UITextFieldDelegate {
  func textFieldShouldReturn(_ textField: UITextField) -> Bool {
    commit()
    return true
  }
}

private final class WorkerAdminTextPillButton: UIView {
  private let labelView = UILabel()
  private let onPress: () -> Void
  private let prominent: Bool

  override var canBecomeFocused: Bool { true }

  init(title: String, prominent: Bool, onPress: @escaping () -> Void) {
    self.onPress = onPress
    self.prominent = prominent
    super.init(frame: .zero)
    labelView.text = title
    labelView.font = .systemFont(ofSize: 30, weight: .semibold)
    labelView.textAlignment = .center
    labelView.translatesAutoresizingMaskIntoConstraints = false
    addSubview(labelView)
    NSLayoutConstraint.activate([
      labelView.centerXAnchor.constraint(equalTo: centerXAnchor),
      labelView.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])
    layer.cornerRadius = 36
    layer.cornerCurve = .continuous
    let tap = UITapGestureRecognizer(target: self, action: #selector(pressed))
    tap.allowedPressTypes = [NSNumber(value: UIPress.PressType.select.rawValue)]
    addGestureRecognizer(tap)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  @objc private func pressed() { onPress() }

  override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
    super.didUpdateFocus(in: context, with: coordinator)
    let focused = context.nextFocusedView === self
    backgroundColor = focused
      ? .white
      : UIColor.white.withAlphaComponent(prominent ? 0.22 : 0.12)
    labelView.textColor = focused ? .black : .white
  }
}
#endif
