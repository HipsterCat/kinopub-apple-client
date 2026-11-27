//
//  PiraticButtonStyle.swift
//
//
//  Created by Kirill Kunst on 31.07.2023.
//

import Foundation
import SwiftUI

public struct PiraticButtonStyle: ButtonStyle {

  var buttonColor: PiraticButton.ButtonColor
  
  public init(buttonColor: PiraticButton.ButtonColor) {
    self.buttonColor = buttonColor
  }

  public func makeBody(configuration: Self.Configuration) -> some View {
    FocusAwareLabel(configuration: configuration, buttonColor: buttonColor)
  }

  /// Nested so `@Environment(\.isFocused)` resolves against the button itself —
  /// without it tvOS gives no indication of which control the remote is on.
  /// (Must not be named `Body`: that collides with `ButtonStyle.Body`.)
  private struct FocusAwareLabel: View {
    let configuration: ButtonStyle.Configuration
    let buttonColor: PiraticButton.ButtonColor
    @Environment(\.isFocused) private var isFocused

    var body: some View {
      configuration.label
        .foregroundColor(buttonColor.foreground)
        .background(buttonColor.color.opacity(isFocused ? 1.0 : 0.8))
        .cornerRadius(6.0)
        .scaleEffect(isFocused ? 1.05 : (configuration.isPressed ? 0.97 : 1.0))
        .animation(.easeOut(duration: 0.15), value: isFocused)
    }
  }

}
