import Testing
@testable import Foreman

struct CPUSamplerTests {
    @Test func firstSampleHasNoPercent() {
        var sampler = CPUSampler()
        #expect(sampler.percent(pid: 1, cpuNs: 1_000, wallNs: 10) == nil)
    }

    @Test func percentIsCpuDeltaOverWallDelta() {
        var sampler = CPUSampler()
        _ = sampler.percent(pid: 7, cpuNs: 0, wallNs: 0)
        // 0.5s of CPU over 2s of wall time = 25%.
        #expect(sampler.percent(pid: 7, cpuNs: 500_000_000, wallNs: 2_000_000_000) == 25)
        // Multi-threaded: 3s CPU over 1s wall = 300%, not clamped.
        #expect(sampler.percent(pid: 7, cpuNs: 3_500_000_000, wallNs: 3_000_000_000) == 300)
    }

    @Test func counterGoingBackwardsMeansReusedPid() {
        var sampler = CPUSampler()
        _ = sampler.percent(pid: 9, cpuNs: 5_000, wallNs: 100)
        #expect(sampler.percent(pid: 9, cpuNs: 10, wallNs: 200) == nil)
        #expect(sampler.percent(pid: 9, cpuNs: 110, wallNs: 300) == 100)
    }

    @Test func pruneForgetsDeadPids() {
        var sampler = CPUSampler()
        _ = sampler.percent(pid: 1, cpuNs: 0, wallNs: 0)
        _ = sampler.percent(pid: 2, cpuNs: 0, wallNs: 0)
        sampler.prune(keeping: [2])
        #expect(sampler.percent(pid: 1, cpuNs: 10, wallNs: 10) == nil)
        #expect(sampler.percent(pid: 2, cpuNs: 10, wallNs: 10) == 100)
    }
}
