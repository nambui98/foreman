import AppKit
import SwiftUI

/// The panel torn off the menu bar: a floating, title-bar-less window with the same rounded
/// material look as the menu bar panel. It stays above other windows (full-screen apps included),
/// doesn't close when you click elsewhere, can be dragged by its background anywhere and remembers
/// where it was. The pin button puts the panel back in the menu bar.
@MainActor
final class FloatingPanelController: NSObject, NSWindowDelegate {
    static let shared = FloatingPanelController()

    private var panel: NSPanel?
    private var monitor: PortMonitor?
    private var settings: AppSettings?

    var isVisible: Bool { panel?.isVisible == true }

    func configure(monitor: PortMonitor, settings: AppSettings) {
        self.monitor = monitor
        self.settings = settings
    }

    /// Shows the floating panel; `frame` places it where the menu bar panel was (tear-off).
    func detach(from frame: NSRect? = nil) {
        guard let panel = makePanelIfNeeded() else { return }
        if let frame { panel.setFrame(frame, display: false) }
        settings?.panelDetached = true
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
    }

    /// Hides the floating panel and returns to the menu bar panel.
    func attach() {
        settings?.panelDetached = false
        panel?.orderOut(nil)
    }

    /// Global shortcut while detached: hide or show the floating panel without re-attaching it.
    func toggleVisibility() {
        if isVisible {
            panel?.orderOut(nil)
        } else {
            detach()
        }
    }

    private func makePanelIfNeeded() -> NSPanel? {
        if let panel { return panel }
        guard let monitor, let settings else { return nil }
        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 640),
            styleMask: [.borderless], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        let hosting = NSHostingView(rootView: PanelView(isDetached: true).environment(monitor).environment(settings))
        hosting.sizingOptions = [.intrinsicContentSize]  // the window always fits the panel exactly
        hosting.wantsLayer = true
        hosting.layer?.cornerRadius = 12
        hosting.layer?.masksToBounds = true
        panel.contentView = hosting
        panel.setContentSize(hosting.fittingSize)
        panel.center()
        panel.setFrameAutosaveName("ForemanFloatingPanel")  // restores the last position…
        panel.setContentSize(hosting.fittingSize)  // …but never an old, stale size
        self.panel = panel
        return panel
    }
}

/// Borderless windows can't become key by default; the search field needs keyboard focus.
private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}
