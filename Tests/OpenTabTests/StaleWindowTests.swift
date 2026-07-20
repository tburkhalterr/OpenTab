// Tests/OpenTabTests/StaleWindowTests.swift
import XCTest
import Cocoa
@testable import OpenTab

final class StaleWindowTests: XCTestCase {
    private func window(_ id: CGWindowID, minimized: Bool = false) -> WindowInfo {
        WindowInfo(id: id, pid: 1, title: "W\(id)", appName: "App", icon: nil,
                   bounds: CGRect(x: 0, y: 0, width: 800, height: 600),
                   isMinimized: minimized, isHidden: false, windowCount: 1, axElement: nil)
    }

    func testDropsOffSpaceWindowOnNoSpace() {
        let windows = [window(1), window(2)]
        let result = WindowManager.withoutStaleWindows(windows, currentSpaceIDs: [],
                                                       onAnySpace: { _ in [1] })   // 2 is dead
        XCTAssertEqual(result.map(\.id), [1])
    }

    func testKeepsOffSpaceWindowThatHasASpace() {
        let windows = [window(1), window(2)]
        let result = WindowManager.withoutStaleWindows(windows, currentSpaceIDs: [],
                                                       onAnySpace: { Set($0) })   // all live
        XCTAssertEqual(result.map(\.id), [1, 2])
    }

    func testNeverSuspectsCurrentSpaceWindows() {
        let windows = [window(1), window(2)]
        // Both are on the current Space, so liveness is never consulted.
        let result = WindowManager.withoutStaleWindows(windows, currentSpaceIDs: [1, 2],
                                                       onAnySpace: { _ in [] })
        XCTAssertEqual(result.map(\.id), [1, 2])
    }

    func testExemptsMinimizedWindows() {
        let windows = [window(1, minimized: true)]
        let result = WindowManager.withoutStaleWindows(windows, currentSpaceIDs: [],
                                                       onAnySpace: { _ in [] })   // would be dead if checked
        XCTAssertEqual(result.map(\.id), [1])
    }
}
