import Foundation
import Testing
@testable import PortBar

@MainActor
struct AppSettingsTests {
    private func freshDefaults() throws -> UserDefaults {
        try #require(UserDefaults(suiteName: "portbar-settings-tests-\(UUID())"))
    }

    @Test func defaultsWhenNothingStored() throws {
        let settings = AppSettings(defaults: try freshDefaults())
        #expect(settings.badgeMode == .devCount)
        #expect(settings.ramWarnGB == 8)
        #expect(settings.editorBundleID == nil)
        #expect(settings.idleHours == 2)
        #expect(settings.notifyEnabled)
        #expect(settings.notifyMinWorkSec == 20)
        #expect(settings.cpuIdleDebounceSec == 30)
    }

    @Test func valuesPersistAcrossInstances() throws {
        let defaults = try freshDefaults()
        let settings = AppSettings(defaults: defaults)
        settings.badgeMode = .both
        settings.ramWarnGB = 12
        settings.editorBundleID = "com.microsoft.VSCode"
        settings.idleHours = 5
        settings.notifyEnabled = false
        settings.notifyMinWorkSec = 60

        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.badgeMode == .both)
        #expect(reloaded.ramWarnGB == 12)
        #expect(reloaded.editorBundleID == "com.microsoft.VSCode")
        #expect(reloaded.idleHours == 5)
        #expect(!reloaded.notifyEnabled)
        #expect(reloaded.notifyMinWorkSec == 60)
    }

    @Test func unknownBadgeModeFallsBackToDefault() throws {
        let defaults = try freshDefaults()
        defaults.set("bogus", forKey: AppSettings.Key.badgeMode)
        #expect(AppSettings(defaults: defaults).badgeMode == .devCount)
    }
}
