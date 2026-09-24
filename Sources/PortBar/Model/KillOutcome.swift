/// Result of delivering a signal and waiting for the process to exit.
enum KillOutcome: Equatable, Sendable {
    case exited
    case stillRunning
    case notPermitted
    case notFound
    /// Target rejected by a safety guard before any signal was sent.
    case refused(String)
}
