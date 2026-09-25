import AppKit
import SwiftUI

/// One agent: status, project, host/tty/uptime, tree CPU/RAM, pause/resume and stop.
struct AgentRowView: View {
    @Environment(PortMonitor.self) private var monitor
    @Environment(AppSettings.self) private var settings
    let agent: AgentRow
    let requestStop: (PendingAgentStop) -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(statusColor).frame(width: 8, height: 8).padding(.top, 6)
                .help(agent.status == .paused ? agent.status.title
                      : agent.status.title + (agent.orcaState != nil ? " · theo Orca" : " · ước lượng theo CPU"))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(agent.kind.displayName).font(.system(.body, weight: .medium)).lineLimit(1)
                    if let member = agent.teamMember {
                        Text(member).font(.caption).foregroundStyle(.tint).lineLimit(1)
                    }
                    Text(verbatim: String(agent.pid)).font(.caption2).foregroundStyle(.tertiary).monospacedDigit()
                    if agent.status == .paused || agent.status == .waiting {
                        Text(agent.status.title).font(.caption2.weight(.semibold))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(statusColor.opacity(0.2), in: .capsule).foregroundStyle(statusColor)
                    }
                }
                if let cwd = Formatters.abbreviatePath(agent.cwd) {
                    HStack(spacing: 4) {
                        Text(cwd).lineLimit(1).truncationMode(.middle)
                        if let branch = agent.gitBranch {
                            BranchLabel(branch: branch)
                        }
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
                Text(context).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                if case .failed(let message) = state {
                    Text(message).font(.caption).foregroundStyle(.red)
                        .onTapGesture { monitor.dismissAgentError(pid: agent.pid) }
                }
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 2) {
                Text(Formatters.cpu(agent.cpuPercent))
                Text(Formatters.memory(agent.memoryBytes)).foregroundStyle(.secondary)
            }
            .font(.caption).monospacedDigit()
            jumpControl
            pauseControl
            stopControl.frame(width: 44)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(isHovering ? Color.primary.opacity(0.06) : .clear, in: .rect(cornerRadius: 6))
        .onHover { isHovering = $0 }
        .contextMenu {
            if let terminal = agent.terminal {
                Button("Mở terminal (\(terminal.appName))") { Task { await monitor.jumpToTerminal(agent) } }
            }
            Button("Copy PID") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(String(agent.pid), forType: .string)
            }
            if let cwd = agent.cwd {
                if let editor = EditorLauncher.preferred(bundleID: settings.editorBundleID) {
                    Button("Mở trong \(editor.name)") { EditorLauncher.open(folder: cwd, in: editor) }
                }
                Button("Mở thư mục trong Finder") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: cwd, isDirectory: true))
                }
            }
        }
    }

    private var state: KillState? { monitor.agentStates[agent.pid] }

    private var statusColor: Color {
        switch agent.status {
        case .waiting: .yellow
        case .working: .green
        case .idle: .secondary
        case .paused: .orange
        }
    }

    /// `Orca · ttys003 · 1d 15h · 4 tiến trình con`
    private var context: String {
        let uptime = Formatters.uptime(seconds: Int(Date().timeIntervalSince1970) - Int(agent.startSec))
        return [agent.host, agent.tty, uptime, "\(agent.childCount) tiến trình con"]
            .compactMap { $0 }.joined(separator: " · ")
    }

    private var jumpControl: some View {
        Button { Task { await monitor.jumpToTerminal(agent) } } label: {
            Image(systemName: "arrow.up.forward.app").font(.title3)
        }
        .buttonStyle(.borderless)
        .disabled(agent.terminal == nil)
        .help(agent.terminal.map { locator in
            switch locator {
            case .app: "Mở \(locator.appName) (không xác định được tab)"
            default: "Mở tab terminal của agent trong \(locator.appName)"
            }
        } ?? "Không xác định được terminal")
    }

    @ViewBuilder private var pauseControl: some View {
        if agent.status == .paused {
            Button { Task { await monitor.resume(agent) } } label: {
                Image(systemName: "play.circle").font(.title3)
            }
            .buttonStyle(.borderless)
            .help("Chạy tiếp các tiến trình con")
        } else {
            Button { Task { await monitor.pause(agent) } } label: {
                Image(systemName: "pause.circle").font(.title3)
            }
            .buttonStyle(.borderless)
            .disabled(agent.childCount == 0)
            .help(agent.childCount == 0
                  ? "Không có tiến trình con để tạm dừng"
                  : "Tạm dừng các tiến trình con (lệnh, MCP, dev server). Agent vẫn chạy; lệnh đang chờ có thể timeout.")
        }
    }

    @ViewBuilder private var stopControl: some View {
        switch state {
        case .terminating:
            ProgressView().controlSize(.small)
        case .needsForce:
            Button("Force") { Task { await monitor.stop(agent, force: true) } }
                .buttonStyle(.borderedProminent).tint(.red).controlSize(.small)
                .help("Vẫn còn chạy sau SIGTERM — gửi SIGKILL")
        default:
            Button {
                requestStop(PendingAgentStop(agent: agent, members: monitor.stopPreview(agent)))
            } label: {
                Image(systemName: "xmark.circle.fill").font(.title3)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.red)
            .help("Dừng agent và toàn bộ tiến trình con")
        }
    }
}

/// A stop waiting for confirmation, with the processes it will signal.
struct PendingAgentStop: Identifiable {
    let agent: AgentRow
    let members: [String]
    var id: Int32 { agent.pid }

    var title: String { "Dừng \(agent.label)?" }

    var message: String {
        let shown = members.prefix(8).joined(separator: ", ")
        let more = members.count > 8 ? " và \(members.count - 8) tiến trình khác" : ""
        var text = "Sẽ gửi SIGTERM tới \(members.count) tiến trình: \(shown)\(more)."
        if let hint = agent.kind.resumeHint {
            text += "\n\nMở lại phiên sau bằng: \(hint)"
        }
        return text
    }
}
