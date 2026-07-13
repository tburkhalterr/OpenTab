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
}

enum WindowManager {
    static func listWindows(scope: WindowScope = .allScreens) -> [WindowInfo] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        var iconCache: [pid_t: NSImage?] = [:]

        let windows = raw.compactMap { entry -> WindowInfo? in
            guard let layer = entry[kCGWindowLayer as String] as? Int, layer == 0,
                  let id = entry[kCGWindowNumber as String] as? CGWindowID,
                  let pid = entry[kCGWindowOwnerPID as String] as? pid_t, pid != ownPID,
                  let boundsDict = entry[kCGWindowBounds as String] as? [String: CGFloat],
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else {
                return nil
            }

            let appName = entry[kCGWindowOwnerName as String] as? String ?? "Unknown"
            let title = entry[kCGWindowName as String] as? String ?? appName
            let icon = iconCache[pid] ?? {
                let image = NSRunningApplication(processIdentifier: pid)?.icon
                iconCache[pid] = image
                return image
            }()

            return WindowInfo(id: id, pid: pid, title: title, appName: appName, icon: icon, bounds: bounds)
        }

        return applyScope(scope, to: windows)
    }

    static func focus(_ window: WindowInfo) {
        let app = AXUIElementCreateApplication(window.pid)
        var value: CFTypeRef?

        if AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
           let axWindows = value as? [AXUIElement] {
            for axWindow in axWindows where windowID(of: axWindow) == window.id {
                AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
                AXUIElementSetAttributeValue(axWindow, kAXMainAttribute as CFString, kCFBooleanTrue)
                break
            }
        }

        NSRunningApplication(processIdentifier: window.pid)?
            .activate(options: [.activateIgnoringOtherApps])
    }

    private static func windowID(of element: AXUIElement) -> CGWindowID? {
        var id: CGWindowID = 0
        return _AXUIElementGetWindow(element, &id) == .success ? id : nil
    }

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
