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
        VStack(spacing: 0) {
            permissionStatus
            Divider()
            TabView {
                appearanceTab
                    .tabItem { Label("Appearance", systemImage: "square.grid.2x2") }
                shortcutTab
                    .tabItem { Label("Shortcut", systemImage: "keyboard") }
            }
            .frame(height: 320)
        }
        .frame(width: 460)
        .onReceive(ticker) { _ in
            accessibility = AXIsProcessTrusted()
            screenRecording = CGPreflightScreenCaptureAccess()
        }
    }

    private var permissionStatus: some View {
        VStack(spacing: 6) {
            permissionRow("Accessibility", granted: accessibility,
                          hint: "Required to switch windows and read titles.",
                          open: openAccessibilitySettings)
            permissionRow("Screen Recording", granted: screenRecording,
                          hint: "Shows window titles for other Spaces.",
                          open: openScreenRecordingSettings)
        }
        .padding(12)
    }

    private func permissionRow(_ name: String, granted: Bool, hint: String,
                               open: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(granted ? .green : .red)
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(.system(size: 12, weight: .medium))
                Text(granted ? "Granted" : hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !granted { Button("Open", action: open) }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background((granted ? Color.green : Color.red).opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8))
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
