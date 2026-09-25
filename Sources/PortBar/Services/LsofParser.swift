/// Listening sockets plus inbound connection counts from one lsof pass.
struct LsofScan: Sendable, Equatable {
    var listening: [ListeningSocket] = []
    /// Local ports of ESTABLISHED sockets per pid (both directions; callers keep the ones whose
    /// local port is one the process listens on, i.e. inbound connections).
    var established: [Int32: [Int]] = [:]
}

/// Parses `lsof -F pcunT` field output.
///
/// Each line starts with a one-letter field id: `p` pid (starts a process set), `c` command,
/// `u` uid, `f` file descriptor (starts a file set), `n` name (`addr:port` or `a:1->b:2`),
/// `T` TCP info (`TST=LISTEN`). A name without a `TST=` field counts as listening, which is what
/// `-sTCP:LISTEN` alone produces.
enum LsofParser {
    static func parse(_ output: String) -> [ListeningSocket] {
        scan(output).listening
    }

    static func scan(_ output: String) -> LsofScan {
        var result = LsofScan()
        var seen = Set<String>()
        var pid: Int32?
        var command = ""
        var uid: UInt32?
        var pendingName: Substring?
        var pendingState: Substring?

        func flush() {
            defer { pendingName = nil; pendingState = nil }
            guard let pid, let name = pendingName, let (address, port) = splitAddress(name) else { return }
            switch pendingState ?? "LISTEN" {
            case "LISTEN":
                // The same socket is often listed once per file descriptor.
                guard seen.insert("\(pid)|\(address)|\(port)").inserted else { return }
                result.listening.append(ListeningSocket(pid: pid, command: command, uid: uid, address: address, port: port))
            case "ESTABLISHED":
                result.established[pid, default: []].append(port)
            default:
                return
            }
        }

        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let field = line.first else { continue }
            let value = line.dropFirst()
            switch field {
            case "p":
                flush()
                pid = Int32(value)
                command = ""
                uid = nil
            case "c":
                command = String(value)
            case "u":
                uid = UInt32(value)
            case "f":
                flush()
            case "n":
                flush()
                pendingName = value
            case "T":
                if value.hasPrefix("ST=") { pendingState = value.dropFirst(3) }
            default:
                continue
            }
        }
        flush()
        return result
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
