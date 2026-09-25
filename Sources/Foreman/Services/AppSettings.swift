import Foundation
import Observation

/// What the menu bar label shows next to the icon.
enum BadgeMode: String, CaseIterable, Sendable {
    case devCount, ram, both

    var title: String {
        switch self {
        case .devCount: "Số tiến trình dev"
        case .ram: "RAM của dev"
        case .both: "Cả hai"
        }
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
    }

    var badgeMode: BadgeMode { didSet { defaults.set(badgeMode.rawValue, forKey: Key.badgeMode) } }
    /// Dev RAM total at or above this tints the menu bar badge.
    var ramWarnGB: Double { didSet { defaults.set(ramWarnGB, forKey: Key.ramWarnGB) } }
    /// Editor used by "Mở trong …"; nil = first installed known editor.
    var editorBundleID: String? { didSet { defaults.set(editorBundleID, forKey: Key.editorBundleID) } }
    /// A quiet dev server must be at least this old to count as idle.
    var idleHours: Double { didSet { defaults.set(idleHours, forKey: Key.idleHours) } }
    var notifyEnabled: Bool { didSet { defaults.set(notifyEnabled, forKey: Key.notifyEnabled) } }
    /// A finished task shorter than this does not notify.
    var notifyMinWorkSec: Double { didSet { defaults.set(notifyMinWorkSec, forKey: Key.notifyMinWorkSec) } }
    /// Agents without hooks: how long CPU must stay idle before "done" is assumed.
    var cpuIdleDebounceSec: Double { didSet { defaults.set(cpuIdleDebounceSec, forKey: Key.cpuIdleDebounceSec) } }

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
        badgeMode = defaults.string(forKey: Key.badgeMode).flatMap(BadgeMode.init(rawValue:)) ?? .devCount
        ramWarnGB = defaults.object(forKey: Key.ramWarnGB) as? Double ?? 8
        editorBundleID = defaults.string(forKey: Key.editorBundleID)
        idleHours = defaults.object(forKey: Key.idleHours) as? Double ?? 2
        notifyEnabled = defaults.object(forKey: Key.notifyEnabled) as? Bool ?? true
        notifyMinWorkSec = defaults.object(forKey: Key.notifyMinWorkSec) as? Double ?? 20
        cpuIdleDebounceSec = defaults.object(forKey: Key.cpuIdleDebounceSec) as? Double ?? 30
        hotKeyEnabled = defaults.object(forKey: Key.hotKeyEnabled) as? Bool ?? true
        hotKey = defaults.data(forKey: Key.hotKey).flatMap { try? JSONDecoder().decode(HotKeyCombo.self, from: $0) }
            ?? .standard
    }
}
