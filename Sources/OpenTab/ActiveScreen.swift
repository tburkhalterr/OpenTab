// Sources/OpenTab/ActiveScreen.swift
import Cocoa

/// The screen the user is working on (the one under the pointer), used by both
/// the panel positioning and the "active screen" scope filter so they agree.
enum ActiveScreen {
    static func current() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main ?? NSScreen.screens[0]
    }

    // CGWindow bounds use a top-left origin anchored to the primary display,
    // whereas NSScreen frames are bottom-left, so the y axis must be flipped.
    static func rectInCGSpace() -> CGRect? {
        guard let primaryHeight = NSScreen.screens.first(where: { $0.frame.origin == .zero })?.frame.height else {
            return nil
        }
        let frame = current().frame
        return CGRect(x: frame.origin.x, y: primaryHeight - frame.maxY,
                      width: frame.width, height: frame.height)
    }
}
