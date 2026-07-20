// Sources/OpenTab/WindowSpaces.swift
import Cocoa

// No public API reports which Space a window belongs to. AltTab, yabai and other
// window managers rely on these private CoreGraphics Spaces symbols. A window
// that belongs to no Space is one the window server still lists but that its app
// has actually closed — browsers in particular retain such phantoms off-Space.
private typealias CGSConnectionID = Int32

@_silgen_name("CGSMainConnectionID")
private func CGSMainConnectionID() -> CGSConnectionID

@_silgen_name("CGSCopySpacesForWindows")
private func CGSCopySpacesForWindows(_ cid: CGSConnectionID, _ mask: Int32, _ windows: CFArray) -> Unmanaged<CFArray>?

enum WindowSpaces {
    // current | other | fullscreen — every Space kind a live window can sit on.
    private static let allSpacesMask: Int32 = 7

    /// The subset of `ids` that belong to at least one Space. Ids absent from the
    /// result are retained-but-closed windows the window server still reports.
    /// Fails open: if the private symbol is unavailable, every id is kept.
    static func onAnySpace(_ ids: [CGWindowID]) -> Set<CGWindowID> {
        guard !ids.isEmpty else { return [] }
        let cid = CGSMainConnectionID()
        return Set(ids.filter { belongsToASpace($0, connection: cid) })
    }

    private static func belongsToASpace(_ id: CGWindowID, connection cid: CGSConnectionID) -> Bool {
        guard let spaces = CGSCopySpacesForWindows(cid, allSpacesMask, [id] as CFArray)?
            .takeRetainedValue() as? [Int] else {
            return true
        }
        return !spaces.isEmpty
    }
}
