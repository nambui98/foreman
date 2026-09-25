import AppKit
import Carbon.HIToolbox
import Foundation
import Testing
@testable import Foreman

struct BadgeFormatTests {
    private let gb: UInt64 = 1_073_741_824

    @Test func textPerMode() {
        #expect(BadgeLabel.text(count: 3, memoryBytes: 3 * gb + gb / 5, mode: .devCount) == "3")
        #expect(BadgeLabel.text(count: 3, memoryBytes: 3 * gb + gb / 5, mode: .ram) == "3.2G")
        #expect(BadgeLabel.text(count: 3, memoryBytes: 3 * gb + gb / 5, mode: .both) == "3 · 3.2G")
        #expect(BadgeLabel.text(count: 0, memoryBytes: 0, mode: .both) == nil)
        #expect(BadgeLabel.text(count: 0, memoryBytes: 0, mode: .devCount) == nil)
    }

    @Test func compactMemory() {
        #expect(BadgeLabel.compactMemory(850 * 1_048_576) == "850M")
        #expect(BadgeLabel.compactMemory(gb) == "1.0G")
    }

    @Test func warningThreshold() {
        #expect(BadgeLabel.isOverThreshold(memoryBytes: 8 * gb, warnGB: 8))
        #expect(!BadgeLabel.isOverThreshold(memoryBytes: 8 * gb - 1, warnGB: 8))
        #expect(!BadgeLabel.isOverThreshold(memoryBytes: 100 * gb, warnGB: 0))  // 0 = off
    }
}

struct HotKeyComboTests {
    @Test func standardIsOptionCommandP() {
        #expect(HotKeyCombo.standard.display == "⌥⌘P")
        #expect(HotKeyCombo.standard.keyCode == UInt32(kVK_ANSI_P))
        #expect(HotKeyCombo.standard.isValid)
    }

    @Test func modifierMapping() {
        let mask = HotKeyCombo.carbonModifiers(from: [.command, .shift, .control, .option])
        #expect(mask == UInt32(cmdKey | shiftKey | controlKey | optionKey))
        #expect(HotKeyCombo(keyCode: 0, carbonModifiers: mask, key: "A").display == "⌃⌥⇧⌘A")
    }

    @Test func shiftAloneIsNotAGlobalShortcut() {
        #expect(!HotKeyCombo(keyCode: 0, carbonModifiers: UInt32(shiftKey), key: "A").isValid)
        #expect(!HotKeyCombo(keyCode: 0, carbonModifiers: 0, key: "A").isValid)
    }

    @Test func fromKeyEvent() throws {
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [.command, .control], timestamp: 0, windowNumber: 0,
            context: nil, characters: "k", charactersIgnoringModifiers: "k", isARepeat: false,
            keyCode: UInt16(kVK_ANSI_K)))
        let combo = try #require(HotKeyCombo(event: event))
        #expect(combo.display == "⌃⌘K")
        #expect(combo.keyCode == UInt32(kVK_ANSI_K))
    }

    @MainActor
    @Test func persistsInSettings() throws {
        let defaults = try #require(UserDefaults(suiteName: "foreman-hotkey-\(UUID())"))
        let settings = AppSettings(defaults: defaults)
        #expect(settings.hotKey == .standard)
        #expect(settings.hotKeyEnabled)
        settings.hotKey = HotKeyCombo(keyCode: UInt32(kVK_ANSI_L), carbonModifiers: UInt32(controlKey | optionKey), key: "L")
        settings.hotKeyEnabled = false
        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.hotKey.display == "⌃⌥L")
        #expect(!reloaded.hotKeyEnabled)
    }
}

@MainActor
struct HotKeyRegistrationTests {
    /// ⌃⌥⇧F13: unlikely to be taken by another app on the test machine.
    private let combo = HotKeyCombo(
        keyCode: UInt32(kVK_F13), carbonModifiers: UInt32(controlKey | optionKey | shiftKey), key: "F13")

    @Test func sameComboRegistersAgainOnlyAfterRelease() {
        let first = HotKey(combo) {}
        #expect(first != nil)
        #expect(HotKey(combo) {} == nil)  // still held by `first`
        first?.unregister()
        let second = HotKey(combo) {}
        #expect(second != nil)
        second?.unregister()
    }
}
