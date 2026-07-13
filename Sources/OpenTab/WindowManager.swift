// Sources/OpenTab/WindowManager.swift
import Cocoa
import ApplicationServices

// No public API maps an AXUIElement window to its CGWindowID; AltTab and other
// switchers rely on this same private symbol.
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError

struct WindowInfo: Identifiable {
    let id: CGWindowID
    let pid: pid_t
    let title: String
    let appName: String
    let icon: NSImage?
    let bounds: CGRect
    let isMinimized: Bool
    let isHidden: Bool
    let windowCount: Int
    let axElement: AXUIElement?
}

enum WindowManager {
    // Cap AX round-trips so an unresponsive app cannot stall the switcher.
    private static let axTimeout: Float = 0.25

    private struct AXEntry {
        let pid: pid_t
        let element: AXUIElement
        let title: String?
        let minimized: Bool
        let appHidden: Bool
        let appName: String
        let icon: NSImage?
    }

    static func listWindows(preferences: Preferences) -> [WindowInfo] {
        let ax = axIndex()
        let onScreen = MRUTracker.shared.ordered(onScreenWindows(ax: ax))
        var result = applyScope(preferences.scope, to: onScreen)

        if preferences.showMinimizedWindows || preferences.showHiddenApps {
            let known = Set(onScreen.map(\.id))
            result.append(contentsOf: offScreenWindows(ax: ax, excluding: known, preferences: preferences))
        }
        return result
    }

    static func focus(_ window: WindowInfo) {
        MRUTracker.shared.promote(window.id)
        let app = NSRunningApplication(processIdentifier: window.pid)
        if window.isHidden { app?.unhide() }

        if let axWindow = window.axElement {
            AXUIElementSetAttributeValue(axWindow, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
            AXUIElementSetAttributeValue(axWindow, kAXMainAttribute as CFString, kCFBooleanTrue)
        }
        app?.activate(options: [.activateIgnoringOtherApps])
    }

    // MARK: - AX window index (real titles, minimized state, per-window element)

    private static func axIndex() -> [CGWindowID: AXEntry] {
        var index: [CGWindowID: AXEntry] = [:]

        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(appElement, axTimeout)
            guard let axWindows = copyWindows(of: appElement) else { continue }

            let appName = app.localizedName ?? "Unknown"
            for axWindow in axWindows {
                guard let id = windowID(of: axWindow), isStandardWindow(axWindow) else { continue }
                index[id] = AXEntry(pid: app.processIdentifier, element: axWindow,
                                    title: stringValue(axWindow, kAXTitleAttribute),
                                    minimized: boolValue(axWindow, kAXMinimizedAttribute),
                                    appHidden: app.isHidden, appName: appName, icon: app.icon)
            }
        }
        return index
    }

    // MARK: - On-screen windows (CGWindowList gives front-to-back order + bounds)

    private static func onScreenWindows(ax: [CGWindowID: AXEntry]) -> [WindowInfo] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        let hasAX = !ax.isEmpty
        var iconCache: [pid_t: NSImage?] = [:]

        return raw.compactMap { entry in
            guard let layer = entry[kCGWindowLayer as String] as? Int, layer == 0,
                  let id = entry[kCGWindowNumber as String] as? CGWindowID,
                  let pid = entry[kCGWindowOwnerPID as String] as? pid_t, pid != ownPID,
                  let boundsDict = entry[kCGWindowBounds as String] as? [String: CGFloat],
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else {
                return nil
            }

            // With AX available, keep only windows the app exposes as standard
            // windows; this drops tab-bar / title-bar accessory windows.
            if hasAX && ax[id] == nil { return nil }

            let appName = entry[kCGWindowOwnerName as String] as? String ?? "Unknown"
            let cgName = nonEmpty(entry[kCGWindowName as String] as? String)
            let title = nonEmpty(ax[id]?.title) ?? cgName ?? appName
            let icon = iconCache[pid] ?? {
                let image = NSRunningApplication(processIdentifier: pid)?.icon
                iconCache[pid] = image
                return image
            }()

            return WindowInfo(id: id, pid: pid, title: title, appName: appName, icon: icon,
                              bounds: bounds, isMinimized: false, isHidden: false,
                              windowCount: 1, axElement: ax[id]?.element)
        }
    }

    // MARK: - Off-screen windows (minimized windows + hidden apps)

    private static func offScreenWindows(ax: [CGWindowID: AXEntry], excluding known: Set<CGWindowID>,
                                         preferences: Preferences) -> [WindowInfo] {
        ax.compactMap { id, entry -> WindowInfo? in
            guard !known.contains(id) else { return nil }
            let include = (entry.minimized && preferences.showMinimizedWindows)
                || (entry.appHidden && preferences.showHiddenApps)
            guard include else { return nil }

            let title = nonEmpty(entry.title) ?? entry.appName
            return WindowInfo(id: id, pid: entry.pid, title: title, appName: entry.appName, icon: entry.icon,
                              bounds: .zero, isMinimized: entry.minimized, isHidden: entry.appHidden,
                              windowCount: 1, axElement: entry.element)
        }
        .sorted { ($0.appName, $0.title) < ($1.appName, $1.title) }
    }

    // MARK: - Accessibility helpers

    private static func copyWindows(of app: AXUIElement) -> [AXUIElement]? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success else {
            return nil
        }
        return value as? [AXUIElement]
    }

    private static func windowID(of element: AXUIElement) -> CGWindowID? {
        var id: CGWindowID = 0
        return _AXUIElementGetWindow(element, &id) == .success ? id : nil
    }

    // Real windows have the "AXStandardWindow" subrole; tab bars, title-bar
    // accessories and other chrome are separate NSWindows we must skip.
    private static func isStandardWindow(_ element: AXUIElement) -> Bool {
        stringValue(element, kAXSubroleAttribute) == kAXStandardWindowSubrole
    }

    private static func boolValue(_ element: AXUIElement, _ attribute: String) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let cfValue = value, CFGetTypeID(cfValue) == CFBooleanGetTypeID() else {
            return false
        }
        return CFBooleanGetValue((cfValue as! CFBoolean))
    }

    private static func stringValue(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private static func nonEmpty(_ text: String?) -> String? {
        guard let text, !text.isEmpty else { return nil }
        return text
    }

    // MARK: - Scope filtering

    private static func applyScope(_ scope: WindowScope, to windows: [WindowInfo]) -> [WindowInfo] {
        guard scope == .activeScreen, let screenRect = activeScreenRectInCGSpace() else {
            return windows
        }
        return windows.filter { $0.bounds.intersects(screenRect) }
    }

    // CGWindow bounds use a top-left origin anchored to the primary display,
    // whereas NSScreen frames are bottom-left, so the y axis must be flipped.
    private static func activeScreenRectInCGSpace() -> CGRect? {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }),
              let primaryHeight = NSScreen.screens.first(where: { $0.frame.origin == .zero })?.frame.height else {
            return nil
        }
        let frame = screen.frame
        return CGRect(x: frame.origin.x, y: primaryHeight - frame.maxY,
                      width: frame.width, height: frame.height)
    }
}
