// Sources/OpenTab/SwitcherController.swift
import Cocoa

final class SwitcherController {
    private var panel: SwitcherPanel?
    private var windows: [WindowInfo] = []
    private var selectedIndex = 0
    private var isActive = false
    private var triggerFlags: NSEvent.ModifierFlags = []
    private var releaseTimer: Timer?

    private static let releasePollInterval: TimeInterval = 0.045

    func advance(reverse: Bool) {
        if !isActive { beginSession() }
        guard !windows.isEmpty else { return }

        let step = reverse ? -1 : 1
        selectedIndex = (selectedIndex + step + windows.count) % windows.count
        panel?.highlight(index: selectedIndex)
    }

    func commit() {
        guard isActive else { return }
        isActive = false
        stopReleaseWatch()

        if windows.indices.contains(selectedIndex) {
            WindowManager.focus(windows[selectedIndex])
        }
        panel?.orderOut(nil)
    }

    private func beginSession() {
        let prefs = PreferencesStore.shared.preferences
        let listed = WindowManager.listWindows(preferences: prefs)
        windows = prefs.layout == .appOnly ? collapseByApp(listed) : listed
        selectedIndex = windows.count > 1 ? 1 : 0
        triggerFlags = ShortcutFormatting.appKitModifiers(from: prefs.triggerModifiers)
        isActive = true

        let panel = panel ?? makePanel()
        panel.present(windows: windows, layout: prefs.layout, density: prefs.density)
        panel.highlight(index: selectedIndex)
        startReleaseWatch()
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

    private func startReleaseWatch() {
        stopReleaseWatch()
        let timer = Timer(timeInterval: Self.releasePollInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            let current = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if current.intersection(self.triggerFlags) != self.triggerFlags {
                self.commit()
            }
        }
        RunLoop.current.add(timer, forMode: .common)
        releaseTimer = timer
    }

    private func stopReleaseWatch() {
        releaseTimer?.invalidate()
        releaseTimer = nil
    }
}
