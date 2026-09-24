import SwiftUI

/// Content of the menu bar window: header, grouped rows, footer.
struct PanelView: View {
    @Environment(PortMonitor.self) private var monitor
    @State private var query = ""
    @State private var expanded: Set<ProcessGroup> = [.dev, .dataContainer]
    @State private var pendingKill: PendingKill?

    var body: some View {
        VStack(spacing: 0) {
            HeaderView(query: $query, visibleRows: visibleRows)
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 420)
        .onAppear { monitor.setPanelOpen(true) }
        .onDisappear { monitor.setPanelOpen(false) }
        .confirmationDialog(
            pendingKill?.title ?? "",
            isPresented: Binding(get: { pendingKill != nil }, set: { if !$0 { pendingKill = nil } }),
            presenting: pendingKill
        ) { pending in
            Button("Dừng", role: .destructive) {
                Task { await monitor.kill(pending.row, wholeGroup: pending.wholeGroup, force: pending.force) }
            }
        } message: { pending in
            Text(pending.message)
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
            ContentUnavailableView("Không đọc được danh sách cổng", systemImage: "exclamationmark.triangle",
                                   description: Text(error))
                .frame(height: 200)
        } else if visibleRows.isEmpty {
            ContentUnavailableView(query.isEmpty ? "Không có cổng nào đang mở" : "Không tìm thấy",
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
                    PortRowView(row: row, isSystem: group == .system) { pendingKill = $0 }
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            if let updated = monitor.lastUpdated {
                Text("Cập nhật \(updated.formatted(date: .omitted, time: .standard))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Thoát") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }
}
