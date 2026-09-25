import SwiftUI

/// Which list the panel shows.
enum PanelTab: String, CaseIterable {
    case ports, agents

    var title: String {
        switch self {
        case .ports: String(localized: "Ports")
        case .agents: String(localized: "Agents")
        }
    }
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
                    Button("Clean up (\(monitor.cleanupCandidates.count))", action: requestCleanup)
                        .controlSize(.small)
                        .help("Stop orphaned or long-idle dev servers")
                }
                Button {
                    Task { await monitor.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh")
            }
            Picker("", selection: $tab) {
                ForEach(PanelTab.allCases, id: \.self) { tab in
                    Text(label(for: tab)).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            TextField(tab == .ports ? String(localized: "Search ports, names, folders…")
                                    : String(localized: "Search agents, projects, terminals…"), text: $query)
                .textFieldStyle(.roundedBorder)
        }
        .padding(12)
    }

    private func label(for tab: PanelTab) -> String {
        switch tab {
        case .ports: "\(tab.title) (\(monitor.rows.count))"
        case .agents: "\(tab.title) (\(monitor.agents.count))"
        }
    }
}
