// Sources/OpenTab/SettingsView.swift
import SwiftUI

struct SettingsView: View {
    @ObservedObject private var store = PreferencesStore.shared

    private var prefs: Binding<Preferences> { $store.preferences }

    var body: some View {
        TabView {
            appearanceTab
                .tabItem { Label("Appearance", systemImage: "square.grid.2x2") }
            shortcutTab
                .tabItem { Label("Shortcut", systemImage: "keyboard") }
        }
        .frame(width: 460, height: 320)
    }

    private var appearanceTab: some View {
        Form {
            Picker("View", selection: prefs.layout) {
                ForEach(SwitcherLayout.allCases) { Text($0.label).tag($0) }
            }
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
}
