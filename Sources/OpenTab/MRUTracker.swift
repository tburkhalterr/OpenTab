// Sources/OpenTab/MRUTracker.swift
import Cocoa
import ApplicationServices

@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError

/// Tracks window focus over time so the switcher can order windows by real
/// most-recently-used rank instead of the instantaneous on-screen z-order.
final class MRUTracker {
    static let shared = MRUTracker()

    private static let maxTracked = 200

    private var order: [CGWindowID] = []
    private var axObserver: AXObserver?
    private var observedApp: AXUIElement?

    func start() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(appActivated(_:)),
            name: NSWorkspace.didActivateApplicationNotification, object: nil)

        if let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier {
            promoteFocusedWindow(pid: pid)
            observeFocusedWindow(pid: pid)
        }
    }

    func promote(_ id: CGWindowID) {
        order.removeAll { $0 == id }
        order.insert(id, at: 0)
        if order.count > Self.maxTracked {
            order.removeLast(order.count - Self.maxTracked)
        }
    }

    /// Known windows first in MRU order, then any unseen window keeping the
    /// original (z-order) sequence it arrived in.
    func ordered(_ windows: [WindowInfo]) -> [WindowInfo] {
        let rankByID = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
        return windows.enumerated().sorted { lhs, rhs in
            let l = rankByID[lhs.element.id] ?? (order.count + lhs.offset)
            let r = rankByID[rhs.element.id] ?? (order.count + rhs.offset)
            return l < r
        }.map(\.element)
    }

    // MARK: - Focus observation

    @objc private func appActivated(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            return
        }
        promoteFocusedWindow(pid: app.processIdentifier)
        observeFocusedWindow(pid: app.processIdentifier)
    }

    private func promoteFocusedWindow(pid: pid_t) {
        guard let id = focusedWindowID(pid: pid) else { return }
        promote(id)
    }

    private func focusedWindowID(pid: pid_t) -> CGWindowID? {
        let app = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let element = value, CFGetTypeID(element) == AXUIElementGetTypeID() else {
            return nil
        }
        var id: CGWindowID = 0
        return _AXUIElementGetWindow((element as! AXUIElement), &id) == .success ? id : nil
    }

    private func observeFocusedWindow(pid: pid_t) {
        teardownObserver()

        var observer: AXObserver?
        let callback: AXObserverCallback = { _, _, _, refcon in
            guard let refcon else { return }
            Unmanaged<MRUTracker>.fromOpaque(refcon).takeUnretainedValue().focusedWindowChanged()
        }
        guard AXObserverCreate(pid, callback, &observer) == .success, let observer else { return }

        let app = AXUIElementCreateApplication(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        AXObserverAddNotification(observer, app, kAXFocusedWindowChangedNotification as CFString, refcon)
        AXObserverAddNotification(observer, app, kAXMainWindowChangedNotification as CFString, refcon)
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)

        axObserver = observer
        observedApp = app
    }

    private func focusedWindowChanged() {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return }
        promoteFocusedWindow(pid: pid)
    }

    private func teardownObserver() {
        guard let axObserver else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(axObserver), .defaultMode)
        self.axObserver = nil
        observedApp = nil
    }
}
