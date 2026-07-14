// Sources/OpenTab/CrossSpaceFocus.swift
import Cocoa

// Activating an app so macOS switches to its Space (honouring the "switch to a
// Space with open windows" setting) is exactly what the Dock and Cmd+Tab do via
// this private SkyLight call. Passing window id 0 activates the app WITHOUT
// targeting a specific window, which is what lets macOS change Space instead of
// summoning a window onto the current one. NSRunningApplication.activate() is
// too weak to trigger this on recent macOS.

private struct PSN {
    var high: UInt32 = 0
    var low: UInt32 = 0
}

@_silgen_name("GetProcessForPID")
private func GetProcessForPID(_ pid: pid_t, _ psn: UnsafeMutablePointer<PSN>) -> Int32

@_silgen_name("_SLPSSetFrontProcessWithOptions")
private func SLPSSetFrontProcessWithOptions(_ psn: UnsafePointer<PSN>, _ windowID: CGWindowID, _ mode: UInt32) -> Int32

enum CrossSpaceFocus {
    private static let userGenerated: UInt32 = 0x200

    static func activateApp(pid: pid_t) {
        var psn = PSN()
        guard GetProcessForPID(pid, &psn) == 0 else { return }
        _ = SLPSSetFrontProcessWithOptions(&psn, 0, userGenerated)
    }
}
