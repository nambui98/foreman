import Foundation

/// Where an agent's terminal lives, precise enough to focus that exact tab when the host allows it.
enum TerminalLocator: Sendable, Equatable {
    /// Orca terminal tab, focused with `orca terminal switch --terminal <handle>`.
    case orca(handle: String)
    /// Terminal.app tab, matched by tty (`/dev/ttys003`) via AppleScript.
    case appleTerminal(tty: String)
    /// iTerm2 session, matched by tty via AppleScript.
    case iTerm(tty: String)
    /// Any other host app: can only be brought to the front.
    case app(name: String)

    /// Picks the most precise locator from the agent's environment, falling back to the host app.
    static func resolve(environment: [String: String], host: String?, tty: String?) -> TerminalLocator? {
        let devicePath = tty.map { "/dev/\($0)" }.flatMap { isValidTTY($0) ? $0 : nil }
        switch environment["TERM_PROGRAM"] {
        case "Orca":
            if let handle = environment["ORCA_TERMINAL_HANDLE"], isValidOrcaHandle(handle) {
                return .orca(handle: handle)
            }
        case "Apple_Terminal":
            if let devicePath { return .appleTerminal(tty: devicePath) }
        case "iTerm.app":
            if let devicePath { return .iTerm(tty: devicePath) }
        default:
            break
        }
        return host.map { .app(name: $0) }
    }

    /// `term_` + UUID, as issued by Orca. Validated before it reaches the CLI's argv.
    static func isValidOrcaHandle(_ handle: String) -> Bool {
        handle.wholeMatch(of: /term_[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/) != nil
    }

    /// `/dev/ttysNNN` only, since the value is interpolated into AppleScript source.
    static func isValidTTY(_ path: String) -> Bool {
        path.wholeMatch(of: /\/dev\/ttys[0-9]{1,4}/) != nil
    }

    /// Name of the app that will come to the front, for tooltips and errors.
    var appName: String {
        switch self {
        case .orca: "Orca"
        case .appleTerminal: "Terminal"
        case .iTerm: "iTerm"
        case .app(let name): name
        }
    }
}
