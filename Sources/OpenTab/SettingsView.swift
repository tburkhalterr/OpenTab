// Sources/OpenTab/SettingsView.swift
import SwiftUI
import AppKit
import ApplicationServices
import CoreGraphics

struct SettingsView: View {
    private enum Pane: String, CaseIterable {
        case appearance = "Appearance"
        case shortcut = "Shortcut"
        case system = "System"

        var icon: String {
            switch self {
            case .appearance: return "square.grid.2x2"
            case .shortcut: return "keyboard"
            case .system: return "gearshape"
            }
        }
    }

    @ObservedObject private var store = PreferencesStore.shared
    @ObservedObject private var status = AppStatus.shared
    @State private var section: Pane = .appearance
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var accessibility = AXIsProcessTrusted()
    @State private var screenRecording = CGPreflightScreenCaptureAccess()

    private let ticker = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()
    private var prefs: Binding<Preferences> { $store.preferences }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 580, height: 400)
        .onReceive(ticker) { _ in
            accessibility = AXIsProcessTrusted()
            screenRecording = CGPreflightScreenCaptureAccess()
            launchAtLogin = LoginItem.isEnabled
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable().frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 1) {
                    Text("OpenTab").font(.system(size: 13, weight: .semibold))
                    Text("Version \(appVersion)").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)

            ForEach(Pane.allCases, id: \.self) { item in
                sidebarRow(item)
            }

            Spacer()

            if let url = URL(string: "https://github.com/tburkhalterr/OpenTab") {
                Link(destination: url) {
                    Label("View on GitHub", systemImage: "arrow.up.forward.square")
                        .font(.caption)
                }
                .padding(.horizontal, 8)
            }
        }
        .padding(12)
        .frame(width: 184)
        .background(.regularMaterial)
    }

    private func sidebarRow(_ item: Pane) -> some View {
        let selected = section == item
        return Button {
            section = item
        } label: {
            HStack(spacing: 9) {
                Image(systemName: item.icon)
                    .frame(width: 18)
                    .foregroundStyle(selected ? Color.white : .secondary)
                Text(item.rawValue)
                    .foregroundStyle(selected ? Color.white : .primary)
                Spacer()
            }
            .font(.system(size: 13))
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(selected ? Color.accentColor : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var content: some View {
        switch section {
        case .appearance: appearanceTab
        case .shortcut: shortcutTab
        case .system: systemTab
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    // MARK: - Appearance

    private var appearanceTab: some View {
        Form {
            Section("Layout") {
                Picker("View", selection: prefs.layout) {
                    ForEach(SwitcherLayout.allCases) { Text($0.label).tag($0) }
                }
                Picker("Density", selection: prefs.density) {
                    ForEach(SwitcherDensity.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle("Live thumbnails (grid)", isOn: prefs.showThumbnails)
            }
            Section("Windows") {
                Picker("Include windows from", selection: prefs.scope) {
                    ForEach(WindowScope.allCases) { Text($0.label).tag($0) }
                }
                Picker("Sort order", selection: prefs.sortOrder) {
                    ForEach(SortOrder.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Show minimized windows", isOn: prefs.showMinimizedWindows)
                Toggle("Show hidden apps", isOn: prefs.showHiddenApps)
            }
            ignoredAppsSection
        }
        .formStyle(.grouped)
    }

    private struct AppOption: Identifiable { let id: String; let name: String }

    @ViewBuilder private var ignoredAppsSection: some View {
        Section("Ignored apps") {
            ForEach(store.preferences.excludedBundleIDs, id: \.self) { bundleID in
                HStack {
                    Text(appName(for: bundleID))
                    Spacer()
                    Button {
                        store.preferences.excludedBundleIDs.removeAll { $0 == bundleID }
                    } label: {
                        Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
            }
            Menu("Add app…") {
                ForEach(addableApps) { app in
                    Button(app.name) { store.preferences.excludedBundleIDs.append(app.id) }
                }
            }
        }
    }

    private var addableApps: [AppOption] {
        let excluded = Set(store.preferences.excludedBundleIDs)
        let options = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> AppOption? in
                guard let id = app.bundleIdentifier, !excluded.contains(id) else { return nil }
                return AppOption(id: id, name: app.localizedName ?? id)
            }
        return Dictionary(options.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            .values.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    private func appName(for bundleID: String) -> String {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.localizedName
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)?
                .deletingPathExtension().lastPathComponent
            ?? bundleID
    }

    // MARK: - Shortcut

    private var shortcutTab: some View {
        Form {
            Section {
                LabeledContent("Cycle windows") {
                    ShortcutRecorderButton(keyCode: prefs.triggerKeyCode,
                                           modifiers: prefs.triggerModifiers)
                }
                Toggle("Add Shift to cycle backwards", isOn: prefs.reverseAddsShift)
            } footer: {
                Text("Hold the modifier and tap the key to move forward; release to focus. "
                    + "Hold the key to auto-repeat.")
            }

            Section {
                Toggle("Enable app switcher", isOn: prefs.appSwitcherEnabled)
                if store.preferences.appSwitcherEnabled {
                    LabeledContent("Cycle apps") {
                        ShortcutRecorderButton(keyCode: prefs.appSwitcherKeyCode,
                                               modifiers: prefs.appSwitcherModifiers)
                    }
                }
            } header: {
                Text("App switcher")
            } footer: {
                Text("A second shortcut that shows one entry per app (⌘Tab-style).")
            }

            Section("While the switcher is open") {
                shortcutHint("Tab · arrows", "Move selection")
                shortcutHint("1–9", "Focus that window directly")
                shortcutHint("Type a name", "Filter the list")
                shortcutHint("⌘W  ⌘M  ⌘H  ⌘Q", "Close · Minimize · Hide · Quit")
                shortcutHint("Click", "Focus a window")
                shortcutHint("Esc", "Cancel (clears the filter first)")
            }
        }
        .formStyle(.grouped)
    }

    private func shortcutHint(_ keys: String, _ meaning: String) -> some View {
        HStack {
            Text(keys)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.primary)
            Spacer()
            Text(meaning).font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: - System

    private var systemTab: some View {
        Form {
            Section("General") {
                Toggle("Launch OpenTab at login", isOn: Binding(
                    get: { launchAtLogin },
                    set: { launchAtLogin = LoginItem.setEnabled($0) }
                ))
            }

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
                Text("Accessibility applies live once granted; Screen Recording needs a relaunch.")
            }

            Section("Status") {
                if !status.hotKeyRegistered {
                    statusRow("Shortcut unavailable", ok: false,
                              detail: "The shortcut is already used by another app — pick another above.")
                }
                if !status.axSymbolWorks {
                    statusRow("Window matching degraded", ok: false,
                              detail: "OpenTab's window-matching API stopped working (likely a macOS update).")
                }
                if status.hotKeyRegistered && status.axSymbolWorks {
                    statusRow("Shortcut & window matching OK", ok: true, detail: nil)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func statusRow(_ title: String, ok: Bool, detail: String?) -> some View {
        HStack(spacing: 10) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(ok ? .green : .orange)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12, weight: .medium))
                if let detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
        }
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
