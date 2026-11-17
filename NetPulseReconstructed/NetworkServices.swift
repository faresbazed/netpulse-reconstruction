import Foundation

struct NetworkTestError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct DNSAnswer: Decodable {
    let name: String?
    let type: Int?
    let data: String?
}

struct DNSResponse: Decodable {
    let status: Int?
    let answer: [DNSAnswer]?

    enum CodingKeys: String, CodingKey {
        case status = "Status"
        case answer = "Answer"
    }
}

enum NetworkTests {
    static func downloadSpeed() async throws -> String {
        let bytes = 8_000_000
        var parts = URLComponents(string: "https://speed.cloudflare.com/__down")!
        parts.queryItems = [
            URLQueryItem(name: "bytes", value: String(bytes)),
            URLQueryItem(name: "cacheBust", value: UUID().uuidString)
        ]
        guard let url = parts.url else { throw NetworkTestError(message: "Invalid test URL") }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        let start = Date()
        let (data, response) = try await URLSession.shared.data(for: request)
        let seconds = max(Date().timeIntervalSince(start), 0.001)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            throw NetworkTestError(message: "Download endpoint returned an unsuccessful response")
        }
        let mbps = Double(data.count) * 8 / seconds / 1_000_000
        return String(format: "Download: %.1f Mbps (%@ in %.2f s)", mbps, ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file), seconds)
    }

    static func uploadSpeed() async throws -> String {
        let payload = Data(repeating: 0x4E, count: 1_000_000)
        guard let url = URL(string: "https://speed.cloudflare.com/__up") else {
            throw NetworkTestError(message: "Invalid upload URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        let start = Date()
        let (_, response) = try await URLSession.shared.upload(for: request, from: payload)
        let seconds = max(Date().timeIntervalSince(start), 0.001)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            throw NetworkTestError(message: "Upload endpoint returned an unsuccessful response")
        }
        let mbps = Double(payload.count) * 8 / seconds / 1_000_000
        return String(format: "Upload: %.1f Mbps (1 MB sample in %.2f s)", mbps, seconds)
    }

    static func runSpeedTest() async throws -> String {
        let download = try await downloadSpeed()
        let upload = try await uploadSpeed()
        return "\(download)\n\(upload)\nTest server: speed.cloudflare.com"
    }

    static func resolveDNS(_ rawHost: String) async throws -> String {
        let host = normalizedHost(rawHost)
        guard !host.isEmpty else { throw NetworkTestError(message: "Enter a hostname") }
        var components = URLComponents(string: "https://cloudflare-dns.com/dns-query")!
        components.queryItems = [
            URLQueryItem(name: "name", value: host),
            URLQueryItem(name: "type", value: "A")
        ]
        guard let url = components.url else { throw NetworkTestError(message: "Invalid DNS query") }
        var request = URLRequest(url: url)
        request.setValue("application/dns-json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10
        let start = Date()
        let (data, _) = try await URLSession.shared.data(for: request)
        let elapsed = Date().timeIntervalSince(start) * 1000
        let decoded = try JSONDecoder().decode(DNSResponse.self, from: data)
        let records = (decoded.answer ?? []).compactMap(\.data)
        guard decoded.status == 0, !records.isEmpty else {
            throw NetworkTestError(message: "No A records returned for \(host)")
        }
        return "\(host) → \(records.joined(separator: ", "))\nDNS-over-HTTPS: Cloudflare\nElapsed: \(Int(elapsed)) ms"
    }

    static func httpRequest(_ rawURL: String) async throws -> String {
        let value = rawURL.contains("://") ? rawURL : "https://\(rawURL)"
        guard let url = URL(string: value), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else {
            throw NetworkTestError(message: "Enter a valid HTTP or HTTPS URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        let start = Date()
        let (data, response) = try await URLSession.shared.data(for: request)
        let milliseconds = Date().timeIntervalSince(start) * 1000
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        return "Status: HTTP \(status)\nTotal response time: \(Int(milliseconds)) ms\nBody received: \(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))"
    }

    // This intentionally uses an HTTPS HEAD request; it is not an ICMP Echo implementation.
    static func reachability(_ rawHost: String) async throws -> String {
        let host = normalizedHost(rawHost)
        guard !host.isEmpty else { throw NetworkTestError(message: "Enter a hostname or IP address") }
        let address = host.contains("://") ? host : "https://\(host)"
        guard let url = URL(string: address) else { throw NetworkTestError(message: "Invalid hostname") }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 10
        let start = Date()
        let (_, response) = try await URLSession.shared.data(for: request)
        let milliseconds = Date().timeIntervalSince(start) * 1000
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        return "HTTPS reachable: \(url.host ?? host)\nHTTP status: \(status)\nDNS + connect + TLS + response: \(Int(milliseconds)) ms\nThis is an HTTP timing approximation, not ICMP ping."
    }

    static func quickDiagnosis(_ rawHost: String) async throws -> String {
        let host = normalizedHost(rawHost)
        let dns = try await resolveDNS(host)
        let web = try await reachability(host)
        return "DNS check\n\(dns)\n\nHTTPS check\n\(web)"
    }

    static func publicIP() async throws -> String {
        guard let url = URL(string: "https://www.cloudflare.com/cdn-cgi/trace") else {
            throw NetworkTestError(message: "Invalid lookup URL")
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        let (data, _) = try await URLSession.shared.data(for: request)
        let body = String(decoding: data, as: UTF8.self)
        guard let line = body.split(separator: "\n").first(where: { $0.hasPrefix("ip=") }) else {
            throw NetworkTestError(message: "Could not read the public IP from the response")
        }
        return "Public IP: \(line.dropFirst(3))\nSource: Cloudflare trace endpoint"
    }

    private static func normalizedHost(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), let host = url.host { return host }
        return trimmed
    }
}
