// Sources/OpenTab/SystemShortcuts.swift
import AppKit
import Carbon.HIToolbox

/// The keyboard shortcuts macOS reserves for itself, read from the same
/// `com.apple.symbolichotkeys` store that System Settings › Keyboard writes to.
/// Used to reject a binding macOS would swallow before OpenTab ever sees it.
enum SystemShortcuts {
    struct Combo: Hashable {
        let keyCode: UInt32
        let carbonModifiers: UInt32
    }

    // macOS stores this in `parameters[1]` when a shortcut is defined by its
    // character rather than a virtual key code — nothing we can match against.
    private static let unusedKeyCode = 0xFFFF

    static func reserved() -> Set<Combo> {
        guard let entries = CFPreferencesCopyAppValue(
            "AppleSymbolicHotKeys" as CFString,
            "com.apple.symbolichotkeys" as CFString) as? [String: Any] else {
            return []
        }

        var combos: Set<Combo> = []
        for case let entry as [String: Any] in entries.values {
            guard (entry["enabled"] as? NSNumber)?.boolValue == true,
                  let value = entry["value"] as? [String: Any],
                  let parameters = value["parameters"] as? [NSNumber],
                  parameters.count >= 3 else { continue }

            let keyCode = parameters[1].intValue
            guard keyCode >= 0, keyCode != Self.unusedKeyCode else { continue }

            let flags = NSEvent.ModifierFlags(rawValue: parameters[2].uintValue)
                .intersection(.deviceIndependentFlagsMask)
            combos.insert(Combo(keyCode: UInt32(keyCode),
                                carbonModifiers: ShortcutFormatting.carbonModifiers(from: flags)))
        }
        return combos
    }

    static func isReserved(keyCode: UInt32, carbonModifiers: UInt32) -> Bool {
        reserved().contains(Combo(keyCode: keyCode, carbonModifiers: carbonModifiers))
    }
}
