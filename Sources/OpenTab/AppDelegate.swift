// Sources/OpenTab/AppDelegate.swift
import Cocoa
import Carbon.HIToolbox

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let hotKeyManager = HotKeyManager()
    private let switcher = SwitcherController()
    private let settingsWindow = SettingsWindowController()
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        requestAccessibilityPermission()
        MRUTracker.shared.start()
        setupStatusItem()
        reloadHotKeys()

        NotificationCenter.default.addObserver(
            self, selector: #selector(reloadHotKeys),
            name: PreferencesStore.didChange, object: nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeyManager.unregisterAll()
        NotificationCenter.default.removeObserver(self)
    }

    @discardableResult
    private func requestAccessibilityPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
            button.image = NSImage(systemSymbolName: "rectangle.stack",
                                   accessibilityDescription: "OpenTab")?
                .withSymbolConfiguration(config)
            button.image?.isTemplate = true
        }

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

}
