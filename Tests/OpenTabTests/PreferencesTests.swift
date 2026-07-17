// Tests/OpenTabTests/PreferencesTests.swift
import XCTest
@testable import OpenTab

final class PreferencesTests: XCTestCase {
    func testDecodingPayloadMissingAFieldKeepsOtherSettings() throws {
        // An older release's stored JSON has no `showHiddenApps` key.
        let json = """
        {
          "layout": "list",
          "density": "compact",
          "showThumbnails": false,
          "scope": "activeScreen",
          "showMinimizedWindows": false,
          "triggerKeyCode": 48,
          "triggerModifiers": 4096,
          "reverseAddsShift": false
        }
        """
        let data = Data(json.utf8)

        let decoded = try JSONDecoder().decode(Preferences.self, from: data)

        XCTAssertEqual(decoded.layout, .list)
        XCTAssertEqual(decoded.density, .compact)
        XCTAssertFalse(decoded.showThumbnails)
        XCTAssertEqual(decoded.scope, .activeScreen)
        XCTAssertFalse(decoded.showMinimizedWindows)
        XCTAssertEqual(decoded.triggerKeyCode, 48)
        XCTAssertEqual(decoded.triggerModifiers, 4096)
        XCTAssertFalse(decoded.reverseAddsShift)
        // The missing field falls back to its default rather than failing the
        // whole decode (which would reset every setting).
        XCTAssertEqual(decoded.showHiddenApps, Preferences().showHiddenApps)
    }

    func testRoundTripPreservesValues() throws {
        var prefs = Preferences()
        prefs.layout = .appOnly
        prefs.showThumbnails = false
        prefs.triggerKeyCode = 12

        let data = try JSONEncoder().encode(prefs)
        let decoded = try JSONDecoder().decode(Preferences.self, from: data)

        XCTAssertEqual(decoded, prefs)
    }
}
