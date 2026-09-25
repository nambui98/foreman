import AppKit
import SwiftUI

/// One process row: ports, name, command/cwd, CPU/RAM and kill actions.
struct PortRowView: View {
    @Environment(PortMonitor.self) private var monitor
    @Environment(AppSettings.self) private var settings
    let row: PortRow
    /// System-section rows confirm every kill; all rows confirm whole-group kills.
    let isSystem: Bool
    let requestConfirmation: (PendingKill) -> Void
    @State private var isHovering = false
    @State private var probes: [Int: ProbeResult] = [:]

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            portChips
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(row.name).font(.system(.body, weight: .medium)).lineLimit(1)
                    Text(verbatim: String(row.pid)).font(.caption2).foregroundStyle(.tertiary).monospacedDigit()
                    ForEach(row.flags.sorted(by: { $0.isOrphan && !$1.isOrphan }), id: \.self) { flag in
                        FlagBadge(flag: flag, row: row)
                    }
                    if row.inboundConnections > 0 {
                        Label("\(row.inboundConnections)", systemImage: "arrow.left.arrow.right")
                            .font(.caption2).foregroundStyle(.secondary).labelStyle(.titleAndIcon)
                            .help("\(row.inboundConnections) open connections to this process")
                    }
                }
                if let detail = Formatters.abbreviatePath(row.cwd) ?? row.commandLine {
                    HStack(spacing: 4) {
                        Text(detail).lineLimit(1).truncationMode(.middle)
                        if let branch = row.gitBranch {
                            BranchLabel(branch: branch)
                        }
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
                if let owner = row.owner {
                    Label(owner, systemImage: "sparkles").font(.caption2).foregroundStyle(.tint)
                        .lineLimit(1)
                }
                if case .failed(let message) = killState {
                    Text(message).font(.caption).foregroundStyle(.red)
                        .onTapGesture { monitor.dismissError(pid: row.pid) }
                }
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 2) {
                Text(Formatters.cpu(row.cpuPercent))
                Text(Formatters.memory(row.memoryBytes)).foregroundStyle(.secondary)
            }
            .font(.caption).monospacedDigit()
            openControl
            killControl.frame(width: 44)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(isHovering ? Color.primary.opacity(0.06) : .clear, in: .rect(cornerRadius: 6))
        .onHover { hovering in
            isHovering = hovering
            if hovering { probePorts() }
        }
        .help(row.commandLine ?? row.executablePath ?? row.name)
        .contextMenu { contextMenu }
    }

    private var killState: KillState? { monitor.killStates[row.pid] }

    private var portChips: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(row.ports.prefix(3), id: \.self) { port in
                Text(verbatim: String(port))
                    .font(.system(.caption, design: .monospaced, weight: .semibold))
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(.tint.opacity(0.15), in: .capsule)
            }
            if row.ports.count > 3 {
                Text("+\(row.ports.count - 3)").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(width: 56, alignment: .leading)
    }

    /// Quick look: open the port in the default browser (a menu when the process has several ports).
    @ViewBuilder private var openControl: some View {
        if row.ports.count == 1, let port = row.ports.first {
            Button { Self.openInBrowser(port) } label: {
                Image(systemName: "safari").font(.title3)
            }
            .buttonStyle(.borderless)
            .help(String(localized: "Open http://localhost:\(String(port))") + (probes[port].map { "\n\($0.summary)" } ?? ""))
        } else {
            Menu {
                ForEach(row.ports, id: \.self) { port in
                    Button("localhost:\(String(port))" + (probes[port].map { " — \($0.summary)" } ?? "")) {
                        Self.openInBrowser(port)
                    }
                }
            } label: {
                Image(systemName: "safari").font(.title3)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Open in browser")
        }
    }

    static func openInBrowser(_ port: Int) {
        if let url = URL(string: "http://localhost:\(port)") { NSWorkspace.shared.open(url) }
    }

    @ViewBuilder private var killControl: some View {
        switch killState {
        case .terminating:
            ProgressView().controlSize(.small)
        case .needsForce:
            Button("Force") { perform(force: true) }
                .buttonStyle(.borderedProminent).tint(.red).controlSize(.small)
                .help("Still running after SIGTERM — send SIGKILL")
        default:
            Button {
                // ⌥-click skips the grace period and sends SIGKILL.
                perform(force: NSEvent.modifierFlags.contains(.option))
            } label: {
                Image(systemName: "xmark.circle.fill").font(.title3)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(row.isKillable ? .red : .secondary)
            .disabled(!row.isKillable)
            .help(row.isKillable ? String(localized: "Stop (SIGTERM) · ⌥-click: SIGKILL")
                                 : String(localized: "Another user's process — not permitted"))
        }
    }

    @ViewBuilder private var contextMenu: some View {
        if row.isKillable {
            Button("Stop (SIGTERM)") { perform(force: false) }
            Button("Force Kill (SIGKILL)") { perform(force: true) }
            Button("Stop the whole process group") { perform(force: false, wholeGroup: true) }
            Divider()
        }
        ForEach(row.ports, id: \.self) { port in
            Button("Open localhost:\(String(port))") { Self.openInBrowser(port) }
        }
        Button("Copy PID") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(String(row.pid), forType: .string)
        }
        if let cwd = row.cwd, cwd != "/" {
            if let editor = EditorLauncher.preferred(bundleID: settings.editorBundleID) {
                Button("Open in \(editor.name)") { EditorLauncher.open(folder: cwd, in: editor) }
            }
            Button("Show in Finder") {
                NSWorkspace.shared.open(URL(fileURLWithPath: cwd, isDirectory: true))
            }
        }
    }

    /// Hovering a dev row looks at what its ports serve (cached 30s, 1.5s timeout, off the main actor).
    private func probePorts() {
        guard row.group == .dev else { return }
        for port in row.ports.prefix(3) where probes[port] == nil {
            Task { probes[port] = await PortProbe.shared.probe(port: port) }
        }
    }

    private func perform(force: Bool, wholeGroup: Bool = false) {
        var members: [String] = []
        if wholeGroup {
            switch ProcessKiller.groupMembers(of: row.pid) {
            case .success(let list): members = list
            case .failure(let refusal):
                monitor.fail(pid: row.pid, refusal.message)
                return
            }
        }
        if wholeGroup || isSystem {
            requestConfirmation(PendingKill(row: row, force: force, wholeGroup: wholeGroup, members: members))
        } else {
            Task { await monitor.kill(row, wholeGroup: false, force: force) }
        }
    }
}

/// `orphan` / `idle 5h` capsule; the tooltip gives the reason.
struct FlagBadge: View {
    let flag: RowFlag
    let row: PortRow

    var body: some View {
        Text(text).font(.caption2.weight(.semibold))
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(color.opacity(0.2), in: .capsule).foregroundStyle(color)
            .help(flag.reason)
    }

    private var text: String {
        guard flag == .idle, let started = row.startSec else { return flag.title }
        let age = Int(Date().timeIntervalSince1970) - Int(started)
        return "\(flag.title) \(Formatters.uptime(seconds: age))"
    }

    private var color: Color { flag.isOrphan ? .orange : .secondary }
}

/// A kill waiting for user confirmation.
struct PendingKill: Identifiable {
    let row: PortRow
    let force: Bool
    let wholeGroup: Bool
    /// `name (PID)` of every process a group kill will signal.
    let members: [String]
    var id: Int32 { row.pid }

    var message: String {
        guard wholeGroup else { return String(localized: "This is a system or user app, not a dev server.") }
        let shown = members.prefix(8).joined(separator: ", ")
        let more = members.count > 8 ? String(localized: " and \(members.count - 8) more") : ""
        return String(localized: "Will stop \(members.count) processes: \(shown)\(more).")
    }

    var title: String {
        let signal = force ? "SIGKILL" : "SIGTERM"
        let target = wholeGroup ? String(localized: "the process group of \(row.name)") : "\(row.name) (PID \(row.pid))"
        return String(localized: "Send \(signal) to \(target)?")
    }
}
