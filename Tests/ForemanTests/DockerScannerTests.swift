import Testing
@testable import Foreman

struct DockerScannerTests {
    static let sample = """
    {"ID":"1841df3f527b","Image":"redis:7-alpine","Labels":"com.docker.compose.config-hash=2b1f,com.docker.compose.project=zunera,com.docker.compose.service=redis","Names":"Zunera-redis","Ports":"0.0.0.0:6380->6379/tcp, [::]:6380->6379/tcp","Status":"Up 2 days (healthy)"}
    {"ID":"aa11bb22cc33","Image":"minio/minio","Labels":"","Names":"danzai-minio","Ports":"0.0.0.0:9010->9000/tcp, [::]:9010->9000/tcp, 0.0.0.0:9011->9001/tcp, 9002/tcp","Status":"Up 3 hours"}
    not json
    """

    @Test func parsesContainersAndPublishedPorts() {
        let containers = DockerScanner.parse(Self.sample)
        #expect(containers.map(\.name) == ["Zunera-redis", "danzai-minio"])
        #expect(containers[0].ports == [.init(host: 6380, container: 6379)])
        #expect(containers[0].composeProject == "zunera")
        #expect(containers[1].ports == [.init(host: 9010, container: 9000), .init(host: 9011, container: 9001)])
        #expect(containers[1].composeProject == nil)
        #expect(containers[1].status == "Up 3 hours")
    }

    @Test func idValidation() {
        #expect(DockerScanner.isValidID("1841df3f527b"))
        #expect(!DockerScanner.isValidID("--rm"))
        #expect(!DockerScanner.isValidID("abc"))
    }

    @Test func containersAttachOnlyToTheHostProcess() {
        let containers = DockerScanner.parse(Self.sample)
        let sockets = [
            ListeningSocket(pid: 10, command: "OrbStack Helper", uid: 501, address: "*", port: 6380),
            ListeningSocket(pid: 10, command: "OrbStack Helper", uid: 501, address: "*", port: 9010),
            ListeningSocket(pid: 20, command: "node", uid: 501, address: "*", port: 9011),
        ]
        let rows = RowBuilder.rows(
            sockets: sockets, details: [:], cpuPercent: [:], currentUID: 501, home: "/Users/me", containers: containers)
        #expect(rows.first { $0.pid == 10 }?.containers.map(\.name) == ["Zunera-redis", "danzai-minio"])
        #expect(rows.first { $0.pid == 20 }?.containers.isEmpty == true)
    }
}
