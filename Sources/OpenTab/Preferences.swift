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
        case .appGrid: return "App grid (thumbnails)"
        case .list:    return "List"
        case .appOnly: return "One entry per app"
        }
    }
}

enum WindowScope: String, CaseIterable, Codable, Identifiable {
    case allScreens
    case activeScreen
    case activeSpace

    var id: String { rawValue }

    var label: String {
        switch self {
        case .allScreens:   return "All screens"
        case .activeScreen: return "Active screen only"
        case .activeSpace:  return "Current space only"
        }
    }
}

struct Preferences: Codable, Equatable {
    var layout: SwitcherLayout = .appGrid
    var scope: WindowScope = .allScreens
    var showMinimizedWindows: Bool = true
    var showHiddenApps: Bool = false

    var triggerKeyCode: UInt32 = UInt32(kVK_Tab)
    var triggerModifiers: UInt32 = UInt32(optionKey)
    var reverseAddsShift: Bool = true
}

final class PreferencesStore: ObservableObject {
    static let shared = PreferencesStore()
    static let didChange = Notification.Name("ch.socraft.opentab.preferencesDidChange")

    @Published var preferences: Preferences {
        didSet {
            guard preferences != oldValue else { return }
            persist()
            NotificationCenter.default.post(name: Self.didChange, object: nil)
        }
    }

    private static let storageKey = "ch.socraft.opentab.preferences"

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
