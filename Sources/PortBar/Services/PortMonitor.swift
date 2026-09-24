import AppKit
import Foundation
import Observation

/// Owns the refresh loop and kill actions; the single source of truth for the UI.
@MainActor
@Observable
final class PortMonitor {
    static let openInterval: Duration = .seconds(2)
    static let closedInterval: Duration = .seconds(15)

    private(set) var rows: [PortRow] = []
    private(set) var lastError: String?
    private(set) var lastUpdated: Date?
    private(set) var killStates: [Int32: KillState] = [:]
    private(set) var isPanelOpen = false

    var devCount: Int { rows.count(where: { $0.group == .dev }) }

    private var sampler = CPUSampler()
    private var isRefreshing = false
    private var refreshRequested = false
    private var loop: Task<Void, Never>?
    private let killer = ProcessKiller()
    private let currentUID = getuid()
    private let home = NSHomeDirectory()

    func start() {
        guard loop == nil else { return }
        restartLoop()
    }

    /// Faster refresh while the panel is visible; refreshes immediately on open.
    func setPanelOpen(_ open: Bool) {
        guard open != isPanelOpen else { return }
        isPanelOpen = open
        restartLoop()
    }

    /// Coalesces overlapping calls: a refresh requested while one is running runs once afterwards,
    /// so lsof is never spawned twice concurrently and CPU samples keep sane wall-clock deltas.
    func refresh() async {
        guard !isRefreshing else {
            refreshRequested = true
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }
        repeat {
            refreshRequested = false
            await refreshOnce()
        } while refreshRequested
    }

    private func refreshOnce() async {
        do {
            let sockets = try await PortScanner.scan()
            let pids = Set(sockets.map(\.pid))
            let details = await Task.detached(priority: .utility) {
                Dictionary(uniqueKeysWithValues: pids.map { ($0, ProcessInspector.details(pid: $0)) })
            }.value

            var cpu: [Int32: Double] = [:]
            for (pid, info) in details {
                if let cpuNs = info.cpuTimeNs,
                   let percent = sampler.percent(pid: pid, cpuNs: cpuNs, wallNs: info.sampledAtNs) {
                    cpu[pid] = percent
                }
            }
            sampler.prune(keeping: pids)

            rows = RowBuilder.rows(
                sockets: sockets, details: details, cpuPercent: cpu, currentUID: currentUID, home: home)
            // Forget kill state for processes that are gone.
            killStates = killStates.filter { pids.contains($0.key) }
            lastError = nil
            lastUpdated = Date()
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// SIGTERM (or SIGKILL when `force`) the row's process or its whole group.
    func kill(_ row: PortRow, wholeGroup: Bool = false, force: Bool = false) async {
        killStates[row.pid] = .terminating
        let outcome = force
            ? await killer.forceKill(pid: row.pid, wholeGroup: wholeGroup)
            : await killer.terminate(pid: row.pid, wholeGroup: wholeGroup)

        switch outcome {
        case .exited, .notFound: killStates[row.pid] = nil
        case .stillRunning: killStates[row.pid] = .needsForce
        case .notPermitted: killStates[row.pid] = .failed("Không đủ quyền để dừng tiến trình này")
        case .refused(let reason): killStates[row.pid] = .failed(reason)
        }
        await refresh()
    }

    func fail(pid: Int32, _ message: String) {
        killStates[pid] = .failed(message)
    }

    func dismissError(pid: Int32) {
        if case .failed = killStates[pid] { killStates[pid] = nil }
    }

    private func restartLoop() {
        loop?.cancel()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                try? await Task.sleep(for: self.isPanelVisible ? Self.openInterval : Self.closedInterval)
            }
        }
    }

    /// `onAppear`/`onDisappear` of MenuBarExtra content is not guaranteed to fire on every toggle,
    /// so the fast cadence also requires an actually visible window besides the status item.
    private var isPanelVisible: Bool {
        isPanelOpen && NSApp.windows.contains { $0.isVisible && !($0.className.contains("StatusBar")) }
    }
}
