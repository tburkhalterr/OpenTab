// Sources/OpenTab/LoginItem.swift
import ServiceManagement

/// Launch-at-login backed by SMAppService; the system is the source of truth.
enum LoginItem {
    static var isEnabled: Bool {
        guard #available(macOS 13.0, *) else { return false }
        return SMAppService.mainApp.status == .enabled
    }

    /// Registers/unregisters the app as a login item and returns the resulting
    /// state (so the UI reflects reality even if the change was rejected).
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        guard #available(macOS 13.0, *) else { return false }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Ignore and report the real status below.
        }
        return isEnabled
    }
}
