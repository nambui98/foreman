import Foundation

/// An agent's state as Orca derives it from the agent's own hooks (prompt submitted, tool use,
/// permission request, stop). Far more precise than tree CPU, which drops to ~0 while the agent
/// waits for the model.
struct OrcaAgentState: Sendable, Equatable {
    enum Phase: String, Sendable, Equatable {
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
        // A read or decode failure (e.g. caught mid-write) keeps the last good snapshot and retries
        // on the next pass, since modifiedAt only advances on success.
        if modified != modifiedAt, let data = try? Data(contentsOf: url), let parsed = Self.parseFile(data) {
            modifiedAt = modified
            cached = parsed
        }
        return cached
    }

    private struct File: Decodable {
        /// Fields are decoded leniently: an entry of an unexpected shape becomes empty and is
        /// dropped, instead of failing the whole file (Orca's format is not ours).
        struct Entry: Decodable {
            let state: String?
            let stateStartedAt: Double?
            let receivedAt: Double?

            private enum Keys: String, CodingKey { case payload, stateStartedAt, receivedAt }
            private enum PayloadKeys: String, CodingKey { case state }

            init(from decoder: Decoder) throws {
                let container = try? decoder.container(keyedBy: Keys.self)
                let payload = try? container?.nestedContainer(keyedBy: PayloadKeys.self, forKey: .payload)
                state = (try? payload?.decodeIfPresent(String.self, forKey: .state)) ?? nil
                stateStartedAt = (try? container?.decodeIfPresent(Double.self, forKey: .stateStartedAt)) ?? nil
                receivedAt = (try? container?.decodeIfPresent(Double.self, forKey: .receivedAt)) ?? nil
            }
        }
        let entries: [String: Entry]
    }

    static func parse(_ data: Data) -> [String: OrcaAgentState] {
        parseFile(data) ?? [:]
    }

    /// nil when the file itself is unreadable (not JSON, no `entries`).
    static func parseFile(_ data: Data) -> [String: OrcaAgentState]? {
        guard let file = try? JSONDecoder().decode(File.self, from: data) else { return nil }
        return file.entries.compactMapValues { entry in
            guard let phase = entry.state.flatMap(OrcaAgentState.Phase.init(rawValue:)),
                  let started = entry.stateStartedAt else { return nil }
            let received = entry.receivedAt ?? started
            return OrcaAgentState(
                phase: phase, startedAt: Date(timeIntervalSince1970: started / 1000),
                lastEventAt: Date(timeIntervalSince1970: max(started, received) / 1000))
        }
    }
}
