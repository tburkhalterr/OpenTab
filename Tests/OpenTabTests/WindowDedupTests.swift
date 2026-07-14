// Tests/OpenTabTests/WindowDedupTests.swift
import XCTest
import Cocoa
@testable import OpenTab

final class WindowDedupTests: XCTestCase {
    private func window(_ id: CGWindowID, pid: pid_t, title: String, app: String = "App",
                        bounds: CGRect = CGRect(x: 0, y: 0, width: 800, height: 600),
                        minimized: Bool = false) -> WindowInfo {
        WindowInfo(id: id, pid: pid, title: title, appName: app, icon: nil, bounds: bounds,
                   isMinimized: minimized, isHidden: false, windowCount: 1, axElement: nil)
    }

    func testFoldsSameTitleSameApp() {
        let a = window(1, pid: 10, title: "Doc", bounds: CGRect(x: 0, y: 0, width: 800, height: 600))
        let b = window(2, pid: 10, title: "Doc", bounds: CGRect(x: 0, y: 40, width: 800, height: 560))
        let result = WindowManager.collapseDuplicates([a, b])
        XCTAssertEqual(result.map(\.id), [1])
    }

    func testFoldsSameFrameSameApp() {
        let a = window(1, pid: 10, title: "Tab A", bounds: CGRect(x: 0, y: 0, width: 800, height: 600))
        let b = window(2, pid: 10, title: "Tab B", bounds: CGRect(x: 0, y: 0, width: 800, height: 600))
        let result = WindowManager.collapseDuplicates([a, b])
        XCTAssertEqual(result.map(\.id), [1])
    }

    func testKeepsDistinctWindows() {
        let a = window(1, pid: 10, title: "Repo A", bounds: CGRect(x: 0, y: 0, width: 800, height: 600))
        let b = window(2, pid: 10, title: "Repo B", bounds: CGRect(x: 900, y: 0, width: 800, height: 600))
        let result = WindowManager.collapseDuplicates([a, b])
        XCTAssertEqual(result.map(\.id), [1, 2])
    }

    func testDedupIsScopedPerApp() {
        let a = window(1, pid: 10, title: "X", bounds: CGRect(x: 0, y: 0, width: 800, height: 600))
        let b = window(2, pid: 20, title: "X", bounds: CGRect(x: 0, y: 0, width: 800, height: 600))
        let result = WindowManager.collapseDuplicates([a, b])
        XCTAssertEqual(result.map(\.id), [1, 2])
    }

    func testMinimizedWindowsAreExempt() {
        let a = window(1, pid: 10, title: "M", bounds: .zero, minimized: true)
        let b = window(2, pid: 10, title: "M", bounds: .zero, minimized: true)
        let result = WindowManager.collapseDuplicates([a, b])
        XCTAssertEqual(result.map(\.id), [1, 2])
    }

    func testCollapseByAppFoldsAndCounts() {
        let windows = [
            window(1, pid: 10, title: "A1", app: "Fork"),
            window(2, pid: 10, title: "A2", app: "Fork"),
            window(3, pid: 20, title: "B1", app: "Slack")
        ]
        let result = SwitcherController.collapseByApp(windows)
        XCTAssertEqual(result.map(\.pid), [10, 20])
        XCTAssertEqual(result.map(\.title), ["Fork", "Slack"])
        XCTAssertEqual(result.first?.windowCount, 2)
        XCTAssertEqual(result.last?.windowCount, 1)
    }
}
