import SwiftUI

/// Content of the menu bar window: header, grouped rows, footer.
struct PanelView: View {
    @Environment(PortMonitor.self) private var monitor
    @Environment(\.openSettings) private var openSettings
    @State private var query = ""
    @State private var expanded: Set<ProcessGroup> = [.dev, .dataContainer]
    @State private var confirmation: Confirmation?
    @State private var tab: PanelTab = .ports
    @State private var showCleanup = false

    var body: some View {
        VStack(spacing: 0) {
            HeaderView(query: $query, tab: $tab, totals: totals) { showCleanup = true }
            Divider()
            switch tab {
            case .ports: content
            case .agents: agentsContent
            }
            Divider()
            footer
        }
        .frame(width: 420)
        .onAppear { monitor.setPanelOpen(true) }
        .onDisappear { monitor.setPanelOpen(false) }
        .overlay {
            if let confirmation {
                ConfirmOverlay(confirmation: confirmation) { self.confirmation = nil }
            } else if showCleanup {
                CleanupOverlay(candidates: monitor.cleanupCandidates) { selected in
                    Task { await monitor.cleanUp(selected) }
                } dismiss: {
                    showCleanup = false
                }
            }
        }
    }

    private var totals: String {
        switch tab {
        case .ports:
            let cpu = visibleRows.compactMap(\.cpuPercent).reduce(0, +)
            let memory = visibleRows.compactMap(\.memoryBytes).reduce(0, +)
            return String(localized: "\(visibleRows.count) processes · CPU \(Formatters.cpu(cpu)) · RAM \(Formatters.memory(memory))")
        case .agents:
            let cpu = visibleAgents.compactMap(\.cpuPercent).reduce(0, +)
            let memory = visibleAgents.compactMap(\.memoryBytes).reduce(0, +)
            return String(localized: "\(visibleAgents.count) agents · CPU \(Formatters.cpu(cpu)) · RAM \(Formatters.memory(memory))")
        }
    }

    private var visibleAgents: [AgentRow] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return monitor.agents }
        return monitor.agents.filter { agent in
            [agent.kind.displayName, agent.teamMember, agent.cwd, agent.host, agent.tty, String(agent.pid)]
                .compactMap { $0?.lowercased() }.contains { $0.contains(needle) }
        }
    }

    @ViewBuilder private var agentsContent: some View {
        if visibleAgents.isEmpty {
            ContentUnavailableView(query.isEmpty ? String(localized: "No agents running") : String(localized: "No matches"),
                                   systemImage: "sparkles")
                .frame(height: 200)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(visibleAgents) { agent in
                        AgentRowView(agent: agent) { pending in
                            confirmation = Confirmation(title: pending.title, message: pending.message) {
                                await monitor.stop(pending.agent)
                            }
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            .frame(height: 480)
        }
    }

    private var visibleRows: [PortRow] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return monitor.rows }
        return monitor.rows.filter { row in
            row.ports.contains { String($0).contains(needle) }
                || row.name.lowercased().contains(needle)
                || (row.cwd?.lowercased().contains(needle) ?? false)
                || (row.commandLine?.lowercased().contains(needle) ?? false)
        }
    }

    @ViewBuilder private var content: some View {
        if let error = monitor.lastError, monitor.rows.isEmpty {
            ContentUnavailableView("Can't read the port list", systemImage: "exclamationmark.triangle",
                                   description: Text(error))
                .frame(height: 200)
        } else if visibleRows.isEmpty {
            ContentUnavailableView(query.isEmpty ? String(localized: "No open ports") : String(localized: "No matches"),
                                   systemImage: "network.slash")
                .frame(height: 200)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(ProcessGroup.allCases, id: \.self) { group in
                        section(group, rows: visibleRows.filter { $0.group == group })
                    }
                }
                .padding(.vertical, 8)
            }
            // MenuBarExtra windows size to the content's ideal height and a ScrollView has none
            // (min/ideal hints are ignored), so the list needs an explicit height or it collapses.
            .frame(height: 480)
        }
    }

    @ViewBuilder private func section(_ group: ProcessGroup, rows: [PortRow]) -> some View {
        if !rows.isEmpty {
            // Searching expands every section so matches are never hidden.
            let isExpanded = !query.isEmpty || expanded.contains(group)
            Button {
                if expanded.contains(group) { expanded.remove(group) } else { expanded.insert(group) }
            } label: {
                HStack {
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .font(.caption2.weight(.bold))
                    Text(group.title).font(.subheadline.weight(.semibold))
                    Text("\(rows.count)").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12).padding(.top, 6)

            if isExpanded {
                ForEach(rows) { row in
                    PortRowView(row: row, isSystem: group == .system) { pending in
                        confirmation = Confirmation(title: pending.title, message: pending.message) {
                            await monitor.kill(pending.row, wholeGroup: pending.wholeGroup, force: pending.force)
                        }
                    } confirm: { confirmation = $0 }
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            if let updated = monitor.lastUpdated {
                Text("Updated \(updated.formatted(date: .omitted, time: .standard))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if monitor.isKeepingAwake {
                Image(systemName: "cup.and.saucer.fill").font(.caption).foregroundStyle(.secondary)
                    .help("Keeping the Mac awake while an agent works")
            }
            Spacer()
            Button {
                // A menu bar (LSUIElement) app must activate itself or Settings opens behind other apps.
                NSApp.activate()
                openSettings()
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("Settings")
            .keyboardShortcut(",")
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }
}
