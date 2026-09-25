import Foundation

enum PortScannerError: Error, LocalizedError {
    case timedOut
    case failed(status: Int32)

    var errorDescription: String? {
        switch self {
        case .timedOut: "lsof không phản hồi sau 3 giây"
        case .failed(let status): "lsof lỗi (mã \(status))"
        }
    }
}

/// Lists listening TCP sockets (and established ones, to count inbound connections) by running `/usr/sbin/lsof` with a fixed argv (no shell).
enum PortScanner {
    static let timeout: TimeInterval = 3

    static func scan() async throws -> LsofScan {
        try await Task.detached(priority: .utility) { try runLsof() }.value
    }

    private static func runLsof() throws -> LsofScan {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        // +c 0: untruncated command names. -n/-P: no DNS or service-name lookups (fast, numeric).
        // LISTEN+ESTABLISHED in one pass costs the same as LISTEN alone (~0.04s).
        process.arguments = ["+c", "0", "-nP", "-iTCP", "-sTCP:LISTEN,ESTABLISHED", "-F", "pcunT"]
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        try process.run()

        // terminate() only signals while the Process still owns a running child, so a PID that
        // was already reaped (and possibly reused) is never hit.
        let watchdog = DispatchWorkItem { process.terminate() }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()

        if process.terminationReason == .uncaughtSignal { throw PortScannerError.timedOut }
        // lsof exits 1 when nothing matches; the (possibly empty) output is still valid.
        guard process.terminationStatus <= 1 else {
            throw PortScannerError.failed(status: process.terminationStatus)
        }
        return LsofParser.scan(String(decoding: data, as: UTF8.self))
    }
}
