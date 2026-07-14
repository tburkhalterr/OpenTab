// Sources/OpenTab/AX.swift
import Cocoa
import ApplicationServices

// No public API maps an AXUIElement window to its CGWindowID; AltTab and other
// switchers rely on this same private symbol. Declared once for the whole app.
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError

enum AX {
    static func app(_ pid: pid_t, timeout: Float? = nil) -> AXUIElement {
        let element = AXUIElementCreateApplication(pid)
        if let timeout { AXUIElementSetMessagingTimeout(element, timeout) }
        return element
    }

    static func windows(of app: AXUIElement) -> [AXUIElement]? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success else {
            return nil
        }
        return value as? [AXUIElement]
    }

    static func windowID(of element: AXUIElement) -> CGWindowID? {
        var id: CGWindowID = 0
        return _AXUIElementGetWindow(element, &id) == .success ? id : nil
    }

    // Real windows have the "AXStandardWindow" subrole; tab bars, title-bar
    // accessories and other chrome are separate NSWindows we must skip.
    static func isStandardWindow(_ element: AXUIElement) -> Bool {
        string(element, kAXSubroleAttribute) == kAXStandardWindowSubrole
    }

    static func focusedWindowID(pid: pid_t) -> CGWindowID? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app(pid), kAXFocusedWindowAttribute as CFString, &value) == .success,
              let element = value, CFGetTypeID(element) == AXUIElementGetTypeID() else {
            return nil
        }
        return windowID(of: element as! AXUIElement)
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    static func bool(_ element: AXUIElement, _ attribute: String) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let cfValue = value, CFGetTypeID(cfValue) == CFBooleanGetTypeID() else {
            return false
        }
        return CFBooleanGetValue((cfValue as! CFBoolean))
    }
}
