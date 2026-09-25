import Foundation
import Testing
@testable import Foreman

struct RowFlaggerTests {
    private let now: UInt64 = 1_800_000_000

    private func row(
        pid: Int32 = 501, group: ProcessGroup = .dev, killable: Bool = true, cwd: String? = "/tmp",
        cpu: Double? = 0, inbound: Int = 0, ageHours: Double = 10
    ) -> PortRow {
        var row = PortRow(
            pid: pid, name: "node", ports: [3000], commandLine: nil, cwd: cwd, executablePath: nil, pgid: nil,
            cpuPercent: cpu, memoryBytes: nil, group: group, isKillable: killable)
        row.inboundConnections = inbound
        row.startSec = now - UInt64(ageHours * 3600)
        return row
    }

    private func flags(
        _ rows: [PortRow], parent: [Int32: Int32] = [:], samples: Int = 1, idleHours: Double = 2,
        exists: @escaping (String) -> Bool = { _ in true }
    ) -> [Set<RowFlag>] {
        var flagger = RowFlagger()
        var result: [PortRow] = []
        for _ in 0..<samples {
            result = flagger.apply(to: rows, parentPid: parent, now: now, idleHours: idleHours, folderExists: exists)
        }
        return result.map(\.flags)
    }

    @Test func parentExitedIsOrphan() {
        #expect(flags([row()], parent: [501: 1]) == [[.parentExited]])
        #expect(flags([row()], parent: [501: 400]) == [[]])
    }

    @Test func deletedFolderIsOrphan() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "foreman-worktree-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let live = row(cwd: dir.path)
        #expect(flags([live], exists: { FileManager.default.fileExists(atPath: $0) }) == [[]])
        try FileManager.default.removeItem(at: dir)
        #expect(flags([live], exists: { FileManager.default.fileExists(atPath: $0) }) == [[.folderDeleted]])
        // Processes that chdir to / are not "deleted".
        #expect(flags([row(cwd: "/")], exists: { _ in false }) == [[]])
    }

    @Test func idleNeedsThreeQuietSamplesAndAge() {
        #expect(flags([row()], samples: 2) == [[]])
        #expect(flags([row()], samples: 3) == [[.idle]])
        #expect(flags([row(ageHours: 1)], samples: 5) == [[]])
    }

    @Test func activeServersAreNeverIdle() {
        #expect(flags([row(inbound: 1)], samples: 5) == [[]])
        #expect(flags([row(cpu: 3)], samples: 5) == [[]])
        #expect(flags([row(cpu: nil)], samples: 5) == [[]])  // first sample has no CPU yet
    }

    @Test func activitySampleResetsTheStreak() {
        var flagger = RowFlagger()
        let quiet = row()
        let busy = row(inbound: 2)
        for sample in [quiet, quiet, busy, quiet, quiet] {
            let out = flagger.apply(to: [sample], parentPid: [:], now: now, idleHours: 2)
            #expect(!out[0].flags.contains(.idle))
        }
    }

    @Test func onlyKillableDevRowsAreFlagged() {
        #expect(flags([row(group: .system)], parent: [501: 1], samples: 3) == [[]])
        #expect(flags([row(group: .dataContainer)], parent: [501: 1], samples: 3) == [[]])
        #expect(flags([row(killable: false)], parent: [501: 1], samples: 3) == [[]])
    }
}
