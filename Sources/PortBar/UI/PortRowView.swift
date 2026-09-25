import AppKit
import SwiftUI

/// One process row: ports, name, command/cwd, CPU/RAM and kill actions.
struct PortRowView: View {
    @Environment(PortMonitor.self) private var monitor
    let row: PortRow
    /// System-section rows confirm every kill; all rows confirm whole-group kills.
    let isSystem: Bool
    let requestConfirmation: (PendingKill) -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            portChips
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(row.name).font(.system(.body, weight: .medium)).lineLimit(1)
                    Text(verbatim: String(row.pid)).font(.caption2).foregroundStyle(.tertiary).monospacedDigit()
                }
                if let detail = Formatters.abbreviatePath(row.cwd) ?? row.commandLine {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
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
        .onHover { isHovering = $0 }
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
            .help("Mở http://localhost:\(String(port))")
        } else {
            Menu {
                ForEach(row.ports, id: \.self) { port in
                    Button("localhost:\(String(port))") { Self.openInBrowser(port) }
                }
            } label: {
                Image(systemName: "safari").font(.title3)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Mở trong trình duyệt")
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
                .help("Vẫn còn chạy sau SIGTERM — gửi SIGKILL")
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
            .help(row.isKillable ? "Dừng (SIGTERM) · ⌥-click: SIGKILL" : "Tiến trình của user khác — không đủ quyền")
        }
    }

    @ViewBuilder private var contextMenu: some View {
        if row.isKillable {
            Button("Dừng (SIGTERM)") { perform(force: false) }
            Button("Force Kill (SIGKILL)") { perform(force: true) }
            Button("Dừng cả process group") { perform(force: false, wholeGroup: true) }
            Divider()
        }
        ForEach(row.ports, id: \.self) { port in
            Button("Mở localhost:\(String(port))") { Self.openInBrowser(port) }
        }
        Button("Copy PID") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(String(row.pid), forType: .string)
        }
        if let cwd = row.cwd, cwd != "/" {
            Button("Mở thư mục trong Finder") {
                NSWorkspace.shared.open(URL(fileURLWithPath: cwd, isDirectory: true))
            }
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

/// A kill waiting for user confirmation.
struct PendingKill: Identifiable {
    let row: PortRow
    let force: Bool
    let wholeGroup: Bool
    /// `name (PID)` of every process a group kill will signal.
    let members: [String]
    var id: Int32 { row.pid }

    var message: String {
        guard wholeGroup else { return "Đây là ứng dụng hệ thống hoặc ứng dụng người dùng, không phải dev server." }
        let shown = members.prefix(8).joined(separator: ", ")
        let more = members.count > 8 ? " và \(members.count - 8) tiến trình khác" : ""
        return "Sẽ dừng \(members.count) tiến trình: \(shown)\(more)."
    }

    var title: String {
        let signal = force ? "SIGKILL" : "SIGTERM"
        let target = wholeGroup ? "process group của \(row.name)" : "\(row.name) (PID \(row.pid))"
        return "Gửi \(signal) tới \(target)?"
    }
}
