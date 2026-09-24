/// Parses `lsof -F pcun` field output into sockets.
///
/// Each line starts with a one-letter field id: `p` pid (starts a process set),
/// `c` command, `u` uid, `n` name (`addr:port`). Unknown fields (`f`, `t`, …) are ignored.
enum LsofParser {
    static func parse(_ output: String) -> [ListeningSocket] {
        var sockets: [ListeningSocket] = []
        var seen = Set<String>()
        var pid: Int32?
        var command = ""
        var uid: UInt32?

        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let field = line.first else { continue }
            let value = line.dropFirst()
            switch field {
            case "p":
                pid = Int32(value)
                command = ""
                uid = nil
            case "c":
                command = String(value)
            case "u":
                uid = UInt32(value)
            case "n":
                guard let pid, let (address, port) = splitAddress(value) else { continue }
                // The same socket is often listed once per file descriptor.
                guard seen.insert("\(pid)|\(address)|\(port)").inserted else { continue }
                sockets.append(ListeningSocket(pid: pid, command: command, uid: uid, address: address, port: port))
            default:
                continue
            }
        }
        return sockets
    }

    /// `*:3000` → (`*`, 3000); `[::1]:5432` → (`[::1]`, 5432). The port is after the last colon.
    static func splitAddress(_ name: Substring) -> (String, Int)? {
        // Connected sockets look like `a:1->b:2`; only the local side matters.
        let local = name.split(separator: "->").first ?? name
        guard let colon = local.lastIndex(of: ":"), let port = Int(local[local.index(after: colon)...]) else {
            return nil
        }
        return (String(local[..<colon]), port)
    }
}
