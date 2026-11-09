import Foundation
import SwiftUI
import AppKit

#if os(macOS)

/// A class that manages the window settings, including the "always on top" feature.
@MainActor
@Observable
class WindowSettings {
    var alwaysOnTop = UserDefaults.standard.bool(forKey: "alwaysOnTop") {
        didSet {
            UserDefaults.standard.set(alwaysOnTop, forKey: "alwaysOnTop")
            updateWindowLevel()
        }
    }
    
    /// Updates the window level based on the "always on top" setting.
    func updateWindowLevel() {
        if alwaysOnTop {
            NSApp.windows.forEach { window in
                window.level = .floating
            }
        } else {
            NSApp.windows.forEach { window in
                window.level = .normal
            }
        }
    }
}
#endif

