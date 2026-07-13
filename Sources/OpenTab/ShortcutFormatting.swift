// Sources/OpenTab/ShortcutFormatting.swift
import AppKit
import Carbon.HIToolbox

enum ShortcutFormatting {
    static func modifierSymbols(_ carbonMask: UInt32) -> String {
        var symbols = ""
        if carbonMask & UInt32(controlKey) != 0 { symbols += "⌃" }
        if carbonMask & UInt32(optionKey)  != 0 { symbols += "⌥" }
        if carbonMask & UInt32(shiftKey)   != 0 { symbols += "⇧" }
        if carbonMask & UInt32(cmdKey)     != 0 { symbols += "⌘" }
        return symbols
    }

    static func keyName(_ keyCode: UInt32) -> String {
        switch Int(keyCode) {
        case kVK_Tab:          return "⇥"
        case kVK_Space:        return "Space"
        case kVK_Return:       return "↩"
        case kVK_Escape:       return "⎋"
        case kVK_ANSI_Grave:   return "`"
        default:               return specialKeyNames[Int(keyCode)] ?? "Key \(keyCode)"
        }
    }

    static func describe(keyCode: UInt32, modifiers: UInt32) -> String {
        modifierSymbols(modifiers) + keyName(keyCode)
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var mask: UInt32 = 0
        if flags.contains(.control) { mask |= UInt32(controlKey) }
        if flags.contains(.option)  { mask |= UInt32(optionKey) }
        if flags.contains(.shift)   { mask |= UInt32(shiftKey) }
        if flags.contains(.command) { mask |= UInt32(cmdKey) }
        return mask
    }

    static func appKitModifiers(from carbonMask: UInt32) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if carbonMask & UInt32(controlKey) != 0 { flags.insert(.control) }
        if carbonMask & UInt32(optionKey)  != 0 { flags.insert(.option) }
        if carbonMask & UInt32(shiftKey)   != 0 { flags.insert(.shift) }
        if carbonMask & UInt32(cmdKey)     != 0 { flags.insert(.command) }
        return flags
    }

    private static let specialKeyNames: [Int: String] = [
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4",
        kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8",
        kVK_ANSI_A: "A", kVK_ANSI_S: "S", kVK_ANSI_D: "D", kVK_ANSI_W: "W",
        kVK_ANSI_Q: "Q", kVK_ANSI_E: "E", kVK_ANSI_1: "1", kVK_ANSI_2: "2"
    ]
}
