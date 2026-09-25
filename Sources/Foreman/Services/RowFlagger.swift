import Foundation

/// Flags dev processes that were left behind: orphans (parent gone or folder deleted) and
/// long-idle servers. Only killable Dev rows are ever flagged; everything else is left alone.
struct RowFlagger {
    /// CPU below this counts as "doing nothing".
    static let quietCPUPercent = 0.5
    /// Idle needs this many consecutive quiet refreshes, so one quiet sample never flags a server.
    static let requiredQuietSamples = 3

    private struct Key: Hashable {
        let pid: Int32
        let startSec: UInt64?
    }

    private var quietStreak: [Key: Int] = [:]

    mutating func apply(
        to rows: [PortRow], parentPid: [Int32: Int32], now: UInt64, idleHours: Double,
        folderExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> [PortRow] {
        var streaks: [Key: Int] = [:]
        let flagged = rows.map { row -> PortRow in
            guard row.group == .dev, row.isKillable else { return row }
            var row = row
            var flags: Set<RowFlag> = []
            if parentPid[row.pid] == 1 { flags.insert(.parentExited) }
            if let cwd = row.cwd, cwd != "/", !folderExists(cwd) { flags.insert(.folderDeleted) }

            let key = Key(pid: row.pid, startSec: row.startSec)
            let age = row.startSec.map { now > $0 ? Double(now - $0) : 0 } ?? 0
            let quiet = row.inboundConnections == 0
                && (row.cpuPercent.map { $0 < Self.quietCPUPercent } ?? false)
                && age >= idleHours * 3600
            if quiet {
                streaks[key] = quietStreak[key, default: 0] + 1
                if streaks[key]! >= Self.requiredQuietSamples { flags.insert(.idle) }
            }
            row.flags = flags
            return row
        }
        quietStreak = streaks
        return flagged
    }
}
