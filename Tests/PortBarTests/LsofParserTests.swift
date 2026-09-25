import Testing
@testable import PortBar

struct LsofParserTests {
    /// Trimmed from real `lsof +c 0 -nP -iTCP -sTCP:LISTEN -F pcun` output on macOS 26.
    static let fixture = """
    p685
    crapportd
    u501
    f10
    n*:62504
    f11
    n*:62504
    f19
    n*:54726
    p2316
    cpostgres
    u501
    f7
    n[::1]:5432
    f8
    n127.0.0.1:5432
    p30601
    cbun
    u501
    f1670
    n*:3000
    """

    @Test func parsesEveryProcessAndDedupesRepeatedDescriptors() {
        let sockets = LsofParser.parse(Self.fixture)
        #expect(sockets.count == 5)
        #expect(sockets.filter { $0.pid == 685 }.map(\.port) == [62504, 54726])
        #expect(sockets.first { $0.pid == 30601 } == ListeningSocket(
            pid: 30601, command: "bun", uid: 501, address: "*", port: 3000))
    }

    @Test func keepsIPv4AndIPv6BindingsOfSamePort() {
        let postgres = LsofParser.parse(Self.fixture).filter { $0.pid == 2316 }
        #expect(postgres.map(\.address) == ["[::1]", "127.0.0.1"])
        #expect(Set(postgres.map(\.port)) == [5432])
    }

    @Test(arguments: [
        ("*:3000", "*", 3000),
        ("[::1]:5432", "[::1]", 5432),
        ("127.0.0.1:8000", "127.0.0.1", 8000),
        ("[fe80::1%lo0]:631", "[fe80::1%lo0]", 631),
        ("127.0.0.1:5000->127.0.0.1:61234", "127.0.0.1", 5000),
    ])
    func splitsAddressAndPort(name: String, address: String, port: Int) throws {
        let split = try #require(LsofParser.splitAddress(Substring(name)))
        #expect(split.0 == address)
        #expect(split.1 == port)
    }

    @Test func ignoresMalformedAndEmptyInput() {
        #expect(LsofParser.parse("").isEmpty)
        #expect(LsofParser.parse("n*:3000\n").isEmpty)  // name before any pid
        #expect(LsofParser.parse("p1\ncx\nn*:notaport\n").isEmpty)
    }
}

struct LsofScanTests {
    @Test func splitsListeningAndEstablished() {
        let output = """
        p501
        cnode
        u501
        f20
        n*:3000
        TST=LISTEN
        TQR=0
        f21
        n127.0.0.1:3000->127.0.0.1:61000
        TST=ESTABLISHED
        f22
        n192.168.1.2:61001->1.2.3.4:443
        TST=ESTABLISHED
        f23
        n[::1]:3000
        TST=CLOSE_WAIT
        p777
        cpostgres
        u501
        f5
        n127.0.0.1:5432
        """
        let scan = LsofParser.scan(output)
        #expect(scan.listening.map(\.port) == [3000, 5432])
        #expect(scan.established[501] == [3000, 61001])
        #expect(scan.established[777] == nil)
    }

    @Test func inboundCountsOnlyListeningPorts() {
        let sockets = [ListeningSocket(pid: 501, command: "node", uid: 501, address: "*", port: 3000)]
        let rows = RowBuilder.rows(
            sockets: sockets, details: [:], cpuPercent: [:], currentUID: 501, home: "/Users/me",
            established: [501: [3000, 3000, 61001]], startSec: [501: 1_700_000_000])
        #expect(rows.first?.inboundConnections == 2)
        #expect(rows.first?.startSec == 1_700_000_000)
    }
}
