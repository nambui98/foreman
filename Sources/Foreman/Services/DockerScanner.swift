import Foundation

/// A running Docker / OrbStack container and the host ports it publishes.
struct Container: Identifiable, Sendable, Equatable {
    struct PortMapping: Sendable, Equatable, Hashable {
        let host: Int
        let container: Int
    }

    let id: String
    let name: String
    let image: String
    /// `Up 2 days (healthy)`.
    let status: String
    /// `docker compose` project, when the container belongs to one.
    let composeProject: String?
    let ports: [PortMapping]
}

/// Lists containers with `docker ps` and stops / restarts them. Works with Docker Desktop and
/// OrbStack, whichever CLI is installed; everything is skipped when none is.
enum DockerScanner {
    /// Fixed locations only (no PATH lookup): OrbStack, Docker Desktop, Homebrew.
    static let candidates = [
        "\(NSHomeDirectory())/.orbstack/bin/docker",
        "/usr/local/bin/docker",
        "/opt/homebrew/bin/docker",
        "/Applications/Docker.app/Contents/Resources/bin/docker",
    ]

    /// Kernel names of the processes that hold published container ports on the host.
    static let hostProcessNames: Set<String> = ["OrbStack Helper", "com.docker.backend", "vpnkit-bridge", "docker-proxy"]

    static var executable: URL? {
        candidates.first { FileManager.default.isExecutableFile(atPath: $0) }.map(URL.init(fileURLWithPath:))
    }

    /// Running containers; nil when there is no CLI or the daemon did not answer in time.
    static func list() -> [Container]? {
        guard let docker = executable,
              let result = ProcessRunner.run(docker, ["ps", "--format", "{{json .}}"], timeout: .seconds(4)),
              result.status == 0 else { return nil }
        return parse(String(decoding: result.output, as: UTF8.self))
    }

    enum Action: String, Sendable {
        case stop, restart
    }

    /// Runs `docker stop|restart <id>`; true on success. Stop waits for the container's grace period.
    static func perform(_ action: Action, containerID: String) -> Bool {
        guard isValidID(containerID), let docker = executable,
              let result = ProcessRunner.run(docker, [action.rawValue, containerID], timeout: .seconds(30)) else {
            return false
        }
        return result.status == 0
    }

    /// Container ids are hex; validated before they reach the CLI's argv.
    static func isValidID(_ id: String) -> Bool {
        id.wholeMatch(of: /[0-9a-f]{12,64}/) != nil
    }

    /// One JSON object per line (`docker ps --format '{{json .}}'`).
    static func parse(_ output: String) -> [Container] {
        output.split(separator: "\n").compactMap { line in
            guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let id = object["ID"] as? String, let name = object["Names"] as? String else { return nil }
            return Container(
                id: id, name: name, image: object["Image"] as? String ?? "",
                status: object["Status"] as? String ?? "",
                composeProject: composeProject(labels: object["Labels"] as? String ?? ""),
                ports: ports(object["Ports"] as? String ?? ""))
        }
    }

    /// `0.0.0.0:5434->5432/tcp, [::]:5434->5432/tcp, 9000/tcp` → [5434→5432] (unpublished ports dropped).
    static func ports(_ field: String) -> [Container.PortMapping] {
        var seen = Set<Container.PortMapping>()
        var result: [Container.PortMapping] = []
        for part in field.split(separator: ",") {
            let sides = part.trimmingCharacters(in: .whitespaces).split(separator: "->")
            guard sides.count == 2, let colon = sides[0].lastIndex(of: ":"),
                  let host = Int(sides[0][sides[0].index(after: colon)...]),
                  let container = Int(sides[1].split(separator: "/").first ?? "") else { continue }
            let mapping = Container.PortMapping(host: host, container: container)
            if seen.insert(mapping).inserted { result.append(mapping) }
        }
        return result
    }

    static func composeProject(labels: String) -> String? {
        labels.split(separator: ",").lazy
            .compactMap { pair -> String? in
                let kv = pair.split(separator: "=", maxSplits: 1)
                return kv.count == 2 && kv[0] == "com.docker.compose.project" ? String(kv[1]) : nil
            }
            .first
    }
}
