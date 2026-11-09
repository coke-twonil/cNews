import Foundation

struct EmbedItem: Identifiable, Equatable {
    var provider: String
    var url: URL
    var original: URL
    var id: String { provider + ":" + url.absoluteString }
    var label: String { ["instagram":"Instagram", "x":"X", "youtube":"YouTube", "facebook":"Facebook", "threads":"Threads", "tiktok":"TikTok", "vimeo":"Vimeo", "spotify":"Spotify", "preview":"連登預覽"][provider] ?? provider }
    static func parse(_ original: URL) -> EmbedItem? {
        guard ["http","https"].contains(original.scheme?.lowercased() ?? ""), original.user == nil, original.password == nil, original.port == nil else { return nil }
        var host = original.host?.lowercased() ?? ""
        for prefix in ["www.","mobile.","m."] { if host.hasPrefix(prefix) { host = String(host.dropFirst(prefix.count)); break } }
        let path = original.path
        let query = URLComponents(url: original, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ key: String) -> String? { query.first { $0.name == key }?.value }
        func match(_ pattern: String) -> [String]? {
            guard let regex = try? NSRegularExpression(pattern: pattern), let result = regex.firstMatch(in: path, range: NSRange(path.startIndex..., in: path)) else { return nil }
            return (1..<result.numberOfRanges).map { Range(result.range(at: $0), in: path).map { String(path[$0]) } ?? "" }
        }
        func item(_ provider: String, _ value: String) -> EmbedItem? { URL(string: value).map { EmbedItem(provider: provider, url: $0, original: original) } }
        if host == "instagram.com", let m = match("^/(p|reel|reels)/([A-Za-z0-9_-]+)/?$") { return item("instagram", "https://www.instagram.com/\(m[0] == "p" ? "p" : "reel")/\(m[1])/") }
        if ["x.com","twitter.com"].contains(host), let m = match("^/(?:[A-Za-z0-9_]+/status|i/web/status|i/status)/([0-9]+)/?$") { return item("x", "https://twitter.com/i/status/\(m[0])") }
        if ["threads.com","threads.net"].contains(host), let m = match("^/(?:@[^/]+/post|t)/([A-Za-z0-9_-]+)/?$") { return item("threads", "https://www.threads.com/t/\(m[0])/") }
        if ["threads.com","threads.net"].contains(host), let m = match("^/share/([A-Za-z0-9_-]+)/?$") { return item("threads", "https://www.threads.com/share/\(m[0])/") }
        if host == "facebook.com" {
            if match("^/(?:[A-Za-z0-9._-]+/posts/[A-Za-z0-9_-]+|groups/[A-Za-z0-9._-]+/(?:permalink|posts)/[0-9]+|share/(?:p|v)/[A-Za-z0-9_-]+|reel/[0-9]+)/?$") != nil { return item("facebook", "https://www.facebook.com" + path) }
            if path == "/story.php", let author = value("id"), let post = value("story_fbid"), author.allSatisfy(\.isNumber), post.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil { return item("facebook", "https://www.facebook.com/\(author)/posts/\(post)/") }
        }
        if host == "youtube.com" || host == "youtu.be" {
            let id = host == "youtu.be" ? path.split(separator: "/").first.map(String.init) : path == "/watch" ? value("v") : match("^/(?:shorts|live|embed)/([A-Za-z0-9_-]+)/?$")?.first
            if let id, id.range(of: "^[A-Za-z0-9_-]{11}$", options: .regularExpression) != nil {
                var start = 0
                let timestamp = value("t") ?? value("start") ?? "0"
                if let seconds = Int(timestamp) { start = max(0, seconds) }
                else if let regex = try? NSRegularExpression(pattern: "([0-9]+)([hms])") {
                    for part in regex.matches(in: timestamp, range: NSRange(timestamp.startIndex..., in: timestamp)) {
                        let ns = timestamp as NSString; let amount = Int(ns.substring(with: part.range(at: 1))) ?? 0
                        start += amount * (["h":3600,"m":60,"s":1][ns.substring(with: part.range(at: 2))] ?? 1)
                    }
                }
                return item("youtube", "https://www.youtube.com/embed/\(id)?playsinline=1&start=\(start)&rel=0")
            }
        }
        if host == "tiktok.com", let m = match("^/@[A-Za-z0-9_.]+/(?:video|photo)/([0-9]{8,30})/?$") { return item("tiktok", "https://www.tiktok.com/player/v1/\(m[0])?autoplay=0") }
        if host == "vimeo.com", let m = match("^/([0-9]+)(?:/([A-Za-z0-9]+))?/?$") { return item("vimeo", "https://player.vimeo.com/video/\(m[0])?dnt=1" + (m[1].isEmpty ? "" : "&h=\(m[1])")) }
        if host == "open.spotify.com", let m = match("^/(?:intl-[a-z-]+/)?(track|album|playlist|episode|show|artist)/([A-Za-z0-9]{22})/?$") { return item("spotify", "https://open.spotify.com/embed/\(m[0])/\(m[1])?theme=0") }
        if ["lih.kg","lihkg.com"].contains(host) { return item("preview", original.absoluteString) }
        return nil
    }
}
struct BodyPiece: Identifiable {
    var id: Int
    var text: String?
    var link: URL?
    var embed: EmbedItem?
}
func mediaPieces(_ body: String, embeds: Bool = true) -> [BodyPiece] {
    guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return [BodyPiece(id: 0, text: body)] }
    var result: [BodyPiece] = [], start = body.startIndex, seen = Set<String>()
    for match in detector.matches(in: body, range: NSRange(body.startIndex..., in: body)) {
        guard let range = Range(match.range, in: body), let url = match.url, ["http","https"].contains(url.scheme?.lowercased() ?? "") else { continue }
        if start < range.lowerBound { result.append(BodyPiece(id: result.count, text: String(body[start..<range.lowerBound]))) }
        let item = embeds ? EmbedItem.parse(url) : nil
        result.append(BodyPiece(id: result.count, link: url, embed: item.flatMap { seen.insert($0.id).inserted ? $0 : nil }))
        start = range.upperBound
    }
    if start < body.endIndex { result.append(BodyPiece(id: result.count, text: String(body[start...]))) }
    return result
}
