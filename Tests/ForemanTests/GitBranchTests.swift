import Foundation
import Network
import Testing
@testable import Foreman

struct GitBranchTests {
    private func makeDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: "foreman-git-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    @Test func headParsing() {
        #expect(GitBranch.branch(headContents: "ref: refs/heads/feat/login\n") == "feat/login")
        #expect(GitBranch.branch(headContents: "ref: refs/remotes/origin/main") == "refs/remotes/origin/main")
        #expect(GitBranch.branch(headContents: "3f9a1c2d4e5b6a7980\n") == "3f9a1c2")
        #expect(GitBranch.branch(headContents: "garbage") == nil)
        #expect(GitBranch.gitDirPath(fileContents: "gitdir: ../main/.git/worktrees/x\n") == "../main/.git/worktrees/x")
        #expect(GitBranch.gitDirPath(fileContents: "nope") == nil)
    }

    @Test func normalCheckoutFromSubfolder() throws {
        let repo = try makeDir()
        defer { try? FileManager.default.removeItem(at: repo) }
        try write("ref: refs/heads/main\n", to: repo.appending(path: ".git/HEAD"))
        let sub = repo.appending(path: "apps/web")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        #expect(GitBranch.resolve(cwd: sub.path) == "main")
    }

    @Test func worktreeFollowsGitdirFile() throws {
        let root = try makeDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let meta = root.appending(path: "main/.git/worktrees/feature")
        try write("ref: refs/heads/feature-x\n", to: meta.appending(path: "HEAD"))
        let worktree = root.appending(path: "feature")
        try write("gitdir: \(meta.path)\n", to: worktree.appending(path: ".git"))
        #expect(GitBranch.resolve(cwd: worktree.path) == "feature-x")

        // Relative gitdir (submodules) resolves against the checkout folder.
        let relative = root.appending(path: "relative")
        try write("gitdir: ../main/.git/worktrees/feature\n", to: relative.appending(path: ".git"))
        #expect(GitBranch.resolve(cwd: relative.path) == "feature-x")
    }

    @Test func cacheRereadsOnlyAfterLifetime() throws {
        let repo = try makeDir()
        defer { try? FileManager.default.removeItem(at: repo) }
        let head = repo.appending(path: ".git/HEAD")
        try write("ref: refs/heads/one\n", to: head)
        var cache = GitBranch.Cache()
        #expect(cache.branch(cwd: repo.path, nowNs: 1_000) == "one")
        try write("ref: refs/heads/two\n", to: head)
        #expect(cache.branch(cwd: repo.path, nowNs: 2_000) == "one")
        #expect(cache.branch(cwd: repo.path, nowNs: 1_000 + GitBranch.Cache.lifetime) == "two")
        cache.prune(keeping: [])
        try write("ref: refs/heads/three\n", to: head)
        #expect(cache.branch(cwd: repo.path, nowNs: 1_000 + GitBranch.Cache.lifetime + 1) == "three")
    }

    @Test func noRepository() throws {
        let dir = try makeDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(GitBranch.resolve(cwd: dir.path) == nil)
        #expect(GitBranch.resolve(cwd: "/") == nil)
    }
}

struct PortProbeTests {
    @Test func titleExtraction() {
        #expect(PortProbe.title(in: "<html><head><TITLE>\n  Vite &amp; React\n</TITLE>") == "Vite & React")
        #expect(PortProbe.title(in: "<title data-x=\"1\">Admin</title>") == "Admin")
        #expect(PortProbe.title(in: "<title></title>") == nil)
        #expect(PortProbe.title(in: "{\"ok\":true}") == nil)
    }

    @Test func summaries() {
        #expect(ProbeResult(status: 200, title: "App").summary == "200 · App")
        #expect(ProbeResult(status: 302).summary == "302")
        #expect(ProbeResult(error: "timeout").summary == "error: timeout")
    }

    @Test func probesALocalHTTPServer() async throws {
        let listener = try NWListener(using: .tcp, on: .any)
        listener.newConnectionHandler = { connection in
            connection.start(queue: .global())
            connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { _, _, _, _ in
                let body = "<html><head><title>Probe Test</title></head></html>"
                let response = "HTTP/1.1 201 Created\r\nContent-Type: text/html\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
                connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
            }
        }
        let ready = AsyncStream<UInt16> { continuation in
            listener.stateUpdateHandler = { state in
                if case .ready = state { continuation.yield(listener.port?.rawValue ?? 0); continuation.finish() }
            }
        }
        listener.start(queue: .global())
        defer { listener.cancel() }
        var iterator = ready.makeAsyncIterator()
        let port = Int(try #require(await iterator.next()))

        let result = await PortProbe().probe(port: port)
        #expect(result == ProbeResult(status: 201, title: "Probe Test"))
    }

    @Test func closedPortReportsError() async {
        // Port 1 (tcpmux) is never served on a dev machine.
        let result = await PortProbe().probe(port: 1)
        #expect(result.error != nil)
    }
}

@MainActor
struct EditorLauncherTests {
    @Test func preferredFallsBackToFirstInstalled() {
        let installed = EditorLauncher.installed()
        #expect(EditorLauncher.preferred(bundleID: "com.example.not-installed") == installed.first)
        if let last = installed.last {
            #expect(EditorLauncher.preferred(bundleID: last.bundleID) == last)
        }
    }
}
