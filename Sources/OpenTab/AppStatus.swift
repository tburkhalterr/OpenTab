// Sources/OpenTab/AppStatus.swift
import Combine

/// Observable health flags surfaced in the Settings "System" tab.
final class AppStatus: ObservableObject {
    static let shared = AppStatus()

    /// The global shortcut registered with Carbon (false if the combo is taken).
    @Published var hotKeyRegistered = true
    /// The private `_AXUIElementGetWindow` symbol still resolves windows.
    @Published var axSymbolWorks = true

    private init() {}
}
