// Sources/OpenTab/ThumbnailProvider.swift
import Cocoa
import ScreenCaptureKit

/// Captures per-window thumbnails via ScreenCaptureKit and caches them by
/// CGWindowID. Only current-Space windows are shareable, so off-Space windows
/// simply never get a thumbnail and fall back to their app icon.
enum ThumbnailProvider {
    private static let maxCachedThumbnails = 128
    private static let cache = ThumbnailCache(capacity: maxCachedThumbnails)
    private static let inFlightLock = NSLock()
    private static var inFlight: Set<CGWindowID> = []

    static func cached(_ id: CGWindowID) -> NSImage? { cache.image(for: id) }

    /// Captures any of `ids` not already cached or already being captured,
    /// invoking `each` on the main thread as each image becomes available. One
    /// SCShareableContent lookup is shared across the batch, and captures run
    /// sequentially to bound cost.
    static func capture(_ ids: [CGWindowID], maxSize: CGFloat, each: @escaping (CGWindowID, NSImage) -> Void) {
        guard #available(macOS 14.0, *) else { return }
        // Dedupe against in-flight captures too: fast type-to-filtering calls this
        // on every keystroke and would otherwise re-run the lookup and re-capture
        // the same not-yet-cached windows concurrently.
        let missing = claim(ids.filter { cache.image(for: $0) == nil })
        guard !missing.isEmpty else { return }

        Task {
            defer { release(missing) }
            guard let content = try? await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: true) else { return }
            for id in missing {
                guard let window = content.windows.first(where: { $0.windowID == id }),
                      let image = await captureWindow(window, maxSize: maxSize) else { continue }
                cache.store(image, for: id)
                await MainActor.run { each(id, image) }
            }
        }
    }

    private static func claim(_ ids: [CGWindowID]) -> [CGWindowID] {
        inFlightLock.lock(); defer { inFlightLock.unlock() }
        let picked = ids.filter { !inFlight.contains($0) }
        inFlight.formUnion(picked)
        return picked
    }

    private static func release(_ ids: [CGWindowID]) {
        inFlightLock.lock(); defer { inFlightLock.unlock() }
        inFlight.subtract(ids)
    }

    @available(macOS 14.0, *)
    private static func captureWindow(_ window: SCWindow, maxSize: CGFloat) async -> NSImage? {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        let longest = max(window.frame.width, window.frame.height)
        let scale = longest > maxSize ? maxSize / longest : 1
        config.width = max(1, Int(window.frame.width * scale))
        config.height = max(1, Int(window.frame.height * scale))
        config.showsCursor = false
        guard let cgImage = try? await SCScreenshotManager.captureImage(
            contentFilter: filter, configuration: config) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}

/// LRU-bounded, lock-guarded store so the process-lifetime cache stays small
/// and is safe to touch from the capture `Task` as well as the main thread.
final class ThumbnailCache: @unchecked Sendable {
    private let capacity: Int
    private let lock = NSLock()
    private var storage: [CGWindowID: NSImage] = [:]
    private var usage: [CGWindowID] = []          // least-recently-used first

    init(capacity: Int) { self.capacity = max(1, capacity) }

    func image(for id: CGWindowID) -> NSImage? {
        lock.lock(); defer { lock.unlock() }
        guard let image = storage[id] else { return nil }
        touch(id)
        return image
    }

    func store(_ image: NSImage, for id: CGWindowID) {
        lock.lock(); defer { lock.unlock() }
        storage[id] = image
        touch(id)
        while usage.count > capacity {
            storage[usage.removeFirst()] = nil
        }
    }

    var count: Int {
        lock.lock(); defer { lock.unlock() }
        return storage.count
    }

    private func touch(_ id: CGWindowID) {
        if let existing = usage.firstIndex(of: id) { usage.remove(at: existing) }
        usage.append(id)
    }
}
