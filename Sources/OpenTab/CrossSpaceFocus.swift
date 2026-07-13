// Sources/OpenTab/CrossSpaceFocus.swift
import Cocoa

// AX cannot reach windows on other Spaces. To focus one we switch the visible
// Space to the window's Space via SkyLight; once it is on screen AX can raise
// it. We deliberately avoid the SLPS "set front process" event sequence — it
// breaks full-screen windows.

@_silgen_name("SLSMainConnectionID")
private func SLSMainConnectionID() -> Int32

@_silgen_name("SLSCopySpacesForWindows")
private func SLSCopySpacesForWindows(_ cid: Int32, _ mask: Int32, _ windows: CFArray) -> CFArray?

@_silgen_name("SLSCopyManagedDisplaySpaces")
private func SLSCopyManagedDisplaySpaces(_ cid: Int32) -> CFArray?

@_silgen_name("CGSManagedDisplaySetCurrentSpace")
private func CGSManagedDisplaySetCurrentSpace(_ cid: Int32, _ display: CFString, _ space: UInt64)

enum CrossSpaceFocus {
    private static let allSpacesMask: Int32 = 0x7

    @discardableResult
    static func switchToSpace(of windowID: CGWindowID) -> Bool {
        let cid = SLSMainConnectionID()
        let windows = [windowID] as CFArray
        guard let target = (SLSCopySpacesForWindows(cid, allSpacesMask, windows) as? [NSNumber])?.first?.uint64Value,
              let displays = SLSCopyManagedDisplaySpaces(cid) as? [[String: Any]] else {
            return false
        }

        for display in displays {
            guard let identifier = display["Display Identifier"] as? String,
                  let spaces = display["Spaces"] as? [[String: Any]] else { continue }
            let ids = spaces.compactMap { ($0["id64"] as? NSNumber)?.uint64Value }
            if ids.contains(target) {
                CGSManagedDisplaySetCurrentSpace(cid, identifier as CFString, target)
                return true
            }
        }
        return false
    }
}
