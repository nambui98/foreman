import AppKit
import SwiftUI

/// Keeps the menu bar panel hanging right below the menu bar of its screen.
///
/// MenuBarExtra places the panel against the status item, which moves when the menu bar slides
/// away (full-screen apps), so a re-layout could leave the header under the menu bar. The target
/// top is computed from the screen instead: `visibleFrame` excludes the menu bar (taller on
/// notched MacBooks) even while it is hidden, so nothing needs to be remembered and the result
/// doesn't depend on the order of window events.
struct PanelWindowAnchor: NSViewRepresentable {
    /// MenuBarExtra leaves this gap below the menu bar.
    static let gap: CGFloat = 2

    func makeNSView(context: Context) -> AnchorView { AnchorView() }
    func updateNSView(_ nsView: AnchorView, context: Context) {}

    /// Top edge (AppKit coordinates) the panel should have on `screen`.
    static func targetTop(on screen: NSScreen) -> CGFloat {
        screen.visibleFrame.maxY - gap
    }

    final class AnchorView: NSView {
        private var observers: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            guard let window else { return }
            let names = [NSWindow.didMoveNotification, NSWindow.didResizeNotification,
                         NSWindow.didChangeOcclusionStateNotification, NSWindow.didChangeScreenNotification]
            for name in names {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) {
                    [weak self] _ in MainActor.assumeIsolated { self?.placeBelowMenuBar() }
                })
            }
        }

        /// Setting the same top again is a no-op, so the move notification this causes cannot loop.
        private func placeBelowMenuBar() {
            guard let window, window.isVisible, let screen = window.screen else { return }
            let top = PanelWindowAnchor.targetTop(on: screen)
            guard abs(window.frame.maxY - top) > 0.5 else { return }
            window.setFrameTopLeftPoint(NSPoint(x: window.frame.minX, y: top))
        }
    }
}
