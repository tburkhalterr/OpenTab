// Sources/OpenTab/SwitcherController.swift
import Cocoa

final class SwitcherController {
    private var panel: SwitcherPanel?
    private var windows: [WindowInfo] = []
    private var selectedIndex = 0
    private var isActive = false
    private var triggerFlags: NSEvent.ModifierFlags = []
    private var triggerKeyCode: CGKeyCode = 0
    private var pollTimer: Timer?
    private var escapeMonitor: Any?
    private var keyWasDown = false
    private var lastAdvance: TimeInterval = 0

    private static let pollInterval: TimeInterval = 0.03
    private static let repeatDelay: TimeInterval = 0.13
    private static let escapeKeyCode: UInt16 = 53

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
        let listed = WindowManager.listWindows(preferences: prefs)
        windows = prefs.layout == .appOnly ? collapseByApp(listed) : listed
        selectedIndex = initialIndex(reverse: reverse)
        triggerFlags = ShortcutFormatting.appKitModifiers(from: prefs.triggerModifiers)
        triggerKeyCode = CGKeyCode(prefs.triggerKeyCode)
        keyWasDown = true
        lastAdvance = ProcessInfo.processInfo.systemUptime
        isActive = true

        let panel = panel ?? makePanel()
        panel.present(windows: windows, layout: prefs.layout, density: prefs.density)
        panel.highlight(index: selectedIndex)
        startPoll()
        startEscapeWatch()
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
        stopEscapeWatch()
        panel?.orderOut(nil)
    }

    private func collapseByApp(_ windows: [WindowInfo]) -> [WindowInfo] {
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
        self.panel = panel
        return panel
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
        let reverse = flags.contains(.shift)
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

    private func stopPoll() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func startEscapeWatch() {
        stopEscapeWatch()
        escapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == SwitcherController.escapeKeyCode { self?.cancel() }
        }
    }

    private func stopEscapeWatch() {
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        escapeMonitor = nil
    }
}
