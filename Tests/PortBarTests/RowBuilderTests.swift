import Testing
@testable import PortBar

struct RowBuilderTests {
    @Test func groupsSocketsPerPidAndSortsByGroupThenPort() {
        let sockets = [
            ListeningSocket(pid: 10, command: "ControlCenter", uid: 501, address: "*", port: 7000),
            ListeningSocket(pid: 20, command: "node", uid: 501, address: "127.0.0.1", port: 5173),
            ListeningSocket(pid: 30, command: "bun", uid: 501, address: "*", port: 3000),
            ListeningSocket(pid: 10, command: "ControlCenter", uid: 501, address: "*", port: 5000),
            ListeningSocket(pid: 40, command: "postgres", uid: 501, address: "[::1]", port: 5432),
            ListeningSocket(pid: 40, command: "postgres", uid: 501, address: "127.0.0.1", port: 5432),
        ]
        let details: [Int32: ProcessDetails] = [
            10: ProcessDetails(pid: 10, uid: 501, executablePath: "/System/Library/CoreServices/ControlCenter.app/Contents/MacOS/ControlCenter"),
            40: ProcessDetails(pid: 40, uid: 501, executablePath: "/opt/homebrew/bin/postgres", memoryBytes: 1024),
        ]
        let rows = RowBuilder.rows(sockets: sockets, details: details, cpuPercent: [20: 12.5],
                                   currentUID: 501, home: "/Users/me")

        #expect(rows.map(\.pid) == [30, 20, 40, 10])
        #expect(rows.first { $0.pid == 10 }?.ports == [5000, 7000])
        #expect(rows.first { $0.pid == 40 }?.ports == [5432])
        #expect(rows.first { $0.pid == 20 }?.cpuPercent == 12.5)
        #expect(rows.first { $0.pid == 40 }?.memoryBytes == 1024)
    }

    @Test func rowsOfOtherUsersAreNotKillable() {
        let rows = RowBuilder.rows(
            sockets: [ListeningSocket(pid: 5, command: "cupsd", uid: 0, address: "*", port: 631)],
            details: [:], cpuPercent: [:], currentUID: 501, home: "/Users/me")
        #expect(rows.first?.isKillable == false)
        #expect(rows.first?.group == .system)
    }

    @Test func commandLineUsesProgramBasename() {
        #expect(RowBuilder.commandLine(["/opt/homebrew/bin/node", "vite", "--port", "5173"]) == "node vite --port 5173")
        #expect(RowBuilder.commandLine([]) == nil)
    }
}
