import Darwin
import Foundation
import Testing
@testable import PortBar

struct ProcessInspectorTests {
    @Test func readsOwnProcess() throws {
        let details = ProcessInspector.details(pid: getpid())
        #expect(details.uid == getuid())
        #expect(details.pgid == getpgrp())
        #expect(details.cwd == FileManager.default.currentDirectoryPath)
        #expect(details.executablePath?.hasSuffix("/PortBar") == true)
        #expect(try #require(details.memoryBytes) > 1_000_000)
        #expect(try #require(details.cpuTimeNs) > 0)
        #expect(!details.arguments.isEmpty)
    }

    @Test func cpuTimeIsInNanoseconds() throws {
        // libproc reports mach ticks; after conversion it must agree with getrusage (µs), not be ~41x off.
        var x = 0.0
        for i in 0..<5_000_000 { x += sin(Double(i)) }
        #expect(x.isFinite)
        let converted = try #require(ProcessInspector.details(pid: getpid()).cpuTimeNs)
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        let reference = UInt64(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) * 1_000_000_000
            + UInt64(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) * 1_000
        let ratio = Double(converted) / Double(reference)
        #expect(ratio > 0.8 && ratio < 1.25)
    }

    @Test func missingProcessIsNotAlive() {
        #expect(!ProcessInspector.isAlive(pid: 999_999))
        #expect(ProcessInspector.isAlive(pid: getpid()))
    }
}
