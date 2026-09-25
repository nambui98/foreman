import SwiftUI

/// A container under the OrbStack / Docker row that publishes its ports: name, image, port
/// mappings, restart and (confirmed) stop.
struct ContainerRowView: View {
    @Environment(PortMonitor.self) private var monitor
    let container: Container
    let confirm: (Confirmation) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(.green).frame(width: 6, height: 6)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(verbatim: container.name).font(.callout.weight(.medium)).lineLimit(1)
                    if let project = container.composeProject {
                        Text(verbatim: project).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Text(verbatim: details).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                if case .failed(let message) = state {
                    Text(message).font(.caption).foregroundStyle(.red)
                        .onTapGesture { monitor.dismissContainerError(id: container.id) }
                }
            }
            Spacer(minLength: 4)
            if state == .terminating {
                ProgressView().controlSize(.small)
            } else {
                Button { Task { await monitor.perform(.restart, on: container) } } label: {
                    Image(systemName: "arrow.clockwise.circle")
                }
                .buttonStyle(.borderless)
                .help("Restart container")
                Button {
                    confirm(Confirmation(
                        title: String(localized: "Stop container \(container.name)?"),
                        message: String(localized: "Runs docker stop. Start it again with docker start or docker compose up.")
                    ) {
                        await monitor.perform(.stop, on: container)
                    })
                } label: {
                    Image(systemName: "stop.circle.fill")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.red)
                .help("Stop container")
            }
        }
        .font(.title3)
        .padding(.leading, 78).padding(.trailing, 12).padding(.vertical, 3)
    }

    private var state: KillState? { monitor.containerStates[container.id] }

    /// `postgres:16 · :5434→5432`
    private var details: String {
        let ports = container.ports.map { ":\($0.host)→\($0.container)" }.joined(separator: " ")
        return [container.image, ports].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}
