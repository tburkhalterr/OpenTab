// Sources/OpenTab/WindowManager.swift
import Cocoa
import ApplicationServices

/// Private AX SPI used to bridge an AXUIElement window to its CGWindowID.
/// AltTab and other switchers rely on the same symbol; there is no public API.
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError

struct WindowInfo: Identifiable {
    let id: CGWindowID
    let pid: pid_t
    let title: String
    let appName: String
    let icon: NSImage?
}

enum WindowManager {
    /// On-screen, user-facing windows in front-to-back order (as CGWindowList reports them).
    static func listWindows() -> [WindowInfo] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        var seenPIDIcons: [pid_t: NSImage?] = [:]

        return raw.compactMap { entry -> WindowInfo? in
            guard let layer = entry[kCGWindowLayer as String] as? Int, layer == 0,
                  let windowID = entry[kCGWindowNumber as String] as? CGWindowID,
                  let pid = entry[kCGWindowOwnerPID as String] as? pid_t else {
                return nil
            }

            let appName = entry[kCGWindowOwnerName as String] as? String ?? "Unknown"
            let title = entry[kCGWindowName as String] as? String ?? appName

            // Skip our own switcher and untitled chrome windows.
            if pid == ProcessInfo.processInfo.processIdentifier { return nil }

            let icon: NSImage?
            if let cached = seenPIDIcons[pid] {
                icon = cached
            } else {
                icon = NSRunningApplication(processIdentifier: pid)?.icon
                seenPIDIcons[pid] = icon
            }

            return WindowInfo(id: windowID, pid: pid, title: title, appName: appName, icon: icon)
        }
    }

    /// Raises the given window and activates its owning application.
    static func focus(_ window: WindowInfo) {
        let appElement = AXUIElementCreateApplication(window.pid)
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value)

        if result == .success, let axWindows = value as? [AXUIElement] {
            for axWindow in axWindows where matches(axWindow, window.id) {
                AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
                AXUIElementSetAttributeValue(axWindow, kAXMainAttribute as CFString, kCFBooleanTrue)
                break
            }
        }

        NSRunningApplication(processIdentifier: window.pid)?
            .activate(options: [.activateIgnoringOtherApps])
    }

    private static func matches(_ axWindow: AXUIElement, _ windowID: CGWindowID) -> Bool {
        var id: CGWindowID = 0
        return _AXUIElementGetWindow(axWindow, &id) == .success && id == windowID
    }
}
