// Sources/OpenTab/ShortcutRecorder.swift
import AppKit
import SwiftUI
import Carbon.HIToolbox

final class ShortcutRecorder: ObservableObject {
    @Published private(set) var isRecording = false
    private var monitor: Any?
    private let onCapture: (_ keyCode: UInt32, _ modifiers: UInt32) -> Void

    init(onCapture: @escaping (UInt32, UInt32) -> Void) {
        self.onCapture = onCapture
    }

    func toggle() {
        isRecording ? stop() : start()
    }

    func start() {
        guard monitor == nil else { return }
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == UInt16(kVK_Escape) {
                self.stop()
                return nil
            }
            let modifiers = ShortcutFormatting.carbonModifiers(from: event.modifierFlags)
            // Require at least one modifier so the shortcut is globally usable.
            guard modifiers != 0 else { return nil }
            self.onCapture(UInt32(event.keyCode), modifiers)
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
        Button(action: { recorder.toggle() }) {
            Text(recorder.isRecording
                 ? "Press keys… (Esc to cancel)"
                 : ShortcutFormatting.describe(keyCode: keyCode, modifiers: modifiers))
                .frame(minWidth: 180)
                .monospacedDigit()
        }
        .onDisappear { recorder.stop() }
    }
}
