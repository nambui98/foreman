/// Merges sockets and process details into one sorted row per PID.
enum RowBuilder {
    static func rows(
        sockets: [ListeningSocket],
        details: [Int32: ProcessDetails],
        cpuPercent: [Int32: Double],
        currentUID: UInt32,
        home: String
    ) -> [PortRow] {
        let byPID = Dictionary(grouping: sockets, by: \.pid)
        let rows = byPID.map { pid, sockets -> PortRow in
            let info = details[pid]
            let name = sockets.first?.command ?? "?"
            let uid = info?.uid ?? sockets.first?.uid
            return PortRow(
                pid: pid,
                name: name,
                ports: Array(Set(sockets.map(\.port))).sorted(),
                commandLine: commandLine(info?.arguments ?? []),
                cwd: info?.cwd,
                executablePath: info?.executablePath,
                pgid: info?.pgid,
                cpuPercent: cpuPercent[pid],
                memoryBytes: info?.memoryBytes,
                group: ProcessClassifier.group(
                    name: name, executablePath: info?.executablePath, uid: uid,
                    currentUID: currentUID, home: home),
                isKillable: uid == currentUID
            )
        }
        return rows.sorted { ($0.group, $0.ports.first ?? 0, $0.pid) < ($1.group, $1.ports.first ?? 0, $1.pid) }
    }

    /// `/opt/…/bin/node /path/vite --port 5173` → `node /path/vite --port 5173`.
    static func commandLine(_ arguments: [String]) -> String? {
        guard let first = arguments.first else { return nil }
        let program = first.split(separator: "/").last.map(String.init) ?? first
        return ([program] + arguments.dropFirst()).joined(separator: " ")
    }
}
