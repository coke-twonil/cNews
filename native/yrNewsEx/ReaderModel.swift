import Foundation
import Darwin

struct NewsMessage: Identifiable, Codable, Equatable {
    var id: String
    var parentID: String?
    var author: String
    var body: String
    var read = false
    var articleNumber: Int?
    var subject: String?
    var references: [String]?
    var bodyLoaded: Bool?
    var images: [Data]?
    var warnings: [String]?
    var senderIP: String?
    var senderIPChecked: Bool?
    var favourite: Bool?
    var searchBody: String?
}
struct NewsThread: Identifiable, Codable {
    var id: String
    var subject: String
    var messages: [NewsMessage]
    var serverID: String?
    var groupName: String?
    var unread: Int { messages.filter { !$0.read }.count }
    var tree: [(message: NewsMessage, depth: Int)] {
        let ids = Set(messages.map(\.id))
        var visited = Set<String>()
        var result: [(NewsMessage, Int)] = []
        func walk(_ message: NewsMessage, _ depth: Int) {
            guard visited.insert(message.id).inserted else { return }
            result.append((message, depth))
            for child in messages where child.parentID == message.id { walk(child, depth + 1) }
        }
        for message in messages where message.parentID == nil || !ids.contains(message.parentID!) { walk(message, 0) }
        for message in messages where !visited.contains(message.id) { walk(message, 0) }
        return result
    }
    func history(replyingTo id: String) -> String {
        let byID = Dictionary(messages.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var chain: [NewsMessage] = [], visited = Set<String>(), current = byID[id]
        while let message = current, chain.count < 4, visited.insert(message.id).inserted {
            chain.append(message)
            current = message.parentID.flatMap { byID[$0] }
        }
        return chain.enumerated().map { index, message in
            let prefix = String(repeating: ">", count: index + 1)
            let own = message.body.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix(">") }
            return "\(prefix) \(message.author):\n" + own.map { "\(prefix) \($0)" }.joined(separator: "\n")
        }.joined(separator: "\n\n")
    }
}
struct NewsServer: Identifiable, Codable {
    var id = UUID().uuidString
    var title: String
    var host: String
    var port = 119
    var name: String
    var email: String
    var groups: [String]
    var blockedUsers: [BlockedUser]?
}
struct PendingReply: Codable {
    var threadID: String
    var message: NewsMessage
    var newThread: NewsThread?
}
struct ReaderSnapshot: Codable {
    var servers: [NewsServer]
    var threads: [NewsThread]
    var pending: [PendingReply] = []
    var liveGroups: [String: LiveGroupCache]?
    var replyDrafts: [String: ReplyDraft]?
    var refreshCounts: [String: Int]?
    var deletedServerIDs: [String]?
}
func downloadSelection(available: [Int], newestDownloaded: Int?, count: Int, latest: Bool) -> [Int] {
    let newer = Array(Set(available)).sorted().filter { $0 > (newestDownloaded ?? 0) }
    return latest ? Array(newer.suffix(max(0, count))) : Array(newer.prefix(max(0, count)))
}
func demoSnapshot() -> ReaderSnapshot {
    let parents: [Int?] = [nil, 0, 1, 2, 1, 0, 5, 6, 5]
    let subjects = ["今晚食乜好？", "有冇人用緊新 reader？", "APM 間咖啡店仲有冇開？", "週末去邊度行下"]
    return ReaderSnapshot(servers: [NewsServer(id: "demo", title: "Demo · 本機示例", host: "news.twonil.hk", name: "示例讀者", email: "reader@example.invalid", groups: ["general.chat", "general.soccer_n_chat", "test.test"])], threads: subjects.enumerated().map { index, subject in
        NewsThread(id: "t\(index)", subject: subject, messages: (0..<(index == 2 ? 9 : index + 1)).map { n in
            NewsMessage(id: "t\(index)m\(n)", parentID: parents[n].map { "t\(index)m\($0)" }, author: ["阿明", "路人甲", "Coffee lover"][n % 3], body: n == 0 ? "以前成日去坐下，最近經過見到好似冇開。\n有冇人知搬咗去邊？" : "我都想知，有消息再講。\n多謝分享！", read: n == 1)
        })
    })
}

func scrollDemoThread() -> NewsThread {
    NewsThread(id: "native-scroll-demo", subject: "長文章捲動測試（本機示例）", messages: [
        NewsMessage(id: "native-scroll-message", author: "yrNewsEx Demo", body: "呢篇係本機操作示例，用嚟試上下捲動同左右切換。\n\n" + (1...40).map { "第 \($0) 段：向上拖動可以繼續閱讀；左右 swipe 會切換文章，唔會誤當成點擊。" }.joined(separator: "\n\n"))
    ])
}

struct LiveGroupCache: Codable {
    var messages: [NewsMessage] = []
    var newest: Int? { messages.compactMap(\.articleNumber).max() }
}
func groupKey(_ server: String, _ group: String) -> String { server + "|" + group }
func liveThreads(_ cache: LiveGroupCache, server: String, group: String) -> [NewsThread] {
    let messages = cache.messages.sorted { ($0.articleNumber ?? 0) < ($1.articleNumber ?? 0) }
    var parents: [String: String] = [:]
    func root(_ id: String) -> String {
        var result = id, visited = Set<String>()
        while let parent = parents[result], visited.insert(result).inserted { result = parent }
        return result
    }
    for message in messages {
        var chain = (message.references ?? []) + [message.id]
        chain = Array(NSOrderedSet(array: chain)) as? [String] ?? chain
        if let first = chain.first {
            for id in chain.dropFirst() { let a = root(id), b = root(first); if a != b { parents[a] = b } }
        }
    }
    var grouped: [String: [NewsMessage]] = [:], order: [String] = []
    for message in messages {
        let key = root(message.id)
        if grouped[key] == nil { order.append(key) }
        grouped[key, default: []].append(message)
    }
    return order.compactMap { id in
        guard let items = grouped[id], let first = items.first else { return nil }
        return NewsThread(id: groupKey(server, group) + "|" + id, subject: first.subject ?? "(No subject)", messages: items, serverID: server, groupName: group)
    }.reversed()
}

struct ReplyPhoto: Identifiable, Codable, Equatable {
    var id = UUID().uuidString
    var data: Data
    var mime: String
}
struct ReplyDraft: Codable {
    var id = UUID().uuidString.lowercased()
    var text = ""
    var subject: String?
    var photos: [ReplyPhoto] = []
    var status: String?
    var fingerprint: String?
    var messageID: String { "<yrnewsex.\(id)@yrnewsex.invalid>" }
    mutating func changed() { id = UUID().uuidString.lowercased(); status = nil; fingerprint = nil }
}

struct BlockedUser: Identifiable, Codable, Equatable {
    var username: String
    var email: String
    var ip: String
    var id: String { ip }
}
func senderIdentity(_ author: String) -> (name: String, email: String) {
    if let left = author.lastIndex(of: "<"), let right = author[left...].firstIndex(of: ">") {
        let name = author[..<left].trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        let email = String(author[author.index(after: left)..<right])
        return (name.isEmpty ? email : name, email)
    }
    return (author, author.contains("@") ? author : "未有提供")
}
func canonicalIP(_ text: String) -> String? {
    let value = text.trimmingCharacters(in: CharacterSet(charactersIn: "[] \t\""))
    var v4 = in_addr(), v6 = in6_addr()
    var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
    if inet_pton(AF_INET, value, &v4) == 1 { _ = inet_ntop(AF_INET, &v4, &buffer, socklen_t(buffer.count)); return String(cString: buffer) }
    if inet_pton(AF_INET6, value, &v6) == 1 { _ = inet_ntop(AF_INET6, &v6, &buffer, socklen_t(buffer.count)); return String(cString: buffer).lowercased() }
    return nil
}
extension NewsThread {
    func visible(blocked: [BlockedUser]) -> NewsThread? {
        let ips = Set(blocked.map(\.ip))
        var hidden = Set(messages.filter { $0.senderIP.map { ips.contains($0) } ?? false }.map(\.id))
        // References retain ancestry even when an intermediate parent is absent.
        var changed = true
        while changed {
            changed = false
            for message in messages where !hidden.contains(message.id) {
                if message.parentID.map({ hidden.contains($0) }) == true || (message.references ?? []).contains(where: { hidden.contains($0) }) {
                    hidden.insert(message.id); changed = true
                }
            }
        }
        var result = self; result.messages.removeAll { hidden.contains($0.id) }
        return result.messages.isEmpty ? nil : result
    }
    func matches(_ query: String, scope: String) -> Bool {
        if query.isEmpty { return true }
        switch scope {
        case "Sender": return messages.contains { $0.author.localizedCaseInsensitiveContains(query) }
        case "Message": return messages.contains { ($0.searchBody ?? $0.body).localizedCaseInsensitiveContains(query) }
        default: return subject.localizedCaseInsensitiveContains(query) || messages.contains { ($0.subject ?? "").localizedCaseInsensitiveContains(query) }
        }
    }
}
func adjacentThreadIndex(threadIDs: [String], index: Int, delta: Int) -> Int? {
    guard threadIDs.indices.contains(index) else { return nil }
    var order: [String] = []
    for id in threadIDs where order.last != id { order.append(id) }
    guard let current = order.firstIndex(of: threadIDs[index]), order.indices.contains(current + delta) else { return nil }
    return threadIDs.firstIndex(of: order[current + delta])
}

extension ReaderSnapshot {
    mutating func deleteServer(_ id: String) {
        guard servers.contains(where: { $0.id == id }) else { return }
        let threadIDs = Set(threads.filter { $0.serverID == id || (id == "demo" && $0.serverID == nil) }.map(\.id))
        servers.removeAll { $0.id == id }
        threads.removeAll { threadIDs.contains($0.id) }
        pending.removeAll { threadIDs.contains($0.threadID) || $0.newThread?.serverID == id || (id == "demo" && $0.newThread != nil && $0.newThread?.serverID == nil) }
        let prefix = id + "|"
        liveGroups = liveGroups?.filter { !$0.key.hasPrefix(prefix) }
        replyDrafts = replyDrafts?.filter { !$0.key.hasPrefix(prefix) }
        refreshCounts = refreshCounts?.filter { !$0.key.hasPrefix(prefix) }
        // Preserve user removal when migrating older installations on next launch.
        var removed = deletedServerIDs ?? []
        if !removed.contains(id) { removed.append(id) }
        deletedServerIDs = removed
    }
}
