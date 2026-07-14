// Sources/OpenTab/WindowManager.swift
import Cocoa
import ApplicationServices

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
    private static let axTimeout: Float = 0.1

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
        let context = Context.build()
        guard let raw = CGWindowListCopyWindowInfo([.excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        var seen = Set<CGWindowID>()
        var windows: [WindowInfo] = []
        for entry in raw {
            guard let window = classify(entry, context: context, preferences: preferences),
                  seen.insert(window.id).inserted else { continue }
            windows.append(window)
        }

        let ordered = windows.sorted { lhs, rhs in
            let l = context.geometry[lhs.id]?.order ?? Int.max
            let r = context.geometry[rhs.id]?.order ?? Int.max
            if l != r { return l < r }
            return (lhs.appName, lhs.title) < (rhs.appName, rhs.title)
        }
        return applyScope(preferences.scope, to: MRUTracker.shared.ordered(collapseDuplicates(ordered)))
    }

    /// Everything the per-window classification needs, gathered once per invocation.
    private struct Context {
        let regularPIDs: Set<pid_t>
        let hiddenPIDs: Set<pid_t>
        let appByPID: [pid_t: NSRunningApplication]
        let geometry: [CGWindowID: (bounds: CGRect, order: Int)]
        let currentSpaceIDs: Set<CGWindowID>
        let ax: [CGWindowID: AXEntry]
        let ownPID: pid_t

        static func build() -> Context {
            let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
            let appByPID = Dictionary(apps.map { ($0.processIdentifier, $0) }, uniquingKeysWith: { first, _ in first })
            let (geometry, currentSpacePIDs) = currentSpaceInfo()
            return Context(
                regularPIDs: Set(apps.map(\.processIdentifier)),
                hiddenPIDs: Set(apps.filter(\.isHidden).map(\.processIdentifier)),
                appByPID: appByPID,
                geometry: geometry,
                currentSpaceIDs: Set(geometry.keys),
                ax: axIndex(pids: currentSpacePIDs, appByPID: appByPID),
                ownPID: ProcessInfo.processInfo.processIdentifier)
        }
    }

    /// Turns one CGWindowList entry into a switchable window, or nil if it is
    /// chrome, a background tab, a hidden helper, or filtered out by preferences.
    private static func classify(_ entry: [String: Any], context: Context,
                                 preferences: Preferences) -> WindowInfo? {
        guard let layer = entry[kCGWindowLayer as String] as? Int, layer == 0,
              let id = entry[kCGWindowNumber as String] as? CGWindowID,
              let pid = entry[kCGWindowOwnerPID as String] as? pid_t,
              pid != context.ownPID, context.regularPIDs.contains(pid),
              let boundsDict = entry[kCGWindowBounds as String] as? [String: CGFloat],
              let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else {
            return nil
        }

        let axEntry = context.ax[id]
        let onScreen = context.currentSpaceIDs.contains(id)
        let minimized = axEntry?.minimized ?? false
        let hidden = axEntry?.appHidden ?? context.hiddenPIDs.contains(pid)

        if axEntry == nil {
            // AX fully covers the current Space, so a current-Space window it
            // omits is chrome; off-Space windows just aren't in AX at all.
            if !context.ax.isEmpty && onScreen { return nil }
            if bounds.height < minChromeStripHeight { return nil }
        } else if !onScreen && !minimized && !hidden {
            // A current-Space standard window that is not on screen is a
            // background native tab; collapse it.
            return nil
        }

        if minimized && !preferences.showMinimizedWindows { return nil }
        if hidden && !preferences.showHiddenApps { return nil }

        let app = context.appByPID[pid]
        let appName = axEntry?.appName ?? app?.localizedName
            ?? entry[kCGWindowOwnerName as String] as? String ?? "Unknown"
        // A window with no real title that AX doesn't expose as a standard
        // window is a hidden helper window (fixed 500×500 placeholder, etc.).
        let realTitle = nonEmpty(axEntry?.title) ?? nonEmpty(entry[kCGWindowName as String] as? String)
        if realTitle == nil && axEntry == nil { return nil }

        return WindowInfo(id: id, pid: pid, title: realTitle ?? appName, appName: appName,
                          icon: axEntry?.icon ?? app?.icon, bounds: bounds,
                          isMinimized: minimized, isHidden: hidden,
                          windowCount: 1, axElement: axEntry?.element)
    }

    // Folds windows that the user cannot tell apart, keeping the first (front /
    // current-Space) occurrence. Two signals, both scoped per app:
    //  - same title  → the same logical window seen twice (e.g. a full-screen
    //    window and its off-Space CG twin), or windows with identical content.
    //  - same frame  → members of a native tab group (stacked, so identical
    //    frames) that AX can't disambiguate off-Space.
    // Minimized windows are exempt (degenerate/identical frames and titles).
    static func collapseDuplicates(_ windows: [WindowInfo]) -> [WindowInfo] {
        var seenTitle = Set<String>()
        var seenFrame = Set<String>()
        return windows.filter { window in
            guard !window.isMinimized else { return true }
            let titleKey = "\(window.pid)\u{1}\(window.title)"
            let frameKey = "\(window.pid):\(Int(window.bounds.minX)):\(Int(window.bounds.minY))"
                + ":\(Int(window.bounds.width)):\(Int(window.bounds.height))"
            let duplicateTitle = !seenTitle.insert(titleKey).inserted
            let duplicateFrame = !seenFrame.insert(frameKey).inserted
            return !(duplicateTitle || duplicateFrame)
        }
    }

    static func focus(_ window: WindowInfo) {
        MRUTracker.shared.promote(window.id)
        let app = NSRunningApplication(processIdentifier: window.pid)
        if window.isHidden { app?.unhide() }

        if let axWindow = window.axElement {
            app?.activate()
            raise(axWindow)
            return
        }

        // Off-Space: activate through LaunchServices (like the Dock / Cmd+Tab),
        // which switches to the app's Space — full-screen included. Raise the
        // exact window only in the completion handler, i.e. AFTER the switch has
        // been driven; raising during the transition makes it flaky.
        guard let url = app?.bundleURL else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        let pid = window.pid
        let id = window.id
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + activationRaiseDelay) {
                // Setting the app frontmost via AX after activation commits the
                // Space transition for full-screen apps, which LaunchServices
                // activation alone leaves in the menu bar without switching.
                AXUIElementSetAttributeValue(AXUIElementCreateApplication(pid),
                                             kAXFrontmostAttribute as CFString, kCFBooleanTrue)
                raiseWhenReachable(pid: pid, id: id)
            }
        }
    }

    private static let maxRaiseRetries = 8
    private static let raiseRetryDelay: TimeInterval = 0.05
    // Give LaunchServices time to drive the Space switch before committing it
    // via AX frontmost (needed for full-screen apps).
    private static let activationRaiseDelay: TimeInterval = 0.12

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
        AX.windows(of: AX.app(pid, timeout: axTimeout))?.first { AX.windowID(of: $0) == id }
    }

    private static func raise(_ axWindow: AXUIElement) {
        AXUIElementSetAttributeValue(axWindow, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        AXUIElementSetAttributeValue(axWindow, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
    }

    // MARK: - Actions on a highlighted window

    static func close(_ window: WindowInfo) {
        guard let axWindow = window.axElement else { return }
        var button: CFTypeRef?
        if AXUIElementCopyAttributeValue(axWindow, kAXCloseButtonAttribute as CFString, &button) == .success,
           let button {
            AXUIElementPerformAction((button as! AXUIElement), kAXPressAction as CFString)
        }
    }

    static func minimize(_ window: WindowInfo) {
        guard let axWindow = window.axElement else { return }
        AXUIElementSetAttributeValue(axWindow, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
    }

    static func hide(_ window: WindowInfo) {
        NSRunningApplication(processIdentifier: window.pid)?.hide()
    }

    static func quit(_ window: WindowInfo) {
        NSRunningApplication(processIdentifier: window.pid)?.terminate()
    }

    // MARK: - AX window index (real titles + per-window element)

    // Only the apps that own a current-Space window need AX: their standard
    // windows drive tab collapsing and precise raising. Off-Space titles come
    // from CGWindowList, so enumerating every app would just add latency.
    private static func axIndex(pids: Set<pid_t>, appByPID: [pid_t: NSRunningApplication]) -> [CGWindowID: AXEntry] {
        var index: [CGWindowID: AXEntry] = [:]

        for pid in pids {
            guard let app = appByPID[pid] else { continue }
            let appElement = AX.app(pid, timeout: axTimeout)
            guard let axWindows = AX.windows(of: appElement) else { continue }

            let appName = app.localizedName ?? "Unknown"
            for axWindow in axWindows {
                guard let id = AX.windowID(of: axWindow), AX.isStandardWindow(axWindow) else { continue }
                index[id] = AXEntry(element: axWindow,
                                    title: AX.string(axWindow, kAXTitleAttribute),
                                    minimized: AX.bool(axWindow, kAXMinimizedAttribute),
                                    appHidden: app.isHidden, appName: appName, icon: app.icon)
            }
        }
        return index
    }

    // MARK: - Current-Space geometry (bounds + front-to-back order + owner pids)

    private static func currentSpaceInfo() -> (geometry: [CGWindowID: (bounds: CGRect, order: Int)], pids: Set<pid_t>) {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return ([:], [])
        }

        var map: [CGWindowID: (bounds: CGRect, order: Int)] = [:]
        var pids = Set<pid_t>()
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
            if let pid = entry[kCGWindowOwnerPID as String] as? pid_t { pids.insert(pid) }
        }
        return (map, pids)
    }

    private static func nonEmpty(_ text: String?) -> String? {
        guard let text, !text.isEmpty else { return nil }
        return text
    }

    // MARK: - Scope filtering

    private static func applyScope(_ scope: WindowScope, to windows: [WindowInfo]) -> [WindowInfo] {
        guard scope == .activeScreen, let screenRect = ActiveScreen.rectInCGSpace() else {
            return windows
        }
        return windows.filter { $0.bounds.intersects(screenRect) }
    }
}
