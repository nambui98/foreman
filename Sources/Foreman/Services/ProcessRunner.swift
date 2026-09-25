import Foundation

/// Runs helper tools (orca, osascript, docker) with a fixed argv, never through a shell.
enum ProcessRunner {
    /// Blocking: call off the main actor. The child is killed after `timeout`; output is read
    /// before waiting so a full pipe cannot deadlock it. nil when the executable can't start.
    static func run(
        _ executable: URL, _ arguments: [String], timeout: DispatchTimeInterval = .seconds(3)
    ) -> (output: Data, status: Int32)? {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let timer = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        timer.cancel()
        return (data, process.terminationStatus)
    }
}
