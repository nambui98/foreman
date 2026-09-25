import Testing
@testable import Foreman

struct ProcessClassifierTests {
    static let home = "/Users/me"

    /// The real process list observed on the dev machine on 2026-09-24.
    @Test(arguments: [
        ("bun", "/Users/me/.bun/bin/bun", ProcessGroup.dev),
        ("node", "/opt/homebrew/Cellar/node/24.0.0/bin/node", .dev),
        ("next-server", "/opt/homebrew/Cellar/node/24.0.0/bin/node", .dev),
        ("Python", "/opt/homebrew/Cellar/python@3.12/3.12.13_2/Frameworks/Python.framework/Versions/3.12/Resources/Python.app/Contents/MacOS/Python", .dev),
        ("serve-sim-bin", "/Users/me/Library/Application Support/orca/serve-sim-runtime/1.4.209/bin/serve-sim-bin", .system),
        ("adb", "/Users/me/Library/Android/sdk/platform-tools/adb", .dev),
        ("postgres", "/opt/homebrew/Cellar/postgresql@16/16.4/bin/postgres", .dataContainer),
        ("OrbStack Helper", "/Applications/OrbStack.app/Contents/Frameworks/OrbStack Helper.app/Contents/MacOS/OrbStack Helper", .dataContainer),
        ("ControlCenter", "/System/Library/CoreServices/ControlCenter.app/Contents/MacOS/ControlCenter", .system),
        ("rapportd", "/usr/libexec/rapportd", .system),
        ("Raycast", "/Applications/Raycast.app/Contents/MacOS/Raycast", .system),
        ("TikTok", "/Applications/TikTok.app/Contents/MacOS/TikTok", .system),
        ("Orca", "/Applications/Orca.app/Contents/MacOS/Orca", .system),
        ("mytool", "/Users/me/Workspace/app/target/debug/mytool", .dev),
    ])
    func classifiesKnownProcesses(name: String, path: String, expected: ProcessGroup) {
        let group = ProcessClassifier.group(
            name: name, executablePath: path, uid: 501, currentUID: 501, home: Self.home)
        #expect(group == expected)
    }

    @Test func otherUsersProcessesAreSystemEvenIfDevRuntime() {
        let group = ProcessClassifier.group(
            name: "node", executablePath: "/opt/homebrew/bin/node", uid: 0, currentUID: 501, home: Self.home)
        #expect(group == .system)
    }

    @Test func unknownPathFallsBackToNameRules() {
        #expect(ProcessClassifier.group(name: "python3.12", executablePath: nil, uid: nil,
                                        currentUID: 501, home: Self.home) == .dev)
        #expect(ProcessClassifier.group(name: "mystery", executablePath: nil, uid: nil,
                                        currentUID: 501, home: Self.home) == .system)
    }
}
