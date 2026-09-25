import Foundation

/// Current git branch of a folder, read straight from `.git/HEAD` (no `git` subprocess).
/// A few stats and one small file read per call; `Cache` keeps refreshes from repeating it.
enum GitBranch {
    /// Branches per folder, re-read at most every `lifetime` so frequent agent passes cost nothing.
    struct Cache: Sendable {
        static let lifetime: UInt64 = 10_000_000_000  // ns
        private var entries: [String: (branch: String?, readAtNs: UInt64)] = [:]

        mutating func branch(cwd: String, nowNs: UInt64 = DispatchTime.now().uptimeNanoseconds) -> String? {
            if let entry = entries[cwd], nowNs &- entry.readAtNs < Self.lifetime { return entry.branch }
            let branch = GitBranch.resolve(cwd: cwd)
            entries[cwd] = (branch, nowNs)
            return branch
        }

        /// Forgets folders no process uses any more.
        mutating func prune(keeping folders: Set<String>) {
            entries = entries.filter { folders.contains($0.key) }
        }
    }

    static func resolve(cwd: String) -> String? {
        guard cwd != "/" else { return nil }
        var dir = URL(fileURLWithPath: cwd, isDirectory: true)
        while dir.path != "/" {
            let dotGit = dir.appending(path: ".git")
            if let head = headFile(dotGit: dotGit, in: dir),
               let contents = try? String(contentsOf: head, encoding: .utf8) {
                return branch(headContents: contents)
            }
            dir.deleteLastPathComponent()
        }
        return nil
    }

    /// `.git` is a directory in a normal checkout and a `gitdir: <path>` file in worktrees/submodules.
    private static func headFile(dotGit: URL, in dir: URL) -> URL? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dotGit.path, isDirectory: &isDirectory) else { return nil }
        if isDirectory.boolValue { return dotGit.appending(path: "HEAD") }
        guard let pointer = try? String(contentsOf: dotGit, encoding: .utf8),
              let gitDir = gitDirPath(fileContents: pointer) else { return nil }
        let base = gitDir.hasPrefix("/") ? URL(fileURLWithPath: gitDir) : dir.appending(path: gitDir)
        return base.appending(path: "HEAD")
    }

    static func gitDirPath(fileContents: String) -> String? {
        let line = fileContents.trimmingCharacters(in: .whitespacesAndNewlines)
        guard line.hasPrefix("gitdir:") else { return nil }
        return line.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
    }

    /// `ref: refs/heads/feat/x` → `feat/x`; a detached HEAD (sha) → first 7 characters.
    static func branch(headContents: String) -> String? {
        let head = headContents.trimmingCharacters(in: .whitespacesAndNewlines)
        if head.hasPrefix("ref: ") {
            let ref = head.dropFirst("ref: ".count)
            return ref.hasPrefix("refs/heads/") ? String(ref.dropFirst("refs/heads/".count)) : String(ref)
        }
        guard head.count >= 7, head.allSatisfy(\.isHexDigit) else { return nil }
        return String(head.prefix(7))
    }
}
