import AppKit
import SwiftUI

/// Pins the menu bar panel's top edge for as long as it is open.
///
/// With a full-screen app in front, the menu bar slides away once the pointer leaves it. When the
/// panel then re-lays out (switching tabs), MenuBarExtra repositions the window against the
/// screen's new visible frame and the header jumps up by the menu bar's height, under the menu
/// bar when it slides back. The top edge the panel opened at is remembered and restored.
struct PanelWindowAnchor: NSViewRepresentable {
    func makeNSView(context: Context) -> AnchorView { AnchorView() }
    func updateNSView(_ nsView: AnchorView, context: Context) {}

    final class AnchorView: NSView {
        private var anchorTop: CGFloat?
        private var observers: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            guard let window else { return }
            let center = NotificationCenter.default
            observers.append(center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) {
                [weak self] _ in MainActor.assumeIsolated { self?.anchorTop = self?.window?.frame.maxY }
            })
            // Shown → remember where it opened; hidden → forget, so the next opening (maybe on
            // another display) is placed fresh.
            observers.append(center.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, let window = self.window else { return }
                    if window.occlusionState.contains(.visible) {
                        if self.anchorTop == nil { self.anchorTop = window.frame.maxY }
                    } else {
                        self.anchorTop = nil
                    }
                }
            })
            for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
                observers.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.restoreTop() }
                })
            }
            if window.isKeyWindow { anchorTop = window.frame.maxY }
        }

        /// Moves the window back so its top sits where it opened (setting the same top again is a
        /// no-op, so this cannot loop).
        private func restoreTop() {
            guard let window, window.isVisible, let anchorTop, abs(window.frame.maxY - anchorTop) > 0.5 else { return }
            window.setFrameTopLeftPoint(NSPoint(x: window.frame.minX, y: anchorTop))
        }
    }
}
