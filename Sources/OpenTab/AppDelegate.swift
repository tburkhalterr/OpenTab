// Sources/OpenTab/AppDelegate.swift
import Cocoa
import Carbon.HIToolbox

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let hotKeyManager = HotKeyManager()
    private let switcher = SwitcherController()
    private var flagsMonitor: Any?
    private var statusItem: NSStatusItem?

    private static let triggerModifier: NSEvent.ModifierFlags = .option

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard ensureAccessibilityPermission() else {
            // The system prompt has been shown; the user must grant access and relaunch.
            NSApp.terminate(nil)
            return
        }
        setupStatusItem()
        setupHotKeys()
        setupModifierReleaseMonitor()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let flagsMonitor { NSEvent.removeMonitor(flagsMonitor) }
        hotKeyManager.unregisterAll()
    }

    // MARK: - Permissions

    private func ensureAccessibilityPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    // MARK: - Setup

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "⇥"
        let menu = NSMenu()
        menu.addItem(withTitle: "OpenTab", action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit OpenTab", action: #selector(NSApp.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    private func setupHotKeys() {
        // Option+Tab -> next window, Option+Shift+Tab -> previous window.
        hotKeyManager.register(keyCode: UInt32(kVK_Tab), modifiers: UInt32(optionKey)) { [weak self] in
            self?.switcher.advance(reverse: false)
        }
        hotKeyManager.register(keyCode: UInt32(kVK_Tab), modifiers: UInt32(optionKey | shiftKey)) { [weak self] in
            self?.switcher.advance(reverse: true)
        }
    }

    private func setupModifierReleaseMonitor() {
        flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self else { return }
            let optionHeld = event.modifierFlags.contains(Self.triggerModifier)
            if !optionHeld {
                self.switcher.commit()
            }
        }
    }
}
