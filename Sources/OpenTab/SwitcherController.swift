// Sources/OpenTab/SwitcherController.swift
import Cocoa
import Carbon.HIToolbox

final class SwitcherController {
    private var panel: SwitcherPanel?
    private var windows: [WindowInfo] = []
    private var selectedIndex = 0
    private var isActive = false
    private var triggerFlags: NSEvent.ModifierFlags = []
    private var triggerKeyCode: CGKeyCode = 0
    private var reverseWithShift = true
    private var pollTimer: Timer?
    private var eventTap: CFMachPort?
    private var eventTapSource: CFRunLoopSource?
    private var keyWasDown = false
    private var lastAdvance: TimeInterval = 0
    private var hoverEnabled = false
    private var allWindows: [WindowInfo] = []
    private var cachedWindows: [WindowInfo] = []
    private var query = ""
    private var layout: SwitcherLayout = .appGrid
    private var density: SwitcherDensity = .normal
    private var thumbnails = true

    private static let pollInterval: TimeInterval = 0.03
    private static let repeatDelay: TimeInterval = 0.13
    private static let hoverGrace: TimeInterval = 0.25
    private static let escapeKeyCode = CGKeyCode(kVK_Escape)
    private static let deleteKeyCode = CGKeyCode(kVK_Delete)
    private static let refreshDelay: TimeInterval = 0.15
    private static let arrowKeys: [(code: CGKeyCode, reverse: Bool)] = [
        (CGKeyCode(kVK_LeftArrow), true), (CGKeyCode(kVK_UpArrow), true),
        (CGKeyCode(kVK_RightArrow), false), (CGKeyCode(kVK_DownArrow), false)
    ]
    private static let actionKeys: [(code: CGKeyCode, perform: (WindowInfo) -> Void)] = [
        (CGKeyCode(kVK_ANSI_W), WindowManager.close),
        (CGKeyCode(kVK_ANSI_M), WindowManager.minimize),
        (CGKeyCode(kVK_ANSI_H), WindowManager.hide),
        (CGKeyCode(kVK_ANSI_Q), WindowManager.quit)
    ]

    // Carbon fires only on the initial press; holding the key auto-advances via
    // key-state polling below, so the hot key just starts the session.
    func begin(reverse: Bool) {
        if isActive { return }
        beginSession(reverse: reverse)
    }

    func commit() {
        guard isActive else { return }
        let target = windows.indices.contains(selectedIndex) ? windows[selectedIndex] : nil
        endSession()
        // Focus on the next runloop tick so the panel is fully gone first;
        // activating while it is still ordering out makes the Space switch flaky.
        if let target {
            DispatchQueue.main.async { WindowManager.focus(target) }
        }
    }

    func cancel() {
        guard isActive else { return }
        endSession()
    }

    // MARK: - Session lifecycle

    private func beginSession(reverse: Bool) {
        let prefs = PreferencesStore.shared.preferences
        layout = prefs.layout
        density = prefs.density
        thumbnails = prefs.showThumbnails
        query = ""
        // Show the HUD instantly from the previous list, then refresh; the first
        // press ever (empty cache) builds synchronously.
        let usingCache = !cachedWindows.isEmpty
        allWindows = usingCache ? cachedWindows : buildWindows(prefs)
        cachedWindows = allWindows
        windows = allWindows
        selectedIndex = initialIndex(reverse: reverse)
        triggerFlags = ShortcutFormatting.appKitModifiers(from: prefs.triggerModifiers)
        triggerKeyCode = CGKeyCode(prefs.triggerKeyCode)
        reverseWithShift = prefs.reverseAddsShift
        keyWasDown = true
        lastAdvance = ProcessInfo.processInfo.systemUptime
        isActive = true
        // Ignore hover until the pointer actually moves, so the cell under the
        // cursor when the HUD appears doesn't hijack the initial selection.
        hoverEnabled = false

        let panel = panel ?? makePanel()
        panel.present(windows: windows, layout: layout, density: density, thumbnails: thumbnails)
        panel.highlight(index: selectedIndex)
        startPoll()
        startEventTap()
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.hoverGrace) { [weak self] in
            self?.hoverEnabled = true
        }
        if usingCache {
            DispatchQueue.main.async { [weak self] in self?.refreshFromSource(reverse: reverse) }
        }
    }

    private func buildWindows(_ prefs: Preferences) -> [WindowInfo] {
        let listed = WindowManager.listWindows(preferences: prefs)
        return prefs.layout == .appOnly ? Self.collapseByApp(listed) : listed
    }

    // Rebuild the list from the window server and reconcile the shown selection;
    // skips re-presenting when nothing changed to avoid flicker.
    private func refreshFromSource(reverse: Bool) {
        guard isActive else { return }
        let fresh = buildWindows(PreferencesStore.shared.preferences)
        cachedWindows = fresh
        guard fresh.map(\.id) != allWindows.map(\.id) else { return }

        let selectedID = windows.indices.contains(selectedIndex) ? windows[selectedIndex].id : nil
        allWindows = fresh
        windows = WindowManager.filter(allWindows, query: query)
        guard !windows.isEmpty else { cancel(); return }
        if let selectedID, let index = windows.firstIndex(where: { $0.id == selectedID }) {
            selectedIndex = index
        } else {
            selectedIndex = initialIndex(reverse: reverse)
        }
        panel?.present(windows: windows, layout: layout, density: density, thumbnails: thumbnails)
        panel?.setQuery(query)
        panel?.highlight(index: selectedIndex)
    }

    private func initialIndex(reverse: Bool) -> Int {
        guard windows.count > 1 else { return 0 }
        return reverse ? windows.count - 1 : 1
    }

    private func advance(reverse: Bool) {
        guard isActive, !windows.isEmpty else { return }
        let step = reverse ? -1 : 1
        selectedIndex = (selectedIndex + step + windows.count) % windows.count
        panel?.highlight(index: selectedIndex)
    }

    private func endSession() {
        isActive = false
        stopPoll()
        stopEventTap()
        panel?.orderOut(nil)
    }

    static func collapseByApp(_ windows: [WindowInfo]) -> [WindowInfo] {
        let counts = Dictionary(grouping: windows, by: \.pid).mapValues(\.count)
        var seen = Set<pid_t>()
        return windows.compactMap { window in
            guard seen.insert(window.pid).inserted else { return nil }
            return WindowInfo(id: window.id, pid: window.pid, title: window.appName,
                              appName: window.appName, icon: window.icon, bounds: window.bounds,
                              isMinimized: window.isMinimized, isHidden: window.isHidden,
                              windowCount: counts[window.pid] ?? 1, axElement: window.axElement)
        }
    }

    private func makePanel() -> SwitcherPanel {
        let panel = SwitcherPanel()
        panel.onHover = { [weak self] index in self?.hover(index) }
        panel.onSelect = { [weak self] index in self?.select(index) }
        self.panel = panel
        return panel
    }

    private func hover(_ index: Int) {
        guard isActive, hoverEnabled, windows.indices.contains(index) else { return }
        selectedIndex = index
        panel?.highlight(index: index)
    }

    private func select(_ index: Int) {
        guard isActive, windows.indices.contains(index) else { return }
        selectedIndex = index
        commit()
    }

    // MARK: - Key-state polling (commit on modifier release, advance on key hold)

    private func startPoll() {
        stopPoll()
        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            self?.poll()
        }
        RunLoop.current.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func poll() {
        let flags = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.intersection(triggerFlags) != triggerFlags {
            commit()
            return
        }

        let keyDown = CGEventSource.keyState(.hidSystemState, key: triggerKeyCode)
        let reverse = reverseWithShift && flags.contains(.shift)
        let now = ProcessInfo.processInfo.systemUptime

        if keyDown && !keyWasDown {
            advance(reverse: reverse)
            lastAdvance = now
        } else if keyDown && keyWasDown && now - lastAdvance >= Self.repeatDelay {
            advance(reverse: reverse)
            lastAdvance = now
        }
        keyWasDown = keyDown
    }

    private func scheduleRefresh() {
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.refreshDelay) { [weak self] in
            self?.refreshWindows()
        }
    }

    private func refreshWindows() {
        guard isActive else { return }
        let prefs = PreferencesStore.shared.preferences
        allWindows = buildWindows(prefs)
        cachedWindows = allWindows
        windows = WindowManager.filter(allWindows, query: query)
        guard !windows.isEmpty else { cancel(); return }
        selectedIndex = min(selectedIndex, windows.count - 1)
        panel?.present(windows: windows, layout: layout, density: density, thumbnails: thumbnails)
        panel?.setQuery(query)
        panel?.highlight(index: selectedIndex)
    }

    private func stopPoll() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    // MARK: - Event tap (intercept & consume in-session keys so they don't leak
    // to the app underneath — arrows navigate, W/M/H/Q act, Esc cancels)

    private func startEventTap() {
        stopEventTap()
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, _, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                return Unmanaged<SwitcherController>.fromOpaque(refcon)
                    .takeUnretainedValue().handleTapKey(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            return
        }
        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        eventTapSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func handleTapKey(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        guard isActive else { return Unmanaged.passUnretained(event) }
        let code = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let command = event.flags.contains(.maskCommand)
        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0

        if code == Self.escapeKeyCode {
            if query.isEmpty { cancel() } else { updateQuery("") }
            return nil
        }
        if let arrow = Self.arrowKeys.first(where: { $0.code == code }) {
            advance(reverse: arrow.reverse)
            return nil
        }
        if code == Self.deleteKeyCode {
            if !query.isEmpty { updateQuery(String(query.dropLast())) }
            return nil
        }
        // Actions are ⌘-modified so plain letters stay free for type-to-filter.
        if command, !isRepeat, let action = Self.actionKeys.first(where: { $0.code == code }) {
            if windows.indices.contains(selectedIndex) {
                action.perform(windows[selectedIndex])
                scheduleRefresh()
            }
            return nil
        }
        if !command, let character = typedCharacter(event) {
            updateQuery(query + character)
            return nil
        }
        return Unmanaged.passUnretained(event)
    }

    private func typedCharacter(_ event: CGEvent) -> String? {
        guard let chars = NSEvent(cgEvent: event)?.charactersIgnoringModifiers,
              chars.count == 1, let scalar = chars.unicodeScalars.first,
              scalar.value >= 0x20, scalar.value != 0x7f, scalar.value < 0xF700 else {
            return nil
        }
        return chars
    }

    private func updateQuery(_ newQuery: String) {
        query = newQuery
        windows = WindowManager.filter(allWindows, query: query)
        selectedIndex = 0
        panel?.present(windows: windows, layout: layout, density: density, thumbnails: thumbnails)
        panel?.setQuery(query)
        panel?.highlight(index: selectedIndex)
    }

    private func stopEventTap() {
        if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: false) }
        if let eventTapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), eventTapSource, .commonModes) }
        eventTap = nil
        eventTapSource = nil
    }
}
