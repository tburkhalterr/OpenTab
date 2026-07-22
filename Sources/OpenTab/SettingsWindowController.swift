// Sources/OpenTab/SettingsWindowController.swift
import Cocoa
import SwiftUI

final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hosting = NSHostingController(rootView: SettingsView())
        let window = NSWindow(contentViewController: hosting)
        window.title = "OpenTab Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setContentSize(hosting.view.fittingSize)
        centerOnActiveScreen(window)
        self.window = window

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // Release the hosting controller on close so the SwiftUI view graph — and its
    // permission-poll timer — tears down instead of firing for the app's lifetime.
    func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in self?.window = nil }
    }

    private func centerOnActiveScreen(_ window: NSWindow) {
        guard let screen = NSScreen.main else {
            window.center()
            return
        }
        let visible = screen.visibleFrame
        let size = window.frame.size
        let origin = NSPoint(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2)
        window.setFrameOrigin(origin)
    }
}
