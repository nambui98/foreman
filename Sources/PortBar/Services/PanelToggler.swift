import AppKit

/// Opens or closes the menu bar panel from code (global hotkey). `MenuBarExtra` has no API for
/// that, so this clicks PortBar's own status item button, which behaves exactly like a user click.
@MainActor
enum PanelToggler {
    @discardableResult
    static func toggle() -> Bool {
        guard let button = statusButton() else { return false }
        button.performClick(nil)
        return true
    }

    private static func statusButton() -> NSStatusBarButton? {
        for window in NSApp.windows where window.className.contains("StatusBarWindow") {
            if let button = find(in: window.contentView) { return button }
        }
        return nil
    }

    private static func find(in view: NSView?) -> NSStatusBarButton? {
        guard let view else { return nil }
        if let button = view as? NSStatusBarButton { return button }
        for subview in view.subviews {
            if let button = find(in: subview) { return button }
        }
        return nil
    }
}
