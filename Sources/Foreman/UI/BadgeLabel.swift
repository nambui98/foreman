import AppKit
import SwiftUI

/// Menu bar label: icon plus dev process count and/or dev RAM. When dev RAM is over the Settings
/// threshold the icon turns orange. The menu bar keeps only the label's first image, so the
/// warning is that image itself, pre-colored and non-template (a separate dot is dropped).
struct BadgeLabel: View {
    let count: Int
    let memoryBytes: UInt64
    let mode: BadgeMode
    let warnGB: Double

    var body: some View {
        HStack(spacing: 2) {
            if Self.isOverThreshold(memoryBytes: memoryBytes, warnGB: warnGB) {
                Image(nsImage: Self.warningIcon)
            } else {
                Image(Self.iconName)  // template asset: follows the menu bar's light/dark appearance
            }
            if let text = Self.text(count: count, memoryBytes: memoryBytes, mode: mode) {
                Text(text).monospacedDigit()
            }
        }
        .accessibilityLabel(String(localized: "Foreman, \(count) dev ports, \(Formatters.memory(memoryBytes))"))
    }

    /// `3`, `3.2G`, `3 · 3.2G`; nil when there is nothing to show.
    nonisolated static func text(count: Int, memoryBytes: UInt64, mode: BadgeMode) -> String? {
        let ram = memoryBytes > 0 ? compactMemory(memoryBytes) : nil
        let parts: [String?] = switch mode {
        case .devCount: [count > 0 ? "\(count)" : nil]
        case .ram: [ram]
        case .both: [count > 0 ? "\(count)" : nil, ram]
        }
        let shown = parts.compactMap { $0 }
        return shown.isEmpty ? nil : shown.joined(separator: " · ")
    }

    /// `850M`, `3.2G` — short enough for the menu bar.
    nonisolated static func compactMemory(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / 1_073_741_824
        return gb >= 1 ? String(format: "%.1fG", gb) : "\(Int((Double(bytes) / 1_048_576).rounded()))M"
    }

    nonisolated static func isOverThreshold(memoryBytes: UInt64, warnGB: Double) -> Bool {
        warnGB > 0 && Double(memoryBytes) >= warnGB * 1_073_741_824
    }

    /// The Foreman mark as a vector template image (Assets.xcassets/MenuBarIcon).
    private static let iconName = "MenuBarIcon"

    /// Same glyph pre-coloured orange; the menu bar keeps a non-template image's colours.
    private static let warningIcon: NSImage = {
        guard let glyph = NSImage(named: iconName) else { return NSImage() }
        let image = NSImage(size: glyph.size, flipped: false) { rect in
            glyph.draw(in: rect)
            NSColor.systemOrange.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        image.isTemplate = false
        return image
    }()
}
