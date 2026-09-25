import Foundation

/// An agent's state as Orca derives it from the agent's own hooks (prompt submitted, tool use,
/// permission request, stop). Far more precise than tree CPU, which drops to ~0 while the agent
/// waits for the model.
struct OrcaAgentState: Sendable, Equatable {
    enum Phase: String, Sendable {
        case working
        /// Waiting for the user: a permission prompt or a question.
        case blocked
        case done
        case idle
    }

    let phase: Phase
    let startedAt: Date
    /// Last hook event Orca received for this pane.
    let lastEventAt: Date
}

/// Reads `~/Library/Application Support/Orca/agent-hooks/last-status.json`, keyed by the pane key
/// Orca also exports to the agent as `ORCA_PANE_KEY`. The file is re-parsed only when it changes.
/// Only the state fields are decoded; prompts and messages in the file are ignored.
struct OrcaStatusReader: Sendable {
    static let defaultURL = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Library/Application Support/Orca/agent-hooks/last-status.json")

    let url: URL
    private var modifiedAt: Date?
    private var cached: [String: OrcaAgentState] = [:]

    init(url: URL = Self.defaultURL) {
        self.url = url
    }

    mutating func states() -> [String: OrcaAgentState] {
        let modified = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        guard let modified else {
            modifiedAt = nil
            cached = [:]
            return cached
        }
        if modified != modifiedAt, let data = try? Data(contentsOf: url) {
            modifiedAt = modified
            cached = Self.parse(data)
        }
        return cached
    }

    private struct File: Decodable {
        struct Entry: Decodable {
            struct Payload: Decodable { let state: String? }
            let payload: Payload?
            let stateStartedAt: Double?
            let receivedAt: Double?
        }
        let entries: [String: Entry]
    }

    static func parse(_ data: Data) -> [String: OrcaAgentState] {
        guard let file = try? JSONDecoder().decode(File.self, from: data) else { return [:] }
        return file.entries.compactMapValues { entry in
            guard let phase = entry.payload?.state.flatMap(OrcaAgentState.Phase.init(rawValue:)),
                  let started = entry.stateStartedAt else { return nil }
            let received = entry.receivedAt ?? started
            return OrcaAgentState(
                phase: phase, startedAt: Date(timeIntervalSince1970: started / 1000),
                lastEventAt: Date(timeIntervalSince1970: max(started, received) / 1000))
        }
    }
}
