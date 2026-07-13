// Sources/OpenTab/SwitcherController.swift
import Cocoa

final class SwitcherController {
    private var panel: SwitcherPanel?
    private var windows: [WindowInfo] = []
    private var selectedIndex = 0
    private var isActive = false

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

        if windows.indices.contains(selectedIndex) {
            WindowManager.focus(windows[selectedIndex])
        }
        panel?.orderOut(nil)
    }

    private func beginSession() {
        let prefs = PreferencesStore.shared.preferences
        windows = WindowManager.listWindows(scope: prefs.scope)
        selectedIndex = windows.count > 1 ? 1 : 0
        isActive = true

        let panel = panel ?? makePanel()
        panel.present(windows: windows, layout: prefs.layout)
        panel.highlight(index: selectedIndex)
    }

    private func makePanel() -> SwitcherPanel {
        let panel = SwitcherPanel()
        self.panel = panel
        return panel
    }
}
