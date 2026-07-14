// Sources/OpenTab/AppDelegate.swift
import Cocoa
import Carbon.HIToolbox

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let hotKeyManager = HotKeyManager()
    private let switcher = SwitcherController()
    private let settingsWindow = SettingsWindowController()
    private var statusItem: NSStatusItem?
    private var registeredShortcut: (keyCode: UInt32, modifiers: UInt32, reverse: Bool)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        requestAccessibilityPermission()
        requestScreenRecordingPermission()
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

    // Window titles on other Spaces are only available from CGWindowList with
    // Screen Recording permission; AX alone covers just the current Space.
    private func requestScreenRecordingPermission() {
        if !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
        }
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            let image = NSImage(named: "MenubarIcon") ?? NSImage(systemSymbolName: "rectangle.stack", accessibilityDescription: "OpenTab")
            image?.isTemplate = true
            image?.size = NSSize(width: 18, height: 18)
            button.image = image
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
        let shortcut = (prefs.triggerKeyCode, prefs.triggerModifiers, prefs.reverseAddsShift)
        // PreferencesStore.didChange fires for any setting; only touch the Carbon
        // registration when the shortcut itself actually changed.
        guard registeredShortcut.map({ $0 != shortcut }) ?? true else { return }
        registeredShortcut = shortcut

        hotKeyManager.unregisterAll()

        hotKeyManager.register(keyCode: prefs.triggerKeyCode, modifiers: prefs.triggerModifiers) { [weak self] in
            self?.switcher.begin(reverse: false)
        }
        if prefs.reverseAddsShift {
            hotKeyManager.register(keyCode: prefs.triggerKeyCode,
                                   modifiers: prefs.triggerModifiers | UInt32(shiftKey)) { [weak self] in
                self?.switcher.begin(reverse: true)
            }
        }
    }
}
