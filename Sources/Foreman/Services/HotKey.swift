import AppKit
import Carbon.HIToolbox

/// A global shortcut: Carbon virtual key code + Carbon modifier mask, and the key's label.
struct HotKeyCombo: Codable, Equatable, Sendable {
    var keyCode: UInt32
    var carbonModifiers: UInt32
    var key: String

    /// ⌥⌘P
    static let standard = HotKeyCombo(keyCode: UInt32(kVK_ANSI_P), carbonModifiers: UInt32(cmdKey | optionKey), key: "P")

    /// `⌃⌥⇧⌘P`, in the order macOS menus use.
    var display: String {
        let symbols: [(Int, String)] = [(controlKey, "⌃"), (optionKey, "⌥"), (shiftKey, "⇧"), (cmdKey, "⌘")]
        return symbols.filter { carbonModifiers & UInt32($0.0) != 0 }.map(\.1).joined() + key
    }

    /// A global shortcut needs ⌘, ⌃ or ⌥; Shift alone would swallow ordinary typing.
    var isValid: Bool { carbonModifiers & UInt32(cmdKey | controlKey | optionKey) != 0 }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var mask = 0
        if flags.contains(.command) { mask |= cmdKey }
        if flags.contains(.option) { mask |= optionKey }
        if flags.contains(.control) { mask |= controlKey }
        if flags.contains(.shift) { mask |= shiftKey }
        return UInt32(mask)
    }

    init(keyCode: UInt32, carbonModifiers: UInt32, key: String) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
        self.key = key
    }

    /// From a key-down event, e.g. in the Settings recorder; nil for keys without a printable label.
    init?(event: NSEvent) {
        guard let characters = event.charactersIgnoringModifiers?.uppercased(), !characters.isEmpty,
              characters.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
            return nil
        }
        self.init(keyCode: UInt32(event.keyCode), carbonModifiers: Self.carbonModifiers(from: event.modifierFlags),
                  key: characters)
    }
}

/// A registered global hotkey (Carbon `RegisterEventHotKey`: no Accessibility permission needed).
/// The owner calls `unregister()` before dropping it: an isolated deinit would need the macOS 15+
/// Swift runtime, and Foreman supports macOS 14.
@MainActor
final class HotKey {
    private static let signature: OSType = 0x4672_6D6E  // 'Frmn'
    private static var actions: [UInt32: () -> Void] = [:]
    private static var nextID: UInt32 = 1
    private static var handlerInstalled = false

    private let id: UInt32
    private var ref: EventHotKeyRef?

    /// nil when the combination is taken by another app or invalid.
    init?(_ combo: HotKeyCombo, action: @escaping () -> Void) {
        guard combo.isValid, Self.installHandler() else { return nil }
        id = Self.nextID
        Self.nextID += 1
        var hotKeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            combo.keyCode, combo.carbonModifiers, EventHotKeyID(signature: Self.signature, id: id),
            GetApplicationEventTarget(), 0, &hotKeyRef)
        guard status == noErr, let hotKeyRef else { return nil }
        ref = hotKeyRef
        Self.actions[id] = action
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
        Self.actions[id] = nil
    }

    private static func installHandler() -> Bool {
        guard !handlerInstalled else { return true }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            // Carbon delivers hotkey events on the main thread's event loop.
            MainActor.assumeIsolated { HotKey.actions[hotKeyID.id]?() }
            return noErr
        }, 1, &spec, nil, nil)
        handlerInstalled = status == noErr
        return handlerInstalled
    }
}
