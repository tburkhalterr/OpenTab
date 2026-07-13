// Sources/OpenTab/AppDelegate.swift
import Cocoa
import Carbon.HIToolbox

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let hotKeyManager = HotKeyManager()
    private let switcher = SwitcherController()
    private let settingsWindow = SettingsWindowController()
    private var flagsMonitor: Any?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard ensureAccessibilityPermission() else {
            NSApp.terminate(nil)
            return
        }
        setupStatusItem()
        reloadHotKeys()
        setupModifierReleaseMonitor()

        NotificationCenter.default.addObserver(
            self, selector: #selector(reloadHotKeys),
            name: PreferencesStore.didChange, object: nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let flagsMonitor { NSEvent.removeMonitor(flagsMonitor) }
        hotKeyManager.unregisterAll()
        NotificationCenter.default.removeObserver(self)
    }

    private func ensureAccessibilityPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "⇥"

        let menu = NSMenu()
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
            .target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit OpenTab", action: #selector(NSApp.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    @objc private func openSettings() {
        settingsWindow.show()
    }

    @objc private func reloadHotKeys() {
        let prefs = PreferencesStore.shared.preferences
        hotKeyManager.unregisterAll()

        hotKeyManager.register(keyCode: prefs.triggerKeyCode, modifiers: prefs.triggerModifiers) { [weak self] in
            self?.switcher.advance(reverse: false)
        }
        if prefs.reverseAddsShift {
            hotKeyManager.register(keyCode: prefs.triggerKeyCode,
                                   modifiers: prefs.triggerModifiers | UInt32(shiftKey)) { [weak self] in
                self?.switcher.advance(reverse: true)
            }
        }
    }

    private func setupModifierReleaseMonitor() {
        flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self else { return }
            let triggerFlags = Self.appKitFlags(from: PreferencesStore.shared.preferences.triggerModifiers)
            if event.modifierFlags.intersection(triggerFlags) != triggerFlags {
                self.switcher.commit()
            }
        }
    }

    private static func appKitFlags(from carbonMask: UInt32) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if carbonMask & UInt32(controlKey) != 0 { flags.insert(.control) }
        if carbonMask & UInt32(optionKey)  != 0 { flags.insert(.option) }
        if carbonMask & UInt32(shiftKey)   != 0 { flags.insert(.shift) }
        if carbonMask & UInt32(cmdKey)     != 0 { flags.insert(.command) }
        return flags
    }
}
