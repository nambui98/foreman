/// Merges sockets and process details into one sorted row per PID.
enum RowBuilder {
    static func rows(
        sockets: [ListeningSocket],
        details: [Int32: ProcessDetails],
        cpuPercent: [Int32: Double],
        currentUID: UInt32,
        home: String,
        owners: [Int32: String] = [:],
        established: [Int32: [Int]] = [:],
        startSec: [Int32: UInt64] = [:]
    ) -> [PortRow] {
        let byPID = Dictionary(grouping: sockets, by: \.pid)
        let rows = byPID.map { pid, sockets -> PortRow in
            let info = details[pid]
            let name = sockets.first?.command ?? "?"
            let uid = info?.uid ?? sockets.first?.uid
            let ports = Array(Set(sockets.map(\.port))).sorted()
            return PortRow(
                pid: pid,
                name: name,
                ports: ports,
                commandLine: commandLine(info?.arguments ?? []),
                cwd: info?.cwd,
                executablePath: info?.executablePath,
                pgid: info?.pgid,
                cpuPercent: cpuPercent[pid],
                memoryBytes: info?.memoryBytes,
                group: ProcessClassifier.group(
                    name: name, executablePath: info?.executablePath, uid: uid,
                    currentUID: currentUID, home: home),
                isKillable: uid == currentUID,
                owner: owners[pid],
                // Outbound connections (the process as a client) have a local port it does not listen on.
                inboundConnections: established[pid, default: []].count(where: ports.contains),
                startSec: startSec[pid],
                gitBranch: info?.gitBranch,
                project: info?.repository?.name,
                projectSubpath: info.flatMap { info in info.cwd.flatMap { info.repository?.subpath(of: $0) } },
                framework: FrameworkDetector.detect(arguments: info?.arguments ?? [], name: name)
            )
        }
        // Dev servers of the same project sit together; everything else stays in port order.
        return rows.sorted {
            let lhsProject = $0.group == .dev ? ($0.project ?? "~").lowercased() : ""
            let rhsProject = $1.group == .dev ? ($1.project ?? "~").lowercased() : ""
            return ($0.group, lhsProject, $0.ports.first ?? 0, $0.pid) < ($1.group, rhsProject, $1.ports.first ?? 0, $1.pid)
        }
    }

    /// `/opt/…/bin/node /path/vite --port 5173` → `node /path/vite --port 5173`.
    static func commandLine(_ arguments: [String]) -> String? {
        guard let first = arguments.first else { return nil }
        let program = first.split(separator: "/").last.map(String.init) ?? first
        return ([program] + arguments.dropFirst()).joined(separator: " ")
    }
}
