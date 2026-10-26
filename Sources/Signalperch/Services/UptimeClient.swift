import Foundation

struct UptimeClient: Sendable {
    /// Uses the status site's own advertised showcase. Unsupported sites return nil.
    func fetch(_ provider: Provider, components: [Component]) async throws -> [ComponentUptime]? {
        guard !components.isEmpty else { return [] }
        var request = URLRequest(url: provider.pageURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        request.setValue("Signalperch/0.3.1", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw FeedError.http(0) }
        guard (200..<300).contains(response.statusCode) else { throw FeedError.http(response.statusCode) }
        guard let html = String(data: data, encoding: .utf8),
              let base = response.url, base.scheme == "https", base.host?.lowercased() == provider.host.lowercased()
        else { return nil }
        if provider.id == "openai" { return Self.openAIComponents(in: html, components: components) }
        guard let endpoint = Self.advertisedEndpoint(in: html) else { return nil }
        let advertised = Set(Self.matches(#"data-uptime-lazy=["']([A-Za-z0-9_-]+)["']"#, in: html))
        // Match the public page's component selection, bound request size, and never
        // manufacture history for components absent from the advertised chart.
        let ids = Array(components.map(\.id).filter { advertised.contains($0) }.prefix(60))
        guard !ids.isEmpty else { return nil }
        guard var url = URLComponents(url: base.appendingPathComponent(String(endpoint.dropFirst())), resolvingAgainstBaseURL: false) else { return nil }
        url.queryItems = [URLQueryItem(name: "components", value: ids.joined(separator: ","))]
        guard let endpointURL = url.url else { return nil }
        let payload = try await StatusFeed.data(from: endpointURL)
        return try JSONDecoder().decode(UptimeShowcase.self, from: payload).components(orderedIDs: ids)
    }

    static func advertisedEndpoint(in html: String) -> String? {
        // This exact same-origin path is accepted only when the official page
        // declares it as its loader endpoint. No endpoint probing or JS execution.
        matches(#"\b(?:var|let|const)\s+ENDPOINT\s*=\s*["'](/uptime_showcase)["']"#, in: html).first
    }
    static func openAIComponents(in html: String, components: [Component]) -> [ComponentUptime]? {
        // Extract JSON string chunks, then decode JSON records. Nothing from the
        // page is evaluated as JavaScript, including the React reference strings.
        // Scan quoted JSON linearly: the real page's 200+ KB string exceeds
        // regex repetition limits that small fixture strings do not reach.
        let marker = "self.__next_f.push("
        var cursor = html.startIndex
        var chunks: [String] = []
        while let range = html.range(of: marker, range: cursor..<html.endIndex) {
            let start = range.upperBound
            cursor = start
            guard html[start...].hasPrefix("[1,") else { continue }
            var quoted = false
            var escaped = false
            var index = start
            while index < html.endIndex {
                let character = html[index]
                if quoted {
                    if escaped { escaped = false }
                    else if character == "\\" { escaped = true }
                    else if character == "\"" { quoted = false }
                } else if character == "\"" { quoted = true }
                else if character == "]" {
                    let end = html.index(after: index)
                    let data = Data(html[start..<end].utf8)
                    if let array = try? JSONSerialization.jsonObject(with: data) as? [Any],
                       array.count == 2, let chunk = array[1] as? String { chunks.append(chunk) }
                    cursor = end
                    break
                }
                index = html.index(after: index)
            }
            if index == html.endIndex { break }
        }
        let stream = chunks.joined()
        var sourceNow: Date?
        var periodDays: Int?
        var payload: OpenAIUptimeData?
        func visit(_ value: Any) {
            if let dictionary = value as? [String: Any] {
                if let now = dictionary["initialNow"] as? [String: Any], let iso = now["isoDate"] as? String {
                    sourceNow = StatusDate.parse(iso)
                }
                if let days = dictionary["history_window_days"] as? Int { periodDays = days }
                if dictionary["component_impacts"] != nil && dictionary["component_uptimes"] != nil,
                   let json = try? JSONSerialization.data(withJSONObject: dictionary),
                   let decoded = try? JSONDecoder().decode(OpenAIUptimeData.self, from: json) { payload = decoded }
                for child in dictionary.values { visit(child) }
            } else if let array = value as? [Any] { for child in array { visit(child) } }
        }
        for line in stream.split(separator: "\n") {
            guard let colon = line.firstIndex(of: ":"),
                  let json = String(line[line.index(after: colon)...]).data(using: .utf8),
                  let record = try? JSONSerialization.jsonObject(with: json, options: [.fragmentsAllowed]) else { continue }
            visit(record)
        }
        guard let sourceNow, let periodDays, let payload else { return nil }
        return payload.components(components, sourceNow: sourceNow, periodDays: periodDays)
    }
    private static func matches(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
            guard let range = Range($0.range(at: 1), in: text) else { return nil }
            return String(text[range])
        }
    }
}
