import SwiftUI

/// Which list the panel shows.
enum PanelTab: String, CaseIterable {
    case ports = "Cổng"
    case agents = "Agents"
}

struct HeaderView: View {
    @Environment(PortMonitor.self) private var monitor
    @Binding var query: String
    @Binding var tab: PanelTab
    let totals: String
    var requestCleanup: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Foreman").font(.headline)
                Spacer()
                Text(totals).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                if tab == .ports, !monitor.cleanupCandidates.isEmpty {
                    Button("Dọn (\(monitor.cleanupCandidates.count))", action: requestCleanup)
                        .controlSize(.small)
                        .help("Dừng các dev server mồ côi / rảnh lâu")
                }
                Button {
                    Task { await monitor.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Làm mới")
            }
            Picker("", selection: $tab) {
                ForEach(PanelTab.allCases, id: \.self) { tab in
                    Text(label(for: tab)).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            TextField(tab == .ports ? "Tìm cổng, tên, thư mục…" : "Tìm agent, project, terminal…", text: $query)
                .textFieldStyle(.roundedBorder)
        }
        .padding(12)
    }

    private func label(for tab: PanelTab) -> String {
        switch tab {
        case .ports: "\(tab.rawValue) (\(monitor.rows.count))"
        case .agents: "\(tab.rawValue) (\(monitor.agents.count))"
        }
    }
}
