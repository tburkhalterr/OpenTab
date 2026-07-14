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

    // Tab bars / title-bar accessories are short strips; drop them when no AX
    // subrole is available to identify a real window (off-Space or no permission).
    private static let minChromeStripHeight: CGFloat = 100

    private struct AXEntry {
        let element: AXUIElement
        let title: String?
        let minimized: Bool
        let appHidden: Bool
        let appName: String
        let icon: NSImage?
    }

    /// The window universe comes from CGWindowList in `optionAll` mode, which
    /// spans every Space (unlike AX, which only reports the current Space).
    /// AX then enriches current-Space windows with real titles and per-window
    /// elements; off-Space windows fall back to their CG name / app name.
    static func listWindows(preferences: Preferences) -> [WindowInfo] {
        let ax = axIndex()
        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        let regularPIDs = Set(apps.map(\.processIdentifier))
        let hiddenPIDs = Set(apps.filter(\.isHidden).map(\.processIdentifier))
        let appByPID = Dictionary(apps.map { ($0.processIdentifier, $0) }, uniquingKeysWith: { first, _ in first })

        let geometry = currentSpaceGeometry()
        let currentSpaceIDs = Set(geometry.keys)
        let ownPID = ProcessInfo.processInfo.processIdentifier

        guard let raw = CGWindowListCopyWindowInfo([.excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        var seen = Set<CGWindowID>()
        var windows: [WindowInfo] = []

        for entry in raw {
            guard let layer = entry[kCGWindowLayer as String] as? Int, layer == 0,
                  let id = entry[kCGWindowNumber as String] as? CGWindowID, seen.insert(id).inserted,
                  let pid = entry[kCGWindowOwnerPID as String] as? pid_t,
                  pid != ownPID, regularPIDs.contains(pid),
                  let boundsDict = entry[kCGWindowBounds as String] as? [String: CGFloat],
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else {
                continue
            }

            let axEntry = ax[id]
            let app = appByPID[pid]
            let onScreen = currentSpaceIDs.contains(id)
            let minimized = axEntry?.minimized ?? false
            let hidden = axEntry?.appHidden ?? hiddenPIDs.contains(pid)

            if axEntry == nil {
                // AX fully covers the current Space, so a current-Space window it
                // omits is chrome; off-Space windows just aren't in AX at all.
                if !ax.isEmpty && onScreen { continue }
                if bounds.height < minChromeStripHeight { continue }
            } else if !onScreen && !minimized && !hidden {
                // A current-Space standard window that is not on screen is a
                // background native tab; collapse it.
                continue
            }

            if minimized && !preferences.showMinimizedWindows { continue }
            if hidden && !preferences.showHiddenApps { continue }

            let appName = axEntry?.appName ?? app?.localizedName
                ?? entry[kCGWindowOwnerName as String] as? String ?? "Unknown"
            // A window with no real title that AX doesn't expose as a standard
            // window is a hidden helper window (fixed 500×500 placeholder, etc.).
            let realTitle = nonEmpty(axEntry?.title) ?? nonEmpty(entry[kCGWindowName as String] as? String)
            if realTitle == nil && axEntry == nil { continue }
            let title = realTitle ?? appName

            windows.append(WindowInfo(id: id, pid: pid, title: title, appName: appName,
                                      icon: axEntry?.icon ?? app?.icon, bounds: bounds,
                                      isMinimized: minimized, isHidden: hidden,
                                      windowCount: 1, axElement: axEntry?.element))
        }

        let ordered = windows.sorted { lhs, rhs in
            let l = geometry[lhs.id]?.order ?? Int.max
            let r = geometry[rhs.id]?.order ?? Int.max
            if l != r { return l < r }
            return (lhs.appName, lhs.title) < (rhs.appName, rhs.title)
        }

        return applyScope(preferences.scope, to: MRUTracker.shared.ordered(collapseNativeTabs(ordered)))
    }

    // Native tabs on other Spaces can't be spotted via AX (current-Space only),
    // but every tab in a group shares the exact same frame, so one window per
    // (app, frame) collapses them. Only off-Space, non-minimized windows are
    // eligible: current-Space windows are already uniquely identified and
    // minimized windows have degenerate frames that must not be folded together.
    private static func collapseNativeTabs(_ windows: [WindowInfo]) -> [WindowInfo] {
        var seen = Set<String>()
        return windows.filter { window in
            guard window.axElement == nil, !window.isMinimized else { return true }
            let key = "\(window.pid):\(Int(window.bounds.minX)):\(Int(window.bounds.minY))"
                + ":\(Int(window.bounds.width)):\(Int(window.bounds.height))"
            return seen.insert(key).inserted
        }
    }

    static func focus(_ window: WindowInfo) {
        MRUTracker.shared.promote(window.id)
        let app = NSRunningApplication(processIdentifier: window.pid)
        if window.isHidden { app?.unhide() }

        if let axWindow = window.axElement {
            activate(app)
            raise(axWindow)
            return
        }

        // Off-Space window: the Space switch is asynchronous, so the window is
        // not immediately reachable via AX. Switch, activate, then retry the
        // precise raise until it appears on the now-current Space.
        CrossSpaceFocus.switchToSpace(of: window.id)
        activate(app)
        raiseWhenReachable(pid: window.pid, id: window.id)
    }

    private static func activate(_ app: NSRunningApplication?) {
        if #available(macOS 14.0, *) {
            app?.activate()
        } else {
            app?.activate(options: [.activateIgnoringOtherApps])
        }
    }

    private static func raise(_ axWindow: AXUIElement) {
        AXUIElementSetAttributeValue(axWindow, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        AXUIElementSetAttributeValue(axWindow, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
    }

    private static let maxRaiseRetries = 8
    private static let raiseRetryDelay: TimeInterval = 0.06

    private static func raiseWhenReachable(pid: pid_t, id: CGWindowID, attempt: Int = 0) {
        if let axWindow = axWindow(pid: pid, id: id) {
            raise(axWindow)
            return
        }
        guard attempt < maxRaiseRetries else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + raiseRetryDelay) {
            raiseWhenReachable(pid: pid, id: id, attempt: attempt + 1)
        }
    }

    private static func axWindow(pid: pid_t, id: CGWindowID) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, axTimeout)
        return copyWindows(of: app)?.first { windowID(of: $0) == id }
    }

    // MARK: - AX window index (current Space: real titles + per-window element)

    private static func axIndex() -> [CGWindowID: AXEntry] {
        var index: [CGWindowID: AXEntry] = [:]

        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(appElement, axTimeout)
            guard let axWindows = copyWindows(of: appElement) else { continue }

            let appName = app.localizedName ?? "Unknown"
            for axWindow in axWindows {
                guard let id = windowID(of: axWindow), isStandardWindow(axWindow) else { continue }
                index[id] = AXEntry(element: axWindow,
                                    title: stringValue(axWindow, kAXTitleAttribute),
                                    minimized: boolValue(axWindow, kAXMinimizedAttribute),
                                    appHidden: app.isHidden, appName: appName, icon: app.icon)
            }
        }
        return index
    }

    // MARK: - Current-Space geometry (bounds + front-to-back order)

    private static func currentSpaceGeometry() -> [CGWindowID: (bounds: CGRect, order: Int)] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return [:]
        }

        var map: [CGWindowID: (CGRect, Int)] = [:]
        var order = 0
        for entry in raw {
            guard let layer = entry[kCGWindowLayer as String] as? Int, layer == 0,
                  let id = entry[kCGWindowNumber as String] as? CGWindowID,
                  let boundsDict = entry[kCGWindowBounds as String] as? [String: CGFloat],
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else {
                continue
            }
            map[id] = (bounds, order)
            order += 1
        }
        return map
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
