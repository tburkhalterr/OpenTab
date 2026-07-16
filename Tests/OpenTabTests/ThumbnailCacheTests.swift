// Tests/OpenTabTests/ThumbnailCacheTests.swift
import XCTest
import Cocoa
@testable import OpenTab

final class ThumbnailCacheTests: XCTestCase {
    private let image = NSImage(size: NSSize(width: 1, height: 1))

    func testStoresAndReturnsImage() {
        let cache = ThumbnailCache(capacity: 4)
        cache.store(image, for: 1)
        XCTAssertNotNil(cache.image(for: 1))
        XCTAssertNil(cache.image(for: 2))
    }

    func testEvictsLeastRecentlyUsedBeyondCapacity() {
        let cache = ThumbnailCache(capacity: 2)
        cache.store(image, for: 1)
        cache.store(image, for: 2)
        cache.store(image, for: 3)          // evicts 1

        XCTAssertNil(cache.image(for: 1))
        XCTAssertNotNil(cache.image(for: 2))
        XCTAssertNotNil(cache.image(for: 3))
        XCTAssertEqual(cache.count, 2)
    }

    func testAccessRefreshesRecency() {
        let cache = ThumbnailCache(capacity: 2)
        cache.store(image, for: 1)
        cache.store(image, for: 2)
        _ = cache.image(for: 1)             // 1 is now most-recently used
        cache.store(image, for: 3)          // evicts 2, not 1

        XCTAssertNotNil(cache.image(for: 1))
        XCTAssertNil(cache.image(for: 2))
        XCTAssertNotNil(cache.image(for: 3))
    }

    func testCountNeverExceedsCapacity() {
        let cache = ThumbnailCache(capacity: 3)
        for id in 0..<20 { cache.store(image, for: CGWindowID(id)) }
        XCTAssertEqual(cache.count, 3)
    }
}
