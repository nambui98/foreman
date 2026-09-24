import SwiftUI

struct HeaderView: View {
    @Environment(PortMonitor.self) private var monitor
    @Binding var query: String
    let visibleRows: [PortRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("PortBar").font(.headline)
                Spacer()
                Text(totals).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                Button {
                    Task { await monitor.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Làm mới")
            }
            TextField("Tìm cổng, tên, thư mục…", text: $query)
                .textFieldStyle(.roundedBorder)
        }
        .padding(12)
    }

    private var totals: String {
        let cpu = visibleRows.compactMap(\.cpuPercent).reduce(0, +)
        let memory = visibleRows.compactMap(\.memoryBytes).reduce(0, +)
        return "\(visibleRows.count) tiến trình · CPU \(Formatters.cpu(cpu)) · RAM \(Formatters.memory(memory))"
    }
}
