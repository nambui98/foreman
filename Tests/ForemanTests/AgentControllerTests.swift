import Darwin
import Foundation
import Testing
@testable import Foreman

/// Uses a throwaway `sh` as a stand-in agent; never touches real agent sessions.
@MainActor
@Suite(.serialized)
struct AgentControllerTests {
    private func spawnFakeAgent(_ script: String) async throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        try process.run()
        try await Task.sleep(for: .milliseconds(300))
        return process
    }

    private func isStopped(_ pid: Int32) -> Bool {
        ProcessInspector.bsdInfo(pid: pid)?.pbi_status == UInt32(SSTOP)
    }

    @Test func pauseStopsDescendantsButNeverTheAgent() async throws {
        let agent = try await spawnFakeAgent("sleep 60 & sleep 60 & wait")
        let controller = AgentController()
        let pid = agent.processIdentifier
        let children = ProcessTable.snapshot().descendants(of: pid)
        #expect(children.count == 2)

        controller.pause(agentPid: pid, table: .snapshot())
        #expect(controller.isPaused(pid))
        #expect(children.allSatisfy(isStopped))
        #expect(!isStopped(pid))

        controller.resume(agentPid: pid)
        try await Task.sleep(for: .milliseconds(100))
        #expect(!controller.isPaused(pid))
        #expect(!children.contains(where: isStopped))
        _ = await controller.stop(agentPid: pid, table: .snapshot(), force: true)
    }

    @Test func reconcilePausesChildrenSpawnedAfterPause() async throws {
        // SIGUSR1 makes the fake agent spawn another child (the agent itself is never paused).
        let agent = try await spawnFakeAgent("trap 'sleep 60 &' USR1; sleep 60 & while :; do wait; done")
        let controller = AgentController()
        let pid = agent.processIdentifier
        controller.pause(agentPid: pid, table: .snapshot())
        kill(pid, SIGUSR1)
        try await Task.sleep(for: .milliseconds(300))
        let table = ProcessTable.snapshot()
        let children = table.descendants(of: pid)
        #expect(children.count == 2)
        #expect(!children.allSatisfy(isStopped))

        controller.reconcile(table: table, livePids: [pid])
        #expect(children.allSatisfy(isStopped))
        _ = await controller.stop(agentPid: pid, table: .snapshot(), force: false)
    }

    @Test func stopEndsWholeTreeEvenWhenPaused() async throws {
        let agent = try await spawnFakeAgent("sleep 60 & sleep 60 & wait")
        let controller = AgentController()
        let pid = agent.processIdentifier
        let tree = [pid] + ProcessTable.snapshot().descendants(of: pid)
        controller.pause(agentPid: pid, table: .snapshot())

        #expect(await controller.stop(agentPid: pid, table: .snapshot(), force: false) == .exited)
        #expect(!tree.contains(where: ProcessInspector.isAlive))
        #expect(!controller.isPaused(pid))
    }

    @Test func stopTargetsNeverIncludeForemanOrItsAncestors() {
        let controller = AgentController()
        let table = ProcessTable.snapshot()
        // Treat our parent as an "agent": we are one of its descendants.
        let targets = controller.stopTargets(agentPid: getppid(), table: table).map(\.0.pid)
        #expect(!targets.contains(getpid()))
        #expect(!targets.contains(getppid()))
    }

    @Test func releasesPausedChildrenWhenAgentDisappears() async throws {
        let agent = try await spawnFakeAgent("sleep 60 & wait")
        let controller = AgentController()
        let pid = agent.processIdentifier
        let child = try #require(ProcessTable.snapshot().descendants(of: pid).first)
        controller.pause(agentPid: pid, table: .snapshot())
        #expect(isStopped(child))

        controller.reconcile(table: .snapshot(), livePids: [])  // agent no longer detected
        try await Task.sleep(for: .milliseconds(100))
        #expect(!isStopped(child))
        #expect(!controller.isPaused(pid))
        kill(child, SIGKILL)
        kill(pid, SIGKILL)
    }
}

@MainActor
@Suite(.serialized)
struct AgentControllerPersistenceTests {
    @Test func nextLaunchResumesMembersLeftPausedByACrash() async throws {
        let defaults = try #require(UserDefaults(suiteName: "foreman-tests-\(UUID())"))
        let agent = Process()
        agent.executableURL = URL(fileURLWithPath: "/bin/sh")
        agent.arguments = ["-c", "sleep 60 & wait"]
        try agent.run()
        try await Task.sleep(for: .milliseconds(300))
        let pid = agent.processIdentifier
        let child = try #require(ProcessTable.snapshot().descendants(of: pid).first)

        // First instance pauses, then "crashes" (no resume).
        AgentController(defaults: defaults).pause(agentPid: pid, table: .snapshot())
        #expect(ProcessInspector.bsdInfo(pid: child)?.pbi_status == UInt32(SSTOP))
        #expect(defaults.array(forKey: AgentController.defaultsKey)?.count == 1)

        // Next launch continues it and clears the record.
        _ = AgentController(defaults: defaults)
        try await Task.sleep(for: .milliseconds(100))
        #expect(ProcessInspector.bsdInfo(pid: child)?.pbi_status != UInt32(SSTOP))
        #expect(defaults.array(forKey: AgentController.defaultsKey) == nil)
        kill(child, SIGKILL)
        kill(pid, SIGKILL)
    }
}
