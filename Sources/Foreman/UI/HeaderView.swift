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
    var isDetached = false
    var requestCleanup: () -> Void = {}
    @State private var tornOff = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Foreman").font(.headline)
                    .help(isDetached ? "" : String(localized: "Drag down to detach the panel"))
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
                Button(action: togglePin) {
                    Image(systemName: isDetached ? "pin.slash" : "pin")
                }
                .buttonStyle(.borderless)
                .help(isDetached ? String(localized: "Attach to the menu bar") : String(localized: "Detach as a floating window"))
            }
            .contentShape(.rect)
            .gesture(DragGesture(minimumDistance: 12).onChanged(tearOff))
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

    private func togglePin() {
        if isDetached {
            FloatingPanelController.shared.attach()
            PanelToggler.toggle()  // reopen under the menu bar
        } else {
            detach(frame: NSApp.keyWindow?.frame)
        }
    }

    /// Dragging the menu bar panel's title row down tears it off where the pointer is.
    private func tearOff(_ drag: DragGesture.Value) {
        guard !isDetached, !tornOff, drag.translation.height > 30 else { return }
        tornOff = true
        detach(frame: NSApp.keyWindow?.frame.offsetBy(dx: drag.translation.width, dy: -drag.translation.height))
    }

    private func detach(frame: NSRect?) {
        PanelToggler.toggle()  // close the menu bar panel
        FloatingPanelController.shared.detach(from: frame)
        tornOff = false
    }

    private func label(for tab: PanelTab) -> String {
        switch tab {
        case .ports: "\(tab.title) (\(monitor.rows.count))"
        case .agents: "\(tab.title) (\(monitor.agents.count))"
        }
    }
}
