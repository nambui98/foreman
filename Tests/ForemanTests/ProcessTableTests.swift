import Darwin
import Foundation
import Testing
@testable import Foreman

func entry(_ pid: Int32, _ ppid: Int32, _ name: String = "p", uid: UInt32 = 501) -> ProcessEntry {
    ProcessEntry(pid: pid, ppid: ppid, pgid: pid, uid: uid, name: name, startSec: UInt64(pid),
                 flags: 0, ttyDevice: UInt32.max)
}

struct ProcessTableTests {
    //  1 ─ 10 ─ 20 ─ 30
    //         └ 21
    static let table = ProcessTable(entries: [entry(1, 0), entry(10, 1), entry(20, 10), entry(21, 10), entry(30, 20)])

    @Test func descendantsAreBreadthFirstAndExcludeRoot() {
        #expect(Self.table.descendants(of: 10).sorted() == [20, 21, 30])
        #expect(Self.table.descendants(of: 30).isEmpty)
    }

    @Test func ancestorsStopAtLaunchd() {
        #expect(Self.table.ancestors(of: 30) == [20, 10])
        #expect(Self.table.ancestors(of: 10).isEmpty)
    }

    @Test func cyclesDoNotLoop() {
        let cyclic = ProcessTable(entries: [entry(5, 6), entry(6, 5)])
        #expect(cyclic.descendants(of: 5) == [6])
        #expect(cyclic.ancestors(of: 5) == [6])
    }

    @Test func liveSnapshotLinksChildToUs() async throws {
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/sleep")
        child.arguments = ["5"]
        try child.run()
        defer { child.terminate() }
        let table = ProcessTable.snapshot()
        #expect(table.entries[getpid()]?.ppid == getppid())
        #expect(table.ancestors(of: child.processIdentifier).first == getpid())
        #expect(table.descendants(of: getpid()).contains(child.processIdentifier))
    }
}
