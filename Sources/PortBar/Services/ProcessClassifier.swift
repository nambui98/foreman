/// Decides which panel section a process belongs to. Rules are applied in order:
/// 1. other users' processes and OS binaries → system
/// 2. databases, caches, container runtimes → dataContainer
/// 3. language runtimes / dev servers, or binaries installed by the user outside app bundles → dev
/// 4. everything else (GUI apps, daemons) → system
enum ProcessClassifier {
    private static let systemPrefixes = ["/System/", "/usr/libexec/", "/usr/sbin/", "/sbin/", "/usr/bin/"]
    private static let dataKeywords = [
        "postgres", "mysql", "mariadb", "redis", "mongo", "memcache", "orbstack", "docker",
        "minio", "clickhouse", "elasticsearch", "opensearch", "rabbitmq", "etcd", "vpnkit",
    ]
    private static let devNames: Set<String> = [
        "node", "bun", "deno", "ruby", "java", "php", "php-fpm", "go", "dotnet", "beam.smp", "erl",
        "next-server", "vite", "esbuild", "serve-sim", "adb", "uvicorn", "gunicorn", "hugo", "caddy",
        "nginx", "httpd", "wrangler", "workerd", "cargo", "air",
    ]
    private static let userBinaryPrefixes = ["/opt/homebrew/", "/usr/local/"]

    static func group(
        name: String, executablePath: String?, uid: UInt32?, currentUID: UInt32, home: String
    ) -> ProcessGroup {
        let lowerName = name.lowercased()
        let path = executablePath ?? ""

        if let uid, uid != currentUID { return .system }
        if systemPrefixes.contains(where: path.hasPrefix) { return .system }

        if dataKeywords.contains(where: { lowerName.contains($0) || path.lowercased().contains($0) }) {
            return .dataContainer
        }

        if devNames.contains(lowerName) || lowerName.hasPrefix("python") { return .dev }

        let insideAppBundle = path.hasPrefix("/Applications/") || path.hasPrefix(home + "/Applications/")
        let userInstalled = userBinaryPrefixes.contains(where: path.hasPrefix)
            || (path.hasPrefix(home + "/") && !path.hasPrefix(home + "/Library/"))
        if userInstalled && !insideAppBundle { return .dev }

        return .system
    }
}
