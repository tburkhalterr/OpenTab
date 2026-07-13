// Sources/OpenTab/SwitcherController.swift
import Cocoa

/// Owns the switcher session: builds the window list on first invocation,
/// tracks the highlighted entry while the trigger key is held, and commits
/// (raises the selected window) when the modifier is released.
final class SwitcherController {
    private var preferences = Preferences.load()
    private var panel: SwitcherPanel?
    private var windows: [WindowInfo] = []
    private var selectedIndex = 0
    private var isActive = false

    func advance(reverse: Bool) {
        if !isActive {
            beginSession()
        }
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

    // MARK: - Session lifecycle

    private func beginSession() {
        windows = filtered(WindowManager.listWindows())
        // Start highlighting the second window, matching the "switch to previous" default.
        selectedIndex = windows.count > 1 ? 1 : 0
        isActive = true

        let panel = panel ?? makePanel()
        panel.present(windows: windows, layout: preferences.layout)
        panel.highlight(index: selectedIndex)
    }

    private func makePanel() -> SwitcherPanel {
        let panel = SwitcherPanel()
        self.panel = panel
        return panel
    }

    private func filtered(_ windows: [WindowInfo]) -> [WindowInfo] {
        // Scope/visibility filters are applied here; extend as WindowScope grows.
        switch preferences.scope {
        case .allScreens:
            return windows
        case .activeScreen, .activeSpace:
            // CGWindowList already excludes off-space windows for onScreenOnly;
            // per-screen filtering is a planned refinement.
            return windows
        }
    }
}
