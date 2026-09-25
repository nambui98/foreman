import SwiftUI

/// Small capsule label (`Next.js`, `idle 4h 17m`, `Waiting for you`). Never wraps or squeezes:
/// the name next to it truncates instead.
struct Chip: View {
    let text: String
    let color: Color

    var body: some View {
        Text(verbatim: text).font(.caption2.weight(.semibold))
            .lineLimit(1).fixedSize()
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(color.opacity(0.18), in: .capsule).foregroundStyle(color)
    }
}
