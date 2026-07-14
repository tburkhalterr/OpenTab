// Sources/OpenTab/SettingsView.swift
import SwiftUI
import AppKit
import ApplicationServices
import CoreGraphics

struct SettingsView: View {
    @ObservedObject private var store = PreferencesStore.shared
    @State private var accessibility = AXIsProcessTrusted()
    @State private var screenRecording = CGPreflightScreenCaptureAccess()

    private let ticker = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()
    private var prefs: Binding<Preferences> { $store.preferences }

    var body: some View {
        TabView {
            appearanceTab
                .tabItem { Label("Appearance", systemImage: "square.grid.2x2") }
            shortcutTab
                .tabItem { Label("Shortcut", systemImage: "keyboard") }
            systemTab
                .tabItem { Label("System", systemImage: "gearshape") }
        }
        .frame(width: 460, height: 340)
        .onReceive(ticker) { _ in
            accessibility = AXIsProcessTrusted()
            screenRecording = CGPreflightScreenCaptureAccess()
        }
    }

    private var systemTab: some View {
        Form {
            Section {
                permissionRow("Accessibility", granted: accessibility,
                              hint: "Required to switch windows and read window titles.",
                              open: openAccessibilitySettings)
                permissionRow("Screen Recording", granted: screenRecording,
                              hint: "Shows window titles for apps on other Spaces.",
                              open: openScreenRecordingSettings)
            } header: {
                Text("Permissions")
            } footer: {
                Text("Grant a permission, then relaunch OpenTab for it to take effect.")
            }
        }
        .formStyle(.grouped)
    }

    private func permissionRow(_ name: String, granted: Bool, hint: String,
                               open: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(granted ? .green : .orange)
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(.system(size: 12, weight: .medium))
                Text(granted ? "Granted" : hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !granted { Button("Open", action: open) }
        }
        .padding(.vertical, 2)
    }

    private var appearanceTab: some View {
        Form {
            Picker("View", selection: prefs.layout) {
                ForEach(SwitcherLayout.allCases) { Text($0.label).tag($0) }
            }
            Picker("Density", selection: prefs.density) {
                ForEach(SwitcherDensity.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            Picker("Include windows from", selection: prefs.scope) {
                ForEach(WindowScope.allCases) { Text($0.label).tag($0) }
            }
            Toggle("Show minimized windows", isOn: prefs.showMinimizedWindows)
            Toggle("Show hidden apps", isOn: prefs.showHiddenApps)
        }
        .formStyle(.grouped)
    }

    private var shortcutTab: some View {
        Form {
            LabeledContent("Cycle windows") {
                ShortcutRecorderButton(keyCode: prefs.triggerKeyCode,
                                       modifiers: prefs.triggerModifiers)
            }
            Toggle("Add Shift to cycle backwards", isOn: prefs.reverseAddsShift)
            Text("Hold the modifier and tap the key to move forward. Release to focus.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }

    private func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    private func openScreenRecordingSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
    }

    private func open(_ path: String) {
        if let url = URL(string: path) { NSWorkspace.shared.open(url) }
    }
}
