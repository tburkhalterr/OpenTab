// Tests/OpenTabTests/HelperTests.swift
import XCTest
import Cocoa
@testable import OpenTab

final class HelperTests: XCTestCase {
    private func window(_ id: CGWindowID, bounds: CGRect) -> WindowInfo {
        WindowInfo(id: id, pid: 1, title: "W\(id)", appName: "App", icon: nil, bounds: bounds,
                   isMinimized: false, isHidden: false, windowCount: 1, axElement: nil)
    }

    // MARK: ActiveScreen coordinate flip

    func testCGRectFlipPrimaryScreen() {
        let frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        XCTAssertEqual(ActiveScreen.cgRect(for: frame, primaryHeight: 1080),
                       CGRect(x: 0, y: 0, width: 1920, height: 1080))
    }

    func testCGRectFlipSecondaryBelow() {
        // A screen sitting below the primary in AppKit (origin.y negative)
        // maps to a positive y in CG's top-left space.
        let frame = CGRect(x: 0, y: -1080, width: 1920, height: 1080)
        XCTAssertEqual(ActiveScreen.cgRect(for: frame, primaryHeight: 1080),
                       CGRect(x: 0, y: 1080, width: 1920, height: 1080))
    }

    // MARK: scope intersection

    func testIntersectingFiltersByRect() {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let onScreen = window(1, bounds: CGRect(x: 100, y: 100, width: 400, height: 300))
        let offScreen = window(2, bounds: CGRect(x: 2000, y: 0, width: 400, height: 300))
        let result = WindowManager.windows([onScreen, offScreen], intersecting: screen)
        XCTAssertEqual(result.map(\.id), [1])
    }

    // MARK: MRU ordering

    func testMRUOrderingKnownFirstThenStableFallback() {
        let a = window(1, bounds: .zero)
        let b = window(2, bounds: .zero)
        let c = window(3, bounds: .zero)
        // MRU says id3 then id1 were used most recently.
        let result = MRUTracker.ordered([a, b, c], byMRU: [3, 1])
        XCTAssertEqual(result.map(\.id), [3, 1, 2])
    }

    func testMRUOrderingEmptyKeepsInputOrder() {
        let a = window(1, bounds: .zero)
        let b = window(2, bounds: .zero)
        XCTAssertEqual(MRUTracker.ordered([a, b], byMRU: []).map(\.id), [1, 2])
    }

    // MARK: sort order

    private func titled(_ id: CGWindowID, title: String, app: String) -> WindowInfo {
        WindowInfo(id: id, pid: 1, title: title, appName: app, icon: nil, bounds: .zero,
                   isMinimized: false, isHidden: false, windowCount: 1, axElement: nil)
    }

    func testSortRecentUsesMRU() {
        let a = titled(1, title: "Zed", app: "Zeta")
        let b = titled(2, title: "Alpha", app: "Acme")
        let result = WindowManager.sorted([a, b], by: .recent, mruOrder: [2, 1])
        XCTAssertEqual(result.map(\.id), [2, 1])
    }

    func testSortAlphabeticalByTitle() {
        let a = titled(1, title: "Zed", app: "Acme")
        let b = titled(2, title: "alpha", app: "Zeta")
        let result = WindowManager.sorted([a, b], by: .alphabetical, mruOrder: [1, 2])
        XCTAssertEqual(result.map(\.id), [2, 1])
    }

    func testSortByAppGroupsByAppName() {
        let a = titled(1, title: "B", app: "Zeta")
        let b = titled(2, title: "A", app: "Acme")
        let c = titled(3, title: "A", app: "Zeta")
        let result = WindowManager.sorted([a, b, c], by: .byApp, mruOrder: [1, 2, 3])
        XCTAssertEqual(result.map(\.id), [2, 3, 1])
    }

    // MARK: fuzzy filter

    func testFuzzyMatchesSubsequence() {
        XCTAssertNotNil(FuzzyMatch.score("github desktop", query: "ghd"))
        XCTAssertNil(FuzzyMatch.score("safari", query: "xyz"))
    }

    func testFuzzyContiguousBeatsScattered() {
        let contiguous = FuzzyMatch.score("github", query: "git")
        let scattered = FuzzyMatch.score("go into tab", query: "git")
        XCTAssertNotNil(contiguous)
        XCTAssertNotNil(scattered)
        XCTAssertGreaterThan(contiguous!, scattered!)
    }

    func testFilterRanksBestMatchFirst() {
        let exact = titled(1, title: "Notes", app: "Notes")
        let loose = titled(2, title: "Network Utility", app: "System")
        let result = WindowManager.filter([loose, exact], query: "note")
        XCTAssertEqual(result.first?.id, 1)
    }

    func testFilterEmptyQueryKeepsOrder() {
        let a = titled(1, title: "A", app: "X")
        let b = titled(2, title: "B", app: "Y")
        XCTAssertEqual(WindowManager.filter([a, b], query: "  ").map(\.id), [1, 2])
    }
}
