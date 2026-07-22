// Sources/OpenTab/ShortcutRecorder.swift
import AppKit
import SwiftUI
import Carbon.HIToolbox

final class ShortcutRecorder: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var conflict: String?
    private var monitor: Any?
    private var reserved: Set<SystemShortcuts.Combo> = []
    private let onCapture: (_ keyCode: UInt32, _ modifiers: UInt32) -> Void

    init(onCapture: @escaping (UInt32, UInt32) -> Void) {
        self.onCapture = onCapture
    }

    func toggle() {
        if isRecording { stop() } else { start() }
    }

    func start() {
        guard monitor == nil else { return }
        isRecording = true
        conflict = nil
        reserved = SystemShortcuts.reserved()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == UInt16(kVK_Escape) {
                self.stop()
                return nil
            }
            let modifiers = ShortcutFormatting.carbonModifiers(from: event.modifierFlags)
            // Require at least one modifier so the shortcut is globally usable.
            guard modifiers != 0 else { return nil }
            let keyCode = UInt32(event.keyCode)
            if self.reserved.contains(.init(keyCode: keyCode, carbonModifiers: modifiers)) {
                // Keep recording so the user can immediately try another combo.
                self.conflict = ShortcutFormatting.describe(keyCode: keyCode, modifiers: modifiers)
                    + " is reserved by macOS — try another."
                return nil
            }
            self.conflict = nil
            self.onCapture(keyCode, modifiers)
            self.stop()
            return nil
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
    }
}

struct ShortcutRecorderButton: View {
    @Binding var keyCode: UInt32
    @Binding var modifiers: UInt32
    @StateObject private var recorder: ShortcutRecorder

    init(keyCode: Binding<UInt32>, modifiers: Binding<UInt32>) {
        _keyCode = keyCode
        _modifiers = modifiers
        _recorder = StateObject(wrappedValue: ShortcutRecorder { code, mods in
            keyCode.wrappedValue = code
            modifiers.wrappedValue = mods
        })
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Button(action: { recorder.toggle() }) {
                Text(recorder.isRecording
                     ? "Press keys… (Esc to cancel)"
                     : ShortcutFormatting.describe(keyCode: keyCode, modifiers: modifiers))
                    .frame(minWidth: 180)
                    .monospacedDigit()
            }
            if let conflict = recorder.conflict {
                Text(conflict)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onDisappear { recorder.stop() }
    }
}
