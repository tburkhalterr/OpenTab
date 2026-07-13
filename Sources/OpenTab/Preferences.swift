// Sources/OpenTab/Preferences.swift
import Foundation

/// How the switcher lays out its entries. Mirrors AltTab's view modes.
enum SwitcherLayout: String, CaseIterable, Codable {
    case appGrid    // thumbnails / icons in a horizontal row, one cell per window
    case list       // vertical list, icon + title per row
    case appOnly    // one cell per application (collapses that app's windows)
}

/// Which windows are eligible to appear in the switcher.
enum WindowScope: String, CaseIterable, Codable {
    case allScreens        // every window on every display
    case activeScreen      // only windows on the screen with the cursor / focus
    case activeSpace       // only windows on the current Mission Control space
}

struct Preferences: Codable {
    var layout: SwitcherLayout = .appGrid
    var scope: WindowScope = .allScreens
    var showMinimizedWindows: Bool = true
    var showHiddenApps: Bool = false

    // Keybindings are stored as (keyCode, carbonModifierMask) pairs so they can
    // be rebound from a future preferences UI without touching the hot-key code.
    var nextKeyCode: UInt32 = 48        // kVK_Tab
    var nextModifiers: UInt32 = 0x0800  // optionKey
    var reverseAddsShift: Bool = true

    static let storageKey = "ch.socraft.opentab.preferences"

    static func load() -> Preferences {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode(Preferences.self, from: data) else {
            return Preferences()
        }
        return decoded
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
}
