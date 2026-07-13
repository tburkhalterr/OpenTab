// Sources/OpenTab/Preferences.swift
import Carbon.HIToolbox
import Combine
import Foundation

enum SwitcherLayout: String, CaseIterable, Codable, Identifiable {
    case appGrid
    case list
    case appOnly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .appGrid: return "App grid"
        case .list:    return "List"
        case .appOnly: return "One entry per app"
        }
    }
}

enum SwitcherDensity: String, CaseIterable, Codable, Identifiable {
    case normal
    case compact

    var id: String { rawValue }

    var label: String {
        switch self {
        case .normal:  return "Normal"
        case .compact: return "Compact"
        }
    }
}

enum WindowScope: String, CaseIterable, Codable, Identifiable {
    case allScreens
    case activeScreen

    var id: String { rawValue }

    var label: String {
        switch self {
        case .allScreens:   return "All screens"
        case .activeScreen: return "Active screen only"
        }
    }
}

struct Preferences: Codable, Equatable {
    var layout: SwitcherLayout = .appGrid
    var density: SwitcherDensity = .normal
    var scope: WindowScope = .allScreens
    var showMinimizedWindows: Bool = true
    var showHiddenApps: Bool = false

    var triggerKeyCode: UInt32 = UInt32(kVK_Tab)
    var triggerModifiers: UInt32 = UInt32(optionKey)
    var reverseAddsShift: Bool = true
}

final class PreferencesStore: ObservableObject {
    static let shared = PreferencesStore()
    static let didChange = Notification.Name("com.tburkhalterr.opentab.preferencesDidChange")

    @Published var preferences: Preferences {
        didSet {
            guard preferences != oldValue else { return }
            persist()
            NotificationCenter.default.post(name: Self.didChange, object: nil)
        }
    }

    private static let storageKey = "com.tburkhalterr.opentab.preferences"

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode(Preferences.self, from: data) {
            preferences = decoded
        } else {
            preferences = Preferences()
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
}
