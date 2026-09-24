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
