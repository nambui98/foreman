import SwiftUI

/// `⑂ feat/login` next to a folder path: gets up to 120pt before the path, which truncates in
/// the middle instead, so both stay readable in the fixed-width panel.
struct BranchLabel: View {
    let branch: String

    var body: some View {
        Label(branch, systemImage: "arrow.triangle.branch")
            .lineLimit(1).truncationMode(.tail)
            .frame(maxWidth: 100, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .layoutPriority(1)
            .help(branch)
    }
}
