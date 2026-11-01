import AppKit

enum GeneralPreferences {
    static let defaultMainWindowVisibility = true
    static let defaultMenuBarVisibility = true
    static let defaultAdvancedFind = false
    static let defaultTouchBar = true
    static let showInMenuBarKey = "application.showInMenuBar"
    static let showMainWindowAtLaunchKey = "application.showMainWindowAtLaunch"
    static let advancedFindKey = "editor.preferAdvancedFind"
    static let showCustomTouchBarKey = "editor.showCustomTouchBar"

    static func showMainWindowAtLaunch(defaults: UserDefaults) -> Bool {
        defaults.object(forKey: showMainWindowAtLaunchKey) as? Bool ?? defaultMainWindowVisibility
    }

    static func showInMenuBar(defaults: UserDefaults) -> Bool {
        defaults.object(forKey: showInMenuBarKey) as? Bool ?? defaultMenuBarVisibility
    }
}

enum ApplicationAppearance: String, CaseIterable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

    static let preferenceKey = "application.appearance"

    static func resolved(_ value: String) -> ApplicationAppearance {
        ApplicationAppearance(rawValue: value) ?? .system
    }

    var nativeAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}


enum ActionMoveNavigation: String, CaseIterable {
    case createNew = "Create New Draft"
    case openNext = "Open Next Draft"
    static let preferenceKey = "application.actionMoveNavigation"
    static func resolved(_ value: String?) -> Self { Self(rawValue: value ?? "") ?? .createNew }
}
