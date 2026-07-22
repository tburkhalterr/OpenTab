// Sources/OpenTab/AppDelegate.swift
import Cocoa
import Carbon.HIToolbox

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let hotKeyManager = HotKeyManager()
    private let switcher = SwitcherController()
    private let settingsWindow = SettingsWindowController()
    private var statusItem: NSStatusItem?
    private var registeredShortcut: (keyCode: UInt32, modifiers: UInt32, reverse: Bool)?
    private var permissionPoll: Timer?
    private var accessibilityStarted = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        requestScreenRecordingPermission()
        setupStatusItem()
        reloadHotKeys()

        NotificationCenter.default.addObserver(
            self, selector: #selector(reloadHotKeys),
            name: PreferencesStore.didChange, object: nil)

        if requestAccessibilityPermission() {
            startAccessibilityFeatures()
        } else {
            // Poll so the switcher lights up the moment permission is granted,
            // without forcing the user to relaunch.
            pollForAccessibility()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        permissionPoll?.invalidate()
        hotKeyManager.unregisterAll()
        NotificationCenter.default.removeObserver(self)
    }

    private func startAccessibilityFeatures() {
        guard !accessibilityStarted else { return }
        accessibilityStarted = true
        MRUTracker.shared.start()
        AppStatus.shared.axSymbolWorks = AX.symbolResolvesWindows()
        switcher.warmCache()
    }

    private func pollForAccessibility() {
        permissionPoll = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            guard AXIsProcessTrusted() else { return }
            timer.invalidate()
            self?.startAccessibilityFeatures()
        }
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

        let registered = hotKeyManager.register(keyCode: prefs.triggerKeyCode,
                                                modifiers: prefs.triggerModifiers) { [weak self] in
            self?.switcher.begin(reverse: false)
        }
        AppStatus.shared.hotKeyRegistered = registered

        if prefs.reverseAddsShift {
            hotKeyManager.register(keyCode: prefs.triggerKeyCode,
                                   modifiers: prefs.triggerModifiers | UInt32(shiftKey)) { [weak self] in
                self?.switcher.begin(reverse: true)
            }
        }
    }
}
