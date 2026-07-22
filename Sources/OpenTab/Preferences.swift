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

enum SortOrder: String, CaseIterable, Codable, Identifiable {
    case recent
    case alphabetical
    case byApp

    var id: String { rawValue }

    var label: String {
        switch self {
        case .recent:       return "Recently used"
        case .alphabetical: return "Alphabetical"
        case .byApp:        return "Grouped by app"
        }
    }
}

struct Preferences: Codable, Equatable {
    var layout: SwitcherLayout = .appGrid
    var density: SwitcherDensity = .normal
    var showThumbnails: Bool = true
    var scope: WindowScope = .allScreens
    var sortOrder: SortOrder = .recent
    var showMinimizedWindows: Bool = true
    var showHiddenApps: Bool = false
    var excludedBundleIDs: [String] = []

    var triggerKeyCode: UInt32 = UInt32(kVK_Tab)
    var triggerModifiers: UInt32 = UInt32(optionKey)
    var reverseAddsShift: Bool = true

    var appSwitcherEnabled: Bool = false
    var appSwitcherKeyCode: UInt32 = UInt32(kVK_ANSI_Grave)
    var appSwitcherModifiers: UInt32 = UInt32(optionKey)

    init() {}

    // Decode each field independently with a default fallback so that adding a
    // new preference in a later release doesn't fail to decode an older payload
    // (which would silently wipe every existing setting on upgrade).
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Preferences()
        layout = try container.decodeIfPresent(SwitcherLayout.self, forKey: .layout) ?? defaults.layout
        density = try container.decodeIfPresent(SwitcherDensity.self, forKey: .density) ?? defaults.density
        showThumbnails = try container.decodeIfPresent(Bool.self, forKey: .showThumbnails) ?? defaults.showThumbnails
        scope = try container.decodeIfPresent(WindowScope.self, forKey: .scope) ?? defaults.scope
        sortOrder = try container.decodeIfPresent(SortOrder.self, forKey: .sortOrder) ?? defaults.sortOrder
        showMinimizedWindows = try container.decodeIfPresent(Bool.self, forKey: .showMinimizedWindows) ?? defaults.showMinimizedWindows
        showHiddenApps = try container.decodeIfPresent(Bool.self, forKey: .showHiddenApps) ?? defaults.showHiddenApps
        excludedBundleIDs = try container.decodeIfPresent([String].self, forKey: .excludedBundleIDs) ?? defaults.excludedBundleIDs
        triggerKeyCode = try container.decodeIfPresent(UInt32.self, forKey: .triggerKeyCode) ?? defaults.triggerKeyCode
        triggerModifiers = try container.decodeIfPresent(UInt32.self, forKey: .triggerModifiers) ?? defaults.triggerModifiers
        reverseAddsShift = try container.decodeIfPresent(Bool.self, forKey: .reverseAddsShift) ?? defaults.reverseAddsShift
        appSwitcherEnabled = try container.decodeIfPresent(Bool.self, forKey: .appSwitcherEnabled) ?? defaults.appSwitcherEnabled
        appSwitcherKeyCode = try container.decodeIfPresent(UInt32.self, forKey: .appSwitcherKeyCode) ?? defaults.appSwitcherKeyCode
        appSwitcherModifiers = try container.decodeIfPresent(UInt32.self, forKey: .appSwitcherModifiers) ?? defaults.appSwitcherModifiers
    }
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
