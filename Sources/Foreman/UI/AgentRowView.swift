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
                      : agent.status.title + " · "
                        + (agent.orcaState != nil ? String(localized: "from Orca") : String(localized: "estimated from CPU")))
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
                Button("Open terminal (\(terminal.appName))") { Task { await monitor.jumpToTerminal(agent) } }
            }
            Button("Copy PID") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(String(agent.pid), forType: .string)
            }
            if let cwd = agent.cwd {
                if let editor = EditorLauncher.preferred(bundleID: settings.editorBundleID) {
                    Button("Open in \(editor.name)") { EditorLauncher.open(folder: cwd, in: editor) }
                }
                Button("Show in Finder") {
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

    /// `Orca · ttys003 · 1d 15h · 4 child processes`
    private var context: String {
        let uptime = Formatters.uptime(seconds: Int(Date().timeIntervalSince1970) - Int(agent.startSec))
        return [agent.host, agent.tty, uptime, String(localized: "\(agent.childCount) child processes")]
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
            case .app: String(localized: "Open \(locator.appName) (tab unknown)")
            default: String(localized: "Open the agent's terminal tab in \(locator.appName)")
            }
        } ?? String(localized: "Terminal not found"))
    }

    @ViewBuilder private var pauseControl: some View {
        if agent.status == .paused {
            Button { Task { await monitor.resume(agent) } } label: {
                Image(systemName: "play.circle").font(.title3)
            }
            .buttonStyle(.borderless)
            .help("Resume the child processes")
        } else {
            Button { Task { await monitor.pause(agent) } } label: {
                Image(systemName: "pause.circle").font(.title3)
            }
            .buttonStyle(.borderless)
            .disabled(agent.childCount == 0)
            .help(agent.childCount == 0
                  ? String(localized: "No child processes to pause")
                  : String(localized: "Pause the child processes (commands, MCP, dev servers). The agent keeps running; a command it waits on may time out."))
        }
    }

    @ViewBuilder private var stopControl: some View {
        switch state {
        case .terminating:
            ProgressView().controlSize(.small)
        case .needsForce:
            Button("Force") { Task { await monitor.stop(agent, force: true) } }
                .buttonStyle(.borderedProminent).tint(.red).controlSize(.small)
                .help("Still running after SIGTERM — send SIGKILL")
        default:
            Button {
                requestStop(PendingAgentStop(agent: agent, members: monitor.stopPreview(agent)))
            } label: {
                Image(systemName: "xmark.circle.fill").font(.title3)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.red)
            .help("Stop the agent and all its child processes")
        }
    }
}

/// A stop waiting for confirmation, with the processes it will signal.
struct PendingAgentStop: Identifiable {
    let agent: AgentRow
    let members: [String]
    var id: Int32 { agent.pid }

    var title: String { String(localized: "Stop \(agent.label)?") }

    var message: String {
        let shown = members.prefix(8).joined(separator: ", ")
        let more = members.count > 8 ? String(localized: " and \(members.count - 8) more") : ""
        var text = String(localized: "Will send SIGTERM to \(members.count) processes: \(shown)\(more).")
        if let hint = agent.kind.resumeHint {
            text += "\n\n" + String(localized: "Reopen the session later with: \(hint)")
        }
        return text
    }
}
