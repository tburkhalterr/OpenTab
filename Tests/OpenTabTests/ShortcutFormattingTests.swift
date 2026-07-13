// Tests/OpenTabTests/ShortcutFormattingTests.swift
import XCTest
import AppKit
import Carbon.HIToolbox
@testable import OpenTab

final class ShortcutFormattingTests: XCTestCase {
    func testCarbonModifiersRoundTrip() {
        let flags: NSEvent.ModifierFlags = [.command, .option, .shift, .control]
        let carbon = ShortcutFormatting.carbonModifiers(from: flags)
        XCTAssertEqual(ShortcutFormatting.appKitModifiers(from: carbon), flags)
    }

    func testCarbonModifiersIgnoresNonMaskable() {
        let flags: NSEvent.ModifierFlags = [.option, .capsLock, .function]
        XCTAssertEqual(ShortcutFormatting.carbonModifiers(from: flags), UInt32(optionKey))
    }

    func testModifierSymbolsOrdering() {
        let mask = UInt32(cmdKey) | UInt32(optionKey) | UInt32(controlKey) | UInt32(shiftKey)
        XCTAssertEqual(ShortcutFormatting.modifierSymbols(mask), "⌃⌥⇧⌘")
    }

    func testKeyNameKnownAndUnknown() {
        XCTAssertEqual(ShortcutFormatting.keyName(UInt32(kVK_Tab)), "⇥")
        XCTAssertEqual(ShortcutFormatting.keyName(UInt32(kVK_Space)), "Space")
        XCTAssertEqual(ShortcutFormatting.keyName(9999), "Key 9999")
    }

    func testDescribeDefaultShortcut() {
        let description = ShortcutFormatting.describe(keyCode: UInt32(kVK_Tab), modifiers: UInt32(optionKey))
        XCTAssertEqual(description, "⌥⇥")
    }
}
