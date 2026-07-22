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

    /// Main-thread-affine inputs captured once so the heavy CGWindowList/AX/Spaces
    /// enumeration can run off the main thread without touching AppKit objects
    /// (`NSRunningApplication`, `NSScreen`, `MRUTracker`) that require it.
    struct AppSnapshot {
        let name: String
        let isHidden: Bool
        let icon: NSImage?
    }

    struct Environment {
        let apps: [pid_t: AppSnapshot]
        let mruOrder: [CGWindowID]
        let activeScreenRect: CGRect?
        let ownPID: pid_t

        // Must run on the main thread.
        static func capture(preferences: Preferences) -> Environment {
            let running = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
            let apps = Dictionary(running.map {
                ($0.processIdentifier, AppSnapshot(name: $0.localizedName ?? "Unknown",
                                                   isHidden: $0.isHidden, icon: $0.icon))
            }, uniquingKeysWith: { first, _ in first })
            return Environment(
                apps: apps,
                mruOrder: MRUTracker.shared.snapshot(),
                activeScreenRect: preferences.scope == .activeScreen ? ActiveScreen.rectInCGSpace() : nil,
                ownPID: ProcessInfo.processInfo.processIdentifier)
        }
    }

    /// The window universe comes from CGWindowList in `optionAll` mode, which
    /// spans every Space (unlike AX, which only reports the current Space).
    /// AX then enriches current-Space windows with real titles and per-window
    /// elements; off-Space windows fall back to their CG name / app name.
    static func listWindows(preferences: Preferences) -> [WindowInfo] {
        listWindows(preferences: preferences, environment: .capture(preferences: preferences))
    }

    /// Captures main-thread state, then runs the AX/CGWindowList enumeration on a
    /// background queue so a hung app's AX timeouts never block the run loop.
    /// `completion` is delivered on the main thread.
    static func listWindowsAsync(preferences: Preferences, completion: @escaping ([WindowInfo]) -> Void) {
        let environment = Environment.capture(preferences: preferences)
        DispatchQueue.global(qos: .userInitiated).async {
            let windows = listWindows(preferences: preferences, environment: environment)
            DispatchQueue.main.async { completion(windows) }
        }
    }

    private static func listWindows(preferences: Preferences, environment: Environment) -> [WindowInfo] {
        let context = Context.build(environment: environment)
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

        let live = withoutStaleWindows(windows, currentSpaceIDs: context.currentSpaceIDs,
                                       onAnySpace: WindowSpaces.onAnySpace)
        let ordered = live.sorted { lhs, rhs in
            let l = context.geometry[lhs.id]?.order ?? Int.max
            let r = context.geometry[rhs.id]?.order ?? Int.max
            if l != r { return l < r }
            return (lhs.appName, lhs.title) < (rhs.appName, rhs.title)
        }
        let ranked = sorted(collapseDuplicates(ordered), by: preferences.sortOrder, mruOrder: environment.mruOrder)
        return applyScope(preferences.scope, rect: environment.activeScreenRect, to: ranked)
    }

    // Order the collapsed window list per the user's preference. `.recent` keeps
    // the MRU ranking; the others are stable string sorts on app name / title.
    static func sorted(_ windows: [WindowInfo], by order: SortOrder, mruOrder: [CGWindowID]) -> [WindowInfo] {
        switch order {
        case .recent:
            return MRUTracker.ordered(windows, byMRU: mruOrder)
        case .alphabetical:
            return windows.sorted { ($0.title.lowercased(), $0.appName.lowercased())
                                  < ($1.title.lowercased(), $1.appName.lowercased()) }
        case .byApp:
            return windows.sorted { ($0.appName.lowercased(), $0.title.lowercased())
                                  < ($1.appName.lowercased(), $1.title.lowercased()) }
        }
    }

    // Off-Space, non-minimized windows that resolve to no Space are phantoms the
    // window server still lists after their app closed them (browsers retain
    // these). On-screen and minimized windows are never suspect.
    static func withoutStaleWindows(_ windows: [WindowInfo], currentSpaceIDs: Set<CGWindowID>,
                                    onAnySpace: ([CGWindowID]) -> Set<CGWindowID>) -> [WindowInfo] {
        let suspect = windows.filter { !$0.isMinimized && !currentSpaceIDs.contains($0.id) }.map(\.id)
        guard !suspect.isEmpty else { return windows }
        let dead = Set(suspect).subtracting(onAnySpace(suspect))
        guard !dead.isEmpty else { return windows }
        return windows.filter { !dead.contains($0.id) }
    }

    /// Everything the per-window classification needs, gathered once per invocation.
    private struct Context {
        let regularPIDs: Set<pid_t>
        let hiddenPIDs: Set<pid_t>
        let apps: [pid_t: AppSnapshot]
        let geometry: [CGWindowID: (bounds: CGRect, order: Int)]
        let currentSpaceIDs: Set<CGWindowID>
        let ax: [CGWindowID: AXEntry]
        let ownPID: pid_t

        static func build(environment: Environment) -> Context {
            let apps = environment.apps
            let (geometry, currentSpacePIDs) = currentSpaceInfo()
            return Context(
                regularPIDs: Set(apps.keys),
                hiddenPIDs: Set(apps.filter { $0.value.isHidden }.map(\.key)),
                apps: apps,
                geometry: geometry,
                currentSpaceIDs: Set(geometry.keys),
                ax: axIndex(pids: currentSpacePIDs, apps: apps),
                ownPID: environment.ownPID)
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

        let app = context.apps[pid]
        let appName = axEntry?.appName ?? app?.name
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
           let button, CFGetTypeID(button) == AXUIElementGetTypeID() {
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

    /// Fuzzy (subsequence) match on window title + app name, ranked best-first;
    /// empty query keeps everything in its original order.
    static func filter(_ windows: [WindowInfo], query: String) -> [WindowInfo] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return windows }
        let scored = windows.enumerated().compactMap { offset, window -> (window: WindowInfo, score: Int, offset: Int)? in
            guard let score = FuzzyMatch.score("\(window.title) \(window.appName)".lowercased(), query: q) else { return nil }
            return (window, score, offset)
        }
        return scored.sorted { $0.score != $1.score ? $0.score > $1.score : $0.offset < $1.offset }.map(\.window)
    }

    // MARK: - AX window index (real titles + per-window element)

    // Only the apps that own a current-Space window need AX: their standard
    // windows drive tab collapsing and precise raising. Off-Space titles come
    // from CGWindowList, so enumerating every app would just add latency.
    private static func axIndex(pids: Set<pid_t>, apps: [pid_t: AppSnapshot]) -> [CGWindowID: AXEntry] {
        var index: [CGWindowID: AXEntry] = [:]

        for pid in pids {
            guard let app = apps[pid] else { continue }
            let appElement = AX.app(pid, timeout: axTimeout)
            guard let axWindows = AX.windows(of: appElement) else { continue }

            let appName = app.name
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

    private static func applyScope(_ scope: WindowScope, rect: CGRect?, to windows: [WindowInfo]) -> [WindowInfo] {
        guard scope == .activeScreen, let rect else { return windows }
        return self.windows(windows, intersecting: rect)
    }

    static func windows(_ windows: [WindowInfo], intersecting rect: CGRect) -> [WindowInfo] {
        windows.filter { $0.bounds.intersects(rect) }
    }
}
