import SwiftUI

/// Menu bar label: network glyph plus the number of dev processes listening.
struct BadgeLabel: View {
    let count: Int

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
            if count > 0 { Text("\(count)").monospacedDigit() }
        }
        .accessibilityLabel("PortBar, \(count) dev ports")
    }
}
