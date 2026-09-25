/// One listening TCP socket as reported by `lsof`.
struct ListeningSocket: Hashable, Sendable {
    let pid: Int32
    /// Full command name (`lsof +c 0`), e.g. `ControlCenter`, `next-server`.
    let command: String
    let uid: UInt32?
    /// Bound address without the port, e.g. `*`, `127.0.0.1`, `[::1]`.
    let address: String
    let port: Int
}
