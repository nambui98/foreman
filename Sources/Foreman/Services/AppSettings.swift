import Foundation
import Observation

/// What the menu bar label shows next to the icon.
enum BadgeMode: String, CaseIterable, Sendable {
    case devCount, ram, both

    var title: String {
        switch self {
        case .devCount: String(localized: "Dev process count")
        case .ram: String(localized: "Dev RAM")
        case .both: String(localized: "Both")
        }
    }
}

/// Interface language. English is the default, whatever the system language is.
enum AppLanguage: String, CaseIterable, Sendable {
    case english = "en"
    case vietnamese = "vi"

    /// Shown in its own language so it can always be found.
    var name: String {
        switch self {
        case .english: "English"
        case .vietnamese: "Tiếng Việt"
        }
    }

    static let defaultsKey = "appLanguage"

    /// Makes the stored choice (English when none) the app's only localization, before any string is
    /// loaded. The bundle resolves its language once per launch, so a change applies on restart.
    static func applyStored(defaults: UserDefaults = .standard) {
        let language = defaults.string(forKey: defaultsKey).flatMap(AppLanguage.init(rawValue:)) ?? .english
        defaults.set([language.rawValue], forKey: "AppleLanguages")
    }
}

/// User preferences, persisted in UserDefaults. Launch at login is not stored here:
/// `SMAppService` owns that state (see `LoginItem`).
@MainActor
@Observable
final class AppSettings {
    enum Key {
        static let badgeMode = "badgeMode"
        static let ramWarnGB = "ramWarnGB"
        static let editorBundleID = "editorBundleID"
        static let idleHours = "idleHours"
        static let notifyEnabled = "notifyEnabled"
        static let notifyMinWorkSec = "notifyMinWorkSec"
        static let cpuIdleDebounceSec = "cpuIdleDebounceSec"
        static let hotKeyEnabled = "hotKeyEnabled"
        static let hotKey = "hotKey"
        static let keepAwake = "keepAwake"
        static let panelDetached = "panelDetached"
    }

    var language: AppLanguage {
        didSet {
            defaults.set(language.rawValue, forKey: AppLanguage.defaultsKey)
            AppLanguage.applyStored(defaults: defaults)
        }
    }
    /// Language the running app loaded its strings in; differs from `language` until a restart.
    @ObservationIgnored let launchLanguage: AppLanguage

    var badgeMode: BadgeMode { didSet { defaults.set(badgeMode.rawValue, forKey: Key.badgeMode) } }
    /// Dev RAM total at or above this tints the menu bar badge.
    var ramWarnGB: Double { didSet { defaults.set(ramWarnGB, forKey: Key.ramWarnGB) } }
    /// Editor used by "Open in …"; nil = first installed known editor.
    var editorBundleID: String? { didSet { defaults.set(editorBundleID, forKey: Key.editorBundleID) } }
    /// A quiet dev server must be at least this old to count as idle.
    var idleHours: Double { didSet { defaults.set(idleHours, forKey: Key.idleHours) } }
    var notifyEnabled: Bool { didSet { defaults.set(notifyEnabled, forKey: Key.notifyEnabled) } }
    /// A finished task shorter than this does not notify.
    var notifyMinWorkSec: Double { didSet { defaults.set(notifyMinWorkSec, forKey: Key.notifyMinWorkSec) } }
    /// Agents without hooks: how long CPU must stay idle before "done" is assumed.
    var cpuIdleDebounceSec: Double { didSet { defaults.set(cpuIdleDebounceSec, forKey: Key.cpuIdleDebounceSec) } }

    /// The panel is torn off the menu bar as a floating window (restored at launch).
    var panelDetached: Bool { didSet { defaults.set(panelDetached, forKey: Key.panelDetached) } }
    /// Prevent idle sleep while an agent is working.
    var keepAwake: Bool { didSet { defaults.set(keepAwake, forKey: Key.keepAwake) } }
    var hotKeyEnabled: Bool { didSet { defaults.set(hotKeyEnabled, forKey: Key.hotKeyEnabled) } }
    /// Global shortcut that opens/closes the panel.
    var hotKey: HotKeyCombo {
        didSet { defaults.set(try? JSONEncoder().encode(hotKey), forKey: Key.hotKey) }
    }

    /// False when the shortcut could not be registered (taken by another app); not persisted.
    var hotKeyRegistered = true

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let language = defaults.string(forKey: AppLanguage.defaultsKey).flatMap(AppLanguage.init(rawValue:)) ?? .english
        self.language = language
        launchLanguage = language
        badgeMode = defaults.string(forKey: Key.badgeMode).flatMap(BadgeMode.init(rawValue:)) ?? .devCount
        ramWarnGB = defaults.object(forKey: Key.ramWarnGB) as? Double ?? 8
        editorBundleID = defaults.string(forKey: Key.editorBundleID)
        idleHours = defaults.object(forKey: Key.idleHours) as? Double ?? 2
        notifyEnabled = defaults.object(forKey: Key.notifyEnabled) as? Bool ?? true
        notifyMinWorkSec = defaults.object(forKey: Key.notifyMinWorkSec) as? Double ?? 20
        cpuIdleDebounceSec = defaults.object(forKey: Key.cpuIdleDebounceSec) as? Double ?? 30
        keepAwake = defaults.object(forKey: Key.keepAwake) as? Bool ?? true
        panelDetached = defaults.bool(forKey: Key.panelDetached)
        hotKeyEnabled = defaults.object(forKey: Key.hotKeyEnabled) as? Bool ?? true
        hotKey = defaults.data(forKey: Key.hotKey).flatMap { try? JSONDecoder().decode(HotKeyCombo.self, from: $0) }
            ?? .standard
    }
}
