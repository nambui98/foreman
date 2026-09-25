import Foundation

/// What `http://localhost:PORT` answers: status and page title, or why it did not.
struct ProbeResult: Equatable, Sendable {
    var status: Int?
    var title: String?
    var error: String?

    /// `200 · Vite App`, `302`, `lỗi: timeout`.
    var summary: String {
        if let error { return "lỗi: \(error)" }
        return [status.map(String.init), title].compactMap { $0 }.joined(separator: " · ")
    }
}

/// Quick HTTP look at a local port, run on demand (hover), never inside the refresh loop.
actor PortProbe {
    static let shared = PortProbe()
    static let timeout: TimeInterval = 1.5
    static let maxBytes = 64 * 1024
    static let cacheLifetime: TimeInterval = 30

    private var cache: [Int: (date: Date, result: ProbeResult)] = [:]
    private var inFlight: [Int: Task<ProbeResult, Never>] = [:]
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        config.httpCookieStorage = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config, delegate: NoRedirects(), delegateQueue: nil)
    }()

    func cached(port: Int) -> ProbeResult? {
        guard let entry = cache[port], Date().timeIntervalSince(entry.date) < Self.cacheLifetime else { return nil }
        return entry.result
    }

    func probe(port: Int) async -> ProbeResult {
        if let hit = cached(port: port) { return hit }
        if let running = inFlight[port] { return await running.value }
        let session = session
        let task = Task { await Self.fetch(port: port, session: session) }
        inFlight[port] = task
        let result = await task.value
        inFlight[port] = nil
        cache[port] = (Date(), result)
        return result
    }

    private static func fetch(port: Int, session: URLSession) async -> ProbeResult {
        guard let url = URL(string: "http://localhost:\(port)/") else { return ProbeResult(error: "URL") }
        do {
            let (bytes, response) = try await session.bytes(from: url)
            var body = Data()
            for try await byte in bytes {
                body.append(byte)
                if body.count >= maxBytes { break }
            }
            bytes.task.cancel()  // a streaming response (SSE, HMR) would otherwise stay open until timeout
            let status = (response as? HTTPURLResponse)?.statusCode
            return ProbeResult(status: status, title: title(in: String(decoding: body, as: UTF8.self)))
        } catch let error as URLError {
            return ProbeResult(error: error.code == .timedOut ? "timeout" : "không phải HTTP")
        } catch {
            return ProbeResult(error: "không phải HTTP")
        }
    }

    /// First `<title>` of an HTML page, whitespace collapsed and basic entities decoded.
    static func title(in html: String) -> String? {
        guard let match = html.firstMatch(of: /(?is)<title[^>]*>(.*?)<\/title>/) else { return nil }
        let raw = String(match.1).split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let decoded = [("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'")]
            .reduce(raw) { $0.replacingOccurrences(of: $1.0, with: $1.1) }
        return decoded.isEmpty ? nil : String(decoded.prefix(80))
    }

    /// A redirect is reported as-is (status 3xx) instead of following it, possibly off localhost.
    private final class NoRedirects: NSObject, URLSessionTaskDelegate {
        func urlSession(
            _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest
        ) async -> URLRequest? {
            nil
        }
    }
}
