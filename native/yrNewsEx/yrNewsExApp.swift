import SwiftUI
import Photos

@MainActor
final class ReaderStore: ObservableObject {
    @Published var snapshot: ReaderSnapshot { didSet { save() } }
    @Published var storageError: String?
    @Published var busy = false
    @Published var progress = ""
    @Published var loadingArticles = Set<String>()
    private let file: URL
    private lazy var writer = SnapshotFileWriter(file: file)
    init() {
        file = URL.applicationSupportDirectory.appending(path: "yrNewsEx/native-demo.json")
        if FileManager.default.fileExists(atPath: file.path) {
            do { snapshot = try JSONDecoder().decode(ReaderSnapshot.self, from: Data(contentsOf: file)) }
            catch { snapshot = demoSnapshot(); storageError = "未能讀取本機資料：\(error.localizedDescription)" }
        } else { snapshot = demoSnapshot() }
        if !snapshot.servers.contains(where: { $0.id == "live-public" }) && !(snapshot.deletedServerIDs ?? []).contains("live-public") {
            snapshot.servers.append(NewsServer(id: "live-public", title: "news.twonil.hk · Live", host: "news.twonil.hk", name: "", email: "", groups: ["general.chat", "test.test"]))
        }
        if snapshot.servers.contains(where: { $0.id == "demo" }) && !snapshot.threads.contains(where: { $0.id == "native-scroll-demo" }) { snapshot.threads.append(scrollDemoThread()) }
        if snapshot.migrateSenderIPParser() { save() }
    }
    func save() {
        writer.schedule(snapshot) { [weak self] message in
            Task { @MainActor [weak self] in self?.storageError = "未能儲存：" + message }
        }
    }
    func markRead(_ id: String, threadID: String? = nil) {
        for t in snapshot.threads.indices where threadID == nil || snapshot.threads[t].id == threadID {
            if let m = snapshot.threads[t].messages.firstIndex(where: { $0.id == id }) { guard !snapshot.threads[t].messages[m].read else { return }
                snapshot.threads[t].messages[m].read = true
                if let server = snapshot.threads[t].serverID, let group = snapshot.threads[t].groupName {
                    let key = groupKey(server, group)
                    if let i = snapshot.liveGroups?[key]?.messages.firstIndex(where: { $0.id == id }) { snapshot.liveGroups?[key]?.messages[i].read = true }
                }
                return }
        }
    }
    func refresh(group: String = "general.chat") {
        var updated = snapshot
        var count = 0
        var pending = updated.pending
        pending.removeAll { reply in
            if let thread = reply.newThread {
                guard (thread.groupName ?? "general.chat") == group else { return false }
                if !updated.threads.contains(where: { $0.id == thread.id }) { updated.threads.insert(thread, at: 0); count += 1 }
                return true
            }
            guard let t = updated.threads.firstIndex(where: { $0.id == reply.threadID }), (updated.threads[t].groupName ?? "general.chat") == group else { return false }
            if !updated.threads[t].messages.contains(where: { $0.id == reply.message.id }) { updated.threads[t].messages.append(reply.message); count += 1 }
            return true
        }
        updated.pending = pending
        if updated.refreshCounts == nil { updated.refreshCounts = [:] }
        updated.refreshCounts?[groupKey("demo", group)] = count
        snapshot = updated
    }
    func catalog(_ server: NewsServer) async throws -> [String] {
        try await Task.detached {
            let client = try NNTPClient(host: server.host, port: server.port); defer { client.close() }
            return try client.groups()
        }.value
    }
    func available(_ server: NewsServer, _ group: String) async throws -> [Int] {
        try await Task.detached {
            let client = try NNTPClient(host: server.host, port: server.port); defer { client.close() }
            return try client.available(group)
        }.value
    }
    func rebuild(server: NewsServer, group: String) {
        let cache = snapshot.liveGroups?[groupKey(server.id, group)] ?? LiveGroupCache()
        var updated = snapshot
        updated.threads.removeAll { $0.serverID == server.id && $0.groupName == group }
        updated.threads += liveThreads(cache, server: server.id, group: group)
        snapshot = updated
    }
    func download(server: NewsServer, group: String, numbers: [Int]) async {
        guard !busy else { return }; busy = true; defer { busy = false; progress = "" }
        setRefreshCount(server: server.id, group: group, count: 0)
        var downloaded = 0
        do {
            for offset in stride(from: 0, to: numbers.count, by: 500) {
                try Task.checkCancellation()
                let batch = Array(numbers[offset..<min(offset+500, numbers.count)])
                progress = "Downloading \(offset)/\(numbers.count)"
                let headers = try await Task.detached {
                    let client = try NNTPClient(host: server.host, port: server.port); defer { client.close() }
                    var messages = try client.headers(group: group, numbers: batch)
                    let ips = try client.senderIPs(group: group, numbers: batch)
                    for i in messages.indices { messages[i].senderIP = ips[messages[i].articleNumber ?? 0]; messages[i].senderIPChecked = true }
                    return messages
                }.value
                let key = groupKey(server.id, group)
                var cache = snapshot.liveGroups?[key] ?? LiveGroupCache()
                var known = Set(cache.messages.map(\.id))
                for message in headers where known.insert(message.id).inserted { cache.messages.append(message); downloaded += 1 }
                setRefreshCount(server: server.id, group: group, count: downloaded)
                if snapshot.liveGroups == nil { snapshot.liveGroups = [:] }
                snapshot.liveGroups?[key] = cache
                rebuild(server: server, group: group)
            }
        } catch { storageError = error.localizedDescription }
    }
    func loadArticle(_ id: String, threadID: String? = nil) async {
        guard !loadingArticles.contains(id),
              let thread = snapshot.threads.first(where: { (threadID == nil || $0.id == threadID) && $0.messages.contains(where: { $0.id == id }) }),
              let sid = thread.serverID, let group = thread.groupName,
              let server = snapshot.servers.first(where: { $0.id == sid }),
              let message = thread.messages.first(where: { $0.id == id }), message.bodyLoaded != true, let number = message.articleNumber else { return }
        loadingArticles.insert(id); defer { loadingArticles.remove(id) }
        do {
            let article = try await Task.detached {
                let client = try NNTPClient(host: server.host, port: server.port); defer { client.close() }
                return try client.article(group: group, number: number)
            }.value
            let key = groupKey(sid, group)
            if let i = snapshot.liveGroups?[key]?.messages.firstIndex(where: { $0.id == id }) {
                snapshot.liveGroups?[key]?.messages[i].body = article.body
                snapshot.liveGroups?[key]?.messages[i].images = article.images
                snapshot.liveGroups?[key]?.messages[i].warnings = article.warnings
                snapshot.liveGroups?[key]?.messages[i].bodyLoaded = true
                snapshot.liveGroups?[key]?.messages[i].senderIP = article.senderIP
                snapshot.liveGroups?[key]?.messages[i].senderIPChecked = true
                rebuild(server: server, group: group)
            }
        } catch { storageError = error.localizedDescription }
    }

    func setRefreshCount(server: String, group: String, count: Int) {
        if snapshot.refreshCounts == nil { snapshot.refreshCounts = [:] }
        snapshot.refreshCounts?[groupKey(server, group)] = count
    }
    func visibleThread(_ thread: NewsThread) -> NewsThread? {
        let blocked = snapshot.servers.first { $0.id == (thread.serverID ?? "demo") }?.blockedUsers ?? []
        return thread.visible(blocked: blocked)
    }
    func updateMessages(threadID: String, change: (inout NewsMessage) -> Void) {
        guard let t = snapshot.threads.firstIndex(where: { $0.id == threadID }) else { return }
        var updated = snapshot
        for i in updated.threads[t].messages.indices { change(&updated.threads[t].messages[i]) }
        if let sid = updated.threads[t].serverID, let group = updated.threads[t].groupName {
            let byID = Dictionary(updated.threads[t].messages.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            let key = groupKey(sid, group)
            if var cache = updated.liveGroups?[key] {
                for i in cache.messages.indices { if let message = byID[cache.messages[i].id] { cache.messages[i] = message } }
                updated.liveGroups?[key] = cache
            }
        }
        snapshot = updated
    }
    func favourite(_ messageID: String, threadID: String) {
        updateMessages(threadID: threadID) { if $0.id == messageID { $0.favourite = !($0.favourite ?? false) } }
    }
    func markThreadRead(_ threadID: String) { updateMessages(threadID: threadID) { $0.read = true } }
    func sourceIP(message: NewsMessage, serverID: String, group: String) async throws -> String? {
        if message.senderIPChecked == true || message.senderIP != nil { return message.senderIP }
        guard let server = snapshot.servers.first(where: { $0.id == serverID }), server.id != "demo", let number = message.articleNumber else { return nil }
        return try await Task.detached {
            let client = try NNTPClient(host: server.host, port: server.port); defer { client.close() }
            return try client.senderIPs(group: group, numbers: [number])[number]
        }.value
    }
    func hydrateSourceIPs(server: NewsServer) async throws {
        let cachedGroups = (snapshot.liveGroups ?? [:]).keys.filter { $0.hasPrefix(server.id + "|") }.map { String($0.dropFirst(server.id.count + 1)) }
        for group in Set(server.groups + cachedGroups).sorted() {
            let key = groupKey(server.id, group)
            let missing = (snapshot.liveGroups?[key]?.messages ?? []).filter { $0.senderIPChecked != true }.compactMap(\.articleNumber).sorted()
            for offset in stride(from: 0, to: missing.count, by: 500) {
                let batch = Array(missing[offset..<min(offset+500, missing.count)])
                progress = "Checking sender IPs: \(group) \(offset)/\(missing.count)"
                let ips = try await Task.detached {
                    let client = try NNTPClient(host: server.host, port: server.port); defer { client.close() }
                    return try client.senderIPs(group: group, numbers: batch)
                }.value
                var updated = snapshot
                if var cache = updated.liveGroups?[key] {
                    let numbers = Set(batch)
                    for i in cache.messages.indices where cache.messages[i].articleNumber.map({ numbers.contains($0) }) == true {
                        cache.messages[i].senderIP = ips[cache.messages[i].articleNumber!]; cache.messages[i].senderIPChecked = true
                    }
                    updated.liveGroups?[key] = cache
                }
                snapshot = updated; rebuild(server: server, group: group)
            }
        }
    }
    func repairBlockedSources(server: NewsServer) async throws {
        guard !(snapshot.servers.first { $0.id == server.id }?.blockedUsers ?? []).isEmpty else { return }
        while busy { try await Task.sleep(for: .milliseconds(100)) }
        try Task.checkCancellation()
        busy = true; defer { busy = false; progress = "" }
        try await hydrateSourceIPs(server: server)
    }
    func blockUser(_ user: BlockedUser, serverID: String) async throws {
        guard !busy, let server = snapshot.servers.first(where: { $0.id == serverID }) else { throw NewsError.failure("請等目前下載完成再試") }
        busy = true; defer { busy = false; progress = "" }
        // Resolve cached source headers first; failures leave the block confirmation open.
        if server.id != "demo" { try await hydrateSourceIPs(server: server) }
        guard let i = snapshot.servers.firstIndex(where: { $0.id == serverID }) else { return }
        var users = snapshot.servers[i].blockedUsers ?? []
        users.removeAll { $0.ip == user.ip }; users.append(user)
        snapshot.servers[i].blockedUsers = users
    }
    func deleteServer(_ id: String) {
        guard !busy, loadingArticles.isEmpty else { storageError = "請等目前載入完成再刪除 server"; return }
        var updated = snapshot
        updated.deleteServer(id)
        snapshot = updated
    }
    func unblock(_ ip: String, serverID: String) {
        if let i = snapshot.servers.firstIndex(where: { $0.id == serverID }) { snapshot.servers[i].blockedUsers?.removeAll { $0.ip == ip } }
    }
    func searchBodies(server: NewsServer, group: String) async throws {
        guard !busy else { throw NewsError.failure("請等目前下載完成再搜尋內文") }
        busy = true; defer { busy = false; progress = "" }
        let key = groupKey(server.id, group)
        let missing = (snapshot.liveGroups?[key]?.messages ?? []).filter { $0.bodyLoaded != true && $0.searchBody == nil }
        for offset in stride(from: 0, to: missing.count, by: 10) {
            try Task.checkCancellation()
            let batch = Array(missing[offset..<min(offset+10, missing.count)])
            progress = "Searching message bodies \(offset)/\(missing.count)"
            let task = Task.detached {
                let client = try NNTPClient(host: server.host, port: server.port); defer { client.close() }
                var results: [(String, String, String?)] = []
                for message in batch {
                    try Task.checkCancellation()
                    guard let number = message.articleNumber else { continue }
                    let article = try client.article(group: group, number: number)
                    results.append((message.id, article.body, article.senderIP))
                }
                return results
            }
            let results = try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
            var updated = snapshot
            for (id, text, ip) in results {
                if let i = updated.liveGroups?[key]?.messages.firstIndex(where: { $0.id == id }) {
                    // Search caches text only; images still load when opening the article.
                    updated.liveGroups?[key]?.messages[i].searchBody = text
                    updated.liveGroups?[key]?.messages[i].senderIP = ip
                    updated.liveGroups?[key]?.messages[i].senderIPChecked = true
                }
            }
            snapshot = updated; rebuild(server: server, group: group)
        }
    }

    func replyHistory(thread: NewsThread, message: NewsMessage) async throws -> String {
        guard let sid = thread.serverID, let group = thread.groupName, let server = snapshot.servers.first(where: { $0.id == sid }) else { return thread.history(replyingTo: message.id) }
        let ids = Array((message.references ?? []).suffix(3)) + [message.id]
        let cached = snapshot.liveGroups?[groupKey(sid, group)]?.messages ?? []
        let history = try await Task.detached {
            let client = try NNTPClient(host: server.host, port: server.port); defer { client.close() }
            var messages: [NewsMessage] = []
            for id in ids {
                var entry: NewsMessage
                if let existing = cached.first(where: { $0.id == id }), existing.bodyLoaded == true { entry = existing }
                else {
                    let raw = try client.rawArticle(group: group, identifier: id), headers = articleHeaders(raw), decoded = try decodeArticle(raw)
                    entry = NewsMessage(id: id, author: decodeWords(headers["from"] ?? ""), body: decoded.body)
                }
                entry.parentID = messages.last?.id; messages.append(entry)
            }
            return NewsThread(id: "history", subject: thread.subject, messages: messages).history(replyingTo: message.id)
        }.value
        return history
    }
    func saveReplyDraft(_ draft: ReplyDraft, key: String) {
        guard let sid = key.split(separator: "|").first, snapshot.servers.contains(where: { $0.id == String(sid) }) else { return }
        if snapshot.replyDrafts == nil { snapshot.replyDrafts = [:] }
        snapshot.replyDrafts?[key] = draft
    }
    func submitReply(draft: ReplyDraft, server: NewsServer, group: String, subject: String, refs: [String]) async throws {
        let bytes = try buildReply(draft: draft, server: server, group: group, subject: subject, refs: refs)
        try await Task.detached {
            let client = try NNTPClient(host: server.host, port: server.port); defer { client.close() }
            func existing() throws -> Bool? {
                do { return try matchingArticle(client.rawArticle(group: group, identifier: draft.messageID), bytes) }
                catch { if error.localizedDescription.hasPrefix("430") { return nil }; throw error }
            }
            if let match = try existing() {
                guard match else { throw NewsError.failure("相同 Message-ID 嘅內容或附件唔一致；草稿保留，請先檢查") }
                return
            }
            if draft.status == "uncertain" || draft.status == "duplicate" {
                throw NewsError.failure("未能確認上次發送結果；草稿同附件保留。請先 Refresh 檢查，唔會自動重發。")
            }
            do { try client.post(bytes) }
            catch {
                if error.localizedDescription.localizedCaseInsensitiveContains("duplicate") {
                    if (try? existing()) == true { return }
                }
                throw error
            }
        }.value
    }

}

@main
struct YrNewsExApp: App {
    @StateObject private var store = ReaderStore()
    var body: some Scene {
        WindowGroup {
            GroupsScreen().environmentObject(store).preferredColorScheme(.dark).tint(.blue)
                .alert("操作未能完成", isPresented: Binding(get: { store.storageError != nil }, set: { if !$0 { store.storageError = nil } })) {
                    Button("OK") { store.storageError = nil }
                } message: { Text(store.storageError ?? "") }
        }
    }
}

struct ReaderHeader<Left: View, Right: View>: View {
    var title: String = ""
    @ViewBuilder var left: () -> Left
    @ViewBuilder var right: () -> Right
    var body: some View {
        ZStack {
            Text(title).font(.system(size: 16, weight: .semibold)).lineLimit(1).padding(.horizontal, 100)
            HStack { left(); Spacer(); right() }.foregroundStyle(Color(red: 0.04, green: 0.52, blue: 1))
        }.frame(height: 44).padding(.horizontal, 12).background(.black).buttonStyle(.plain).tint(Color(red: 0.04, green: 0.52, blue: 1))
    }
}
struct ReaderBottom<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        HStack { content() }.foregroundStyle(Color(red: 0.04, green: 0.52, blue: 1)).frame(height: 48).padding(.horizontal, 16)
            .background(Color(white: 0.15).ignoresSafeArea(edges: .bottom)).buttonStyle(.plain)
    }
}
struct ReaderAction: Identifiable {
    var title: String
    var action: () -> Void
    var id: String { title }
}
/// Flat action sheet keeps the yrNews layout on newer iOS versions too.
struct ReaderActionSheet: View {
    var title: String? = nil
    var items: [ReaderAction]
    var cancel: () -> Void
    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.5).ignoresSafeArea().onTapGesture(perform: cancel)
            VStack(spacing: 8) {
                VStack(spacing: 0) {
                    if let title { Text(title).font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 36); Divider() }
                    ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                        if index > 0 { Divider().overlay(Color(white: 0.3)) }
                        Button { cancel(); item.action() } label: {
                            Text(item.title).font(.system(size: 20)).frame(maxWidth: .infinity, minHeight: 58)
                        }
                    }
                }.background(Color(white: 0.14), in: RoundedRectangle(cornerRadius: 14))
                Button(action: cancel) { Text("Cancel").font(.system(size: 20, weight: .semibold)).frame(maxWidth: .infinity, minHeight: 58) }
                    .background(Color(white: 0.16), in: RoundedRectangle(cornerRadius: 14))
            }.foregroundStyle(Color(red: 0.04, green: 0.52, blue: 1)).buttonStyle(.plain).padding(.horizontal, 8).padding(.bottom, 8)
        }.accessibilityAddTraits(.isModal)
    }
}

struct ReaderBack: View {
    var title: String
    var action: () -> Void
    var body: some View {
        Button(action: action) { HStack(spacing: 4) { Image(systemName: "chevron.left").font(.system(size: 17)); Text(title).lineLimit(1) }.frame(minHeight: 44) }
    }
}
struct GroupsScreen: View {
    @EnvironmentObject var store: ReaderStore
    @State private var query = ""
    @State private var settings: NewsServer?
    @State private var adding = false
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 0) {
                    Text("Groups").font(.system(size: 34, weight: .bold)).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.bottom, 8)
                    ReaderSearch(text: $query)
                    ForEach(store.snapshot.servers) { server in
                        Button { settings = server } label: {
                            HStack { Text(server.title).fontWeight(.semibold); Spacer(); Image(systemName: "chevron.right").foregroundStyle(.gray) }
                                .padding(12).background(Color(white: 0.15)).foregroundStyle(.white)
                        }
                        ForEach(server.groups.filter { query.isEmpty || $0.localizedCaseInsensitiveContains(query) }.map { groupKey(server.id, $0) }, id: \.self) { rowID in
                            let group = String(rowID.dropFirst(server.id.count + 1))
                            NavigationLink { ThreadScreen(server: server, group: group) } label: {
                                HStack { Text(group); Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(.gray) }.padding(.horizontal, 16).frame(minHeight: 48).foregroundStyle(.white)
                            }
                            Divider().overlay(Color(white: 0.1))
                        }
                    }
                    Text("Demo 為本機示例；Live 可直接連線閱讀 NNTP").font(.footnote).foregroundStyle(.secondary).padding(20)
                }
            }
            .background(.black).toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                ReaderHeader { Color.clear.frame(width: 44, height: 44) } right: {
                    Button { adding = true } label: { Image(systemName: "plus").font(.system(size: 23)).frame(width: 44, height: 44) }.accessibilityLabel("Add Server")
                }
            }
            .sheet(item: $settings) { server in ServerEditor(server: server, isNew: false) }
            .sheet(isPresented: $adding) { ServerEditor(server: NewsServer(title: "", host: "", name: "", email: "", groups: []), isNew: true) }
        }
    }
}

struct ServerEditor: View {
    @EnvironmentObject var store: ReaderStore
    @Environment(\.dismiss) var dismiss
    @State var server: NewsServer
    @State private var confirmingDelete = false
    var isNew: Bool
    var body: some View {
        NavigationStack {
            Form {
                Section("Server") {
                    TextField("Title", text: $server.title)
                    TextField("News Server", text: $server.host).textInputAutocapitalization(.never).autocorrectionDisabled().disabled(!isNew)
                    TextField("Port", value: $server.port, format: .number).keyboardType(.numberPad).disabled(!isNew)
                }
                Section("Posting identity") {
                    TextField("Name", text: $server.name)
                    TextField("Email", text: $server.email).textInputAutocapitalization(.never).keyboardType(.emailAddress).autocorrectionDisabled()
                }
                if !isNew {
                    Section("Blocked Users") {
                        let users = store.snapshot.servers.first { $0.id == server.id }?.blockedUsers ?? []
                        if users.isEmpty { Text("未有封鎖用戶").foregroundStyle(.secondary) }
                        ForEach(users) { user in
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Username: \(user.username)")
                                Text("Email: \(user.email)")
                                Text("IP: \(user.ip)").monospaced()
                                Button("Unblock", role: .destructive) { store.unblock(user.ip, serverID: server.id) }
                            }.font(.subheadline).textSelection(.enabled)
                        }
                    }
                }
                Section {
                    NavigationLink("Subscribe Group") { SubscriptionScreen(selection: $server.groups, server: server) }
                } footer: { Text("Live 會直接連線載入群組及文章；119 普通 NNTP，563 TLS。暫未支援帳密登入；支援發文及最多三張相片。Name／Email 會隨發文公開顯示。") }
                if !isNew {
                    Section {
                        Button("Delete Server", role: .destructive) { confirmingDelete = true }
                            .disabled(store.busy || !store.loadingArticles.isEmpty)
                    } footer: { Text("移除此 server、訂閱、本機文章、草稿、收藏及封鎖清單。唔會刪除 server 上嘅文章，亦唔影響其他 servers。") }
                }
            }
            .alert("Delete Server?", isPresented: $confirmingDelete) {
                Button("Cancel", role: .cancel) { }
                Button("Delete Server", role: .destructive) { store.deleteServer(server.id); dismiss() }
            } message: { Text("確定刪除「\(server.title.isEmpty ? server.host : server.title)」及佢嘅所有本機資料？未發送草稿亦會移除。此操作無法還原。") }
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                ReaderHeader(title: isNew ? "Add Server" : "Server") {
                    Button("Cancel") { dismiss() }.frame(minHeight: 44)
                } right: {
                    Button("Done") {
                        if let i = store.snapshot.servers.firstIndex(where: { $0.id == server.id }) { server.blockedUsers = store.snapshot.servers[i].blockedUsers; store.snapshot.servers[i] = server }
                        else { store.snapshot.servers.append(server) }
                        dismiss()
                    }.frame(minHeight: 44).disabled(server.host.trimmingCharacters(in: .whitespaces).isEmpty || !(1...65535).contains(server.port))
                }
            }
        }
    }
}
struct SubscriptionScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: [String]
    @State private var query = ""
    var server: NewsServer
    @EnvironmentObject var store: ReaderStore
    @State private var groups = [String]()
    @State private var loading = false
    @State private var errorText: String?

    var body: some View {
        List {
            if loading { ProgressView("Loading groups…") }
            if let errorText { Text(errorText).foregroundStyle(.orange); Button("Retry") { Task { await loadGroups() } } }
            ForEach(groups.filter { query.isEmpty || $0.localizedCaseInsensitiveContains(query) }, id: \.self) { group in
            Button {
                if selection.contains(group) { selection.removeAll { $0 == group } } else { selection.append(group) }
            } label: { HStack { Text(group).foregroundStyle(.white); Spacer(); if selection.contains(group) { Image(systemName: "checkmark") } } }
            }
        }.task { await loadGroups() }.toolbar(.hidden, for: .navigationBar).navigationBarBackButtonHidden(true)
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 0) {
                    ReaderHeader(title: "Subscribe Group") { ReaderBack(title: "Server") { dismiss() } } right: { EmptyView() }
                    ReaderSearch(text: $query)
                }.background(.black)
            }
    }
    func loadGroups() async {
        loading = true; errorText = nil; defer { loading = false }
        if server.id == "demo" { groups = ["club.arsenal", "club.liverpool", "general.chat", "general.soccer_n_chat", "test.test"]; return }
        do { groups = try await store.catalog(server) } catch { errorText = error.localizedDescription }
    }

}

struct ReadingItem: Identifiable {
    var threadID: String
    var messageID: String
    var id: String { messageID }
}
struct ReadingSession: Identifiable, Hashable {
    var route: [ReadingItem]
    var initial: ReadingItem
    var id: String { initial.id }
}
struct ThreadScreen: View {
    @EnvironmentObject var store: ReaderStore
    var server: NewsServer
    var group: String
    @State private var expanded = Set<String>()
    @State private var query = ""
    @State private var searchScope = "Subject"
    @State private var searching = false
    @FocusState private var searchFocused: Bool
    @State private var unreadOnly = false
    @State private var favouritesOnly = false
    @State private var latestReply = false
    @State private var actions = false
    @State private var composing = false
    @State private var blockTarget: BlockTarget?
    @State private var reading: ReadingSession?
    @State private var edgeBackActive = false
    @Environment(\.dismiss) private var dismiss
    @State private var availableNumbers: [Int] = []
    @State private var downloadDialog = false
    @State private var checking = false
    @State private var quantity = 500
    @State private var customQuantity = "500"
    var threads: [NewsThread] {
        var result = store.snapshot.threads.compactMap { t -> NewsThread? in
            let belongs = server.id == "demo" ? (t.serverID == nil && (t.groupName ?? "general.chat") == group) : (t.serverID == server.id && t.groupName == group)
            guard belongs, let visible = store.visibleThread(t), (!unreadOnly || visible.unread > 0), (!favouritesOnly || visible.messages.contains { $0.favourite == true }), visible.matches(query, scope: searchScope) else { return nil }
            return visible
        }
        if latestReply { result.sort { ($0.messages.compactMap(\.articleNumber).max() ?? 0) > ($1.messages.compactMap(\.articleNumber).max() ?? 0) } }
        return result
    }
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if !searching { Text(group).font(.system(size: 34, weight: .bold)).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.bottom, 8) }
                searchBar
                if checking { ProgressView("Checking new messages…").padding() }
                if store.busy { ProgressView(store.progress).padding() }
                if threads.isEmpty { Text(query.isEmpty ? "未有符合條件嘅本機文章" : "搵唔到符合嘅文章").foregroundStyle(.secondary).padding(30) }
                ForEach(threads) { thread in
                    VStack(spacing: 0) {
                        ForEach(expanded.contains(thread.id) ? thread.tree : Array(thread.tree.prefix(1)), id: \.message.id) { entry in
                            messageRow(thread, entry.message, depth: entry.depth)
                            Divider().overlay(Color(white: 0.08))
                        }
                    }.background(HorizontalSwipe { _ in toggle(thread.id) })
                }
            }.background(EdgeBack(active: edgeBackActive && !downloadDialog && !actions && blockTarget == nil && reading == nil && !composing) { dismiss() })
        }
        .onAppear { edgeBackActive = true }.onDisappear { edgeBackActive = false }
        .scrollIndicators(.hidden).background(.black).toolbar(.hidden, for: .navigationBar).navigationBarBackButtonHidden(true)
        .safeAreaInset(edge: .top, spacing: 0) {
            if !searching {
                ReaderHeader { ReaderBack(title: "Groups") { dismiss() } } right: {
                    Button { if server.id == "demo" { store.refresh(group: group) } else { Task { await checkMessages() } } } label: { Image(systemName: "arrow.clockwise").font(.system(size: 21)).frame(width: 44, height: 44) }.accessibilityLabel("Refresh").disabled(checking || store.busy)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !searching {
                ReaderBottom {
                    Button { composing = true } label: { Image(systemName: "square.and.pencil").font(.system(size: 23)).frame(width: 44, height: 44) }.accessibilityLabel("New post")
                    Spacer()
                    Text("\(store.snapshot.refreshCounts?[groupKey(server.id, group)] ?? 0) New Messages").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                    Spacer()
                    Button { actions = true } label: { Image(systemName: "square.and.arrow.up").font(.system(size: 23)).frame(width: 44, height: 44) }.accessibilityLabel("Thread actions")
                }
            }
        }
        .task {
            if server.id != "demo" {
                store.rebuild(server: server, group: group)
                do { try await store.repairBlockedSources(server: server) }
                catch is CancellationError { }
                catch { store.storageError = "未能補讀封鎖所需嘅來源 headers：" + error.localizedDescription }
            }
        }
        .task(id: searchScope + "|" + query) {
            guard searching, searchScope == "Message", !query.isEmpty, server.id != "demo" else { return }
            do {
                try await Task.sleep(for: .milliseconds(500))
                while store.busy { try await Task.sleep(for: .milliseconds(100)) }
                try await store.searchBodies(server: server, group: group)
            }
            catch is CancellationError { }
            catch { store.storageError = error.localizedDescription }
        }
        .overlay {
            if actions {
                ReaderActionSheet(items: [
                    ReaderAction(title: "Mark All Read", action: markAllRead),
                    ReaderAction(title: unreadOnly ? "Show All Messages" : "Show Unread Only", action: { unreadOnly.toggle() }),
                    ReaderAction(title: favouritesOnly ? "Show All Messages" : "Show Favourites Only", action: { favouritesOnly.toggle() }),
                    ReaderAction(title: latestReply ? "Sort Threads by Original Post" : "Sort Threads by Latest Reply", action: { latestReply.toggle() })
                ], cancel: { actions = false })
            }
        }
        .sheet(item: $blockTarget) { target in BlockUserSheet(target: target) { } }
        .sheet(isPresented: $composing) {
            ReplyScreen(thread: NewsThread(id: "new|" + groupKey(server.id, group), subject: "", messages: [], serverID: server.id == "demo" ? nil : server.id, groupName: group), message: NewsMessage(id: "new", author: "", body: ""), isNewPost: true, onSent: { composing = false })
        }
        .sheet(isPresented: $downloadDialog) {
            VStack(spacing: 20) {
                Text("\(availableNumbers.count) new messages").font(.headline)
                Text("Next 由本機最新已下載文章之後開始；Latest 取最新一批。").font(.footnote).foregroundStyle(.secondary)
                Picker("Download", selection: $quantity) { Text("500").tag(500); Text("1,000").tag(1000); Text("2,000").tag(2000); Text("More…").tag(-1); Text("All").tag(0) }.pickerStyle(.menu)
                if quantity == -1 { TextField("Quantity", text: $customQuantity).keyboardType(.numberPad).textFieldStyle(.roundedBorder) }
                Button("Next \(chosenCount)") { startDownload(latest: false) }.disabled(chosenCount < 1)
                Button("Latest \(chosenCount)") { startDownload(latest: true) }.disabled(chosenCount < 1)
                Button("Cancel") { downloadDialog = false }
            }.padding(24).presentationDetents([.medium, .large])
        }
        .navigationDestination(item: $reading) { item in ArticleScreen(route: item.route, initial: item.initial, onReplySent: { reading = nil }) }
    }
    var searchBar: some View {
        VStack(spacing: 8) {
            HStack {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.gray)
                    TextField("搜尋", text: $query).textInputAutocapitalization(.never).autocorrectionDisabled().focused($searchFocused).submitLabel(.search)
                        .onChange(of: searchFocused) { _, value in if value { searching = true } }
                    if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.gray) } }
                }.padding(10).background(Color(white: 0.11), in: RoundedRectangle(cornerRadius: 10))
                if searching { Button("取消") { query = ""; searchFocused = false; searching = false } }
            }
            if searching {
                Picker("Search scope", selection: $searchScope) { Text("Subject").tag("Subject"); Text("Sender").tag("Sender"); Text("Message").tag("Message") }.pickerStyle(.segmented)
                if searchScope == "Message" { Text("搜尋本機已下載文章；未載入嘅內文會連線載入。").font(.caption).foregroundStyle(.secondary) }
            }
        }.padding(.horizontal, 16).padding(.vertical, 8)
    }
    func messageRow(_ thread: NewsThread, _ message: NewsMessage, depth: Int) -> some View {
        HStack(spacing: 8) {
            Circle().fill(message.read ? Color.clear : Color.blue).frame(width: 6, height: 6)
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(message.subject ?? (depth == 0 ? thread.subject : "Re: \(thread.subject)")).font(.system(size: 17)).foregroundStyle(message.read ? .gray : .white).lineLimit(1)
                    if message.favourite == true { Image(systemName: "star.fill").font(.caption).foregroundStyle(.yellow) }
                }
                Text(message.author).font(.system(size: 13)).foregroundStyle(.gray).lineLimit(1)
            }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                .onTapGesture {
                    let route = threads.flatMap { t in t.tree.map { ReadingItem(threadID: t.id, messageID: $0.message.id) } }
                    reading = ReadingSession(route: route, initial: ReadingItem(threadID: thread.id, messageID: message.id))
                }.accessibilityAddTraits(.isButton)
            if depth == 0 {
                if thread.messages.count > 1 {
                    Button { toggle(thread.id) } label: {
                        Text("\(thread.unread)/\(thread.messages.count)").font(.system(size: 15, weight: .semibold)).foregroundStyle(thread.unread > 0 ? .blue : .gray)
                            .padding(.horizontal, 7).padding(.vertical, 5).overlay(RoundedRectangle(cornerRadius: 10).stroke(.gray, lineWidth: 1))
                            .frame(minWidth: 44, minHeight: 44)
                    }.accessibilityLabel("Toggle thread")
                } else { Image(systemName: "chevron.right").foregroundStyle(.gray).frame(width: 32) }
            }
        }.padding(.leading, 12 + CGFloat(min(depth, 12)) * 18).padding(.trailing, 12).frame(minHeight: 70).contentShape(Rectangle())
            .onLongPressGesture { blockTarget = BlockTarget(message: message, serverID: server.id, group: group) }
    }
    var chosenCount: Int { min(availableNumbers.count, quantity == 0 ? availableNumbers.count : quantity == -1 ? max(0, Int(customQuantity) ?? 0) : quantity) }
    func checkMessages() async {
        guard !checking, !store.busy else { return }
        checking = true; defer { checking = false }
        do {
            let all = try await store.available(server, group)
            try Task.checkCancellation()
            let cache = store.snapshot.liveGroups?[groupKey(server.id, group)] ?? LiveGroupCache()
            let known = Set(cache.messages.compactMap(\.articleNumber))
            availableNumbers = all.filter { !known.contains($0) && $0 > (cache.newest ?? 0) }
            if availableNumbers.count > 500 { quantity = 500; downloadDialog = true }
            else { await store.download(server: server, group: group, numbers: availableNumbers) }
        } catch is CancellationError { return }
        catch { store.storageError = error.localizedDescription }
    }
    func startDownload(latest: Bool) {
        let count = chosenCount; guard count > 0 else { return }
        let numbers = latest ? Array(availableNumbers.suffix(count)) : Array(availableNumbers.prefix(count))
        downloadDialog = false
        Task { await store.download(server: server, group: group, numbers: numbers) }
    }
    func markAllRead() {
        for thread in store.snapshot.threads where server.id == "demo" ? (thread.serverID == nil && (thread.groupName ?? "general.chat") == group) : (thread.serverID == server.id && thread.groupName == group) { store.markThreadRead(thread.id) }
    }
    func toggle(_ id: String) { if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) } }
}
struct BlockTarget: Identifiable {
    var message: NewsMessage
    var serverID: String
    var group: String
    var id: String { serverID + "|" + message.id }
}
struct BlockUserSheet: View {
    @EnvironmentObject var store: ReaderStore
    @Environment(\.dismiss) var dismiss
    var target: BlockTarget
    var onBlocked: () -> Void
    @State private var ip: String?
    @State private var loading = true
    @State private var saving = false
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Block 呢個用戶？").font(.title3).bold()
            Text("Username: \(senderIdentity(target.message.author).name)")
            Text("Email: \(senderIdentity(target.message.author).email)")
            Text("Sender IP: \(ip ?? (loading ? "讀取中…" : "未有提供"))").monospaced()
            Text("此 server 所有 groups 內，相同 sender IP 嘅 messages 及子回覆串都會隱藏；共用 IP 嘅人亦會受影響。").font(.footnote).foregroundStyle(.secondary)
            if loading || saving { ProgressView(saving ? store.progress : "讀取文章 sender IP…") }
            if let error { Text(error).font(.footnote).foregroundStyle(.orange) }
            if !loading && ip == nil { Text("文章未提供有效 sender IP，無法按 IP Block。").font(.footnote) }
            Button("Block 此 IP", role: .destructive) {
                guard let ip else { return }; saving = true
                Task {
                    do {
                        let identity = senderIdentity(target.message.author)
                        try await store.blockUser(BlockedUser(username: identity.name, email: identity.email, ip: ip), serverID: target.serverID)
                        dismiss(); onBlocked()
                    } catch { self.error = error.localizedDescription }
                    saving = false
                }
            }.disabled(loading || saving || ip == nil || store.busy).frame(maxWidth: .infinity, minHeight: 44)
            Button("取消") { dismiss() }.disabled(saving).frame(maxWidth: .infinity, minHeight: 44)
        }.padding(24).presentationDetents([.medium, .large]).interactiveDismissDisabled(saving)
        .task {
            defer { loading = false }
            do { ip = try await store.sourceIP(message: target.message, serverID: target.serverID, group: target.group) }
            catch { self.error = error.localizedDescription }
        }
    }
}

extension ReadingItem: Hashable {}
struct ArticleScreen: View {
    @EnvironmentObject var store: ReaderStore
    let route: [ReadingItem]
    let initial: ReadingItem
    @Environment(\.dismiss) private var dismiss
    var onReplySent: () -> Void
    @State private var index = 0
    @State private var composing = false
    @State private var actions = false
    @State private var blockTarget: BlockTarget?
    @State private var edgeBackActive = false
    init(route: [ReadingItem], initial: ReadingItem, onReplySent: @escaping () -> Void) {
        self.route = route; self.initial = initial; self.onReplySent = onReplySent
        _index = State(initialValue: route.firstIndex(of: initial) ?? 0)
    }
    var item: ReadingItem { route.indices.contains(index) ? route[index] : initial }
    var thread: NewsThread? { store.snapshot.threads.first { $0.id == item.threadID } }
    var message: NewsMessage? { thread?.messages.first { $0.id == item.messageID } }
    var body: some View {
        ScrollView {
            if let thread, let message {
                VStack(alignment: .leading, spacing: 14) {
                    Text(thread.subject).font(.title3).bold()
                    HStack {
                        Text(message.author).foregroundStyle(.secondary).textSelection(.enabled)
                        Spacer()
                        Button { blockTarget = BlockTarget(message: message, serverID: thread.serverID ?? "demo", group: thread.groupName ?? "general.chat") } label: {
                            Image(systemName: "person.crop.circle.badge.xmark").font(.system(size: 23)).frame(width: 44, height: 44)
                        }.accessibilityLabel("Block sender IP")
                    }
                    Divider()
                    if store.loadingArticles.contains(message.id) { ProgressView("Loading message…") }
                    if message.bodyLoaded == false && !store.loadingArticles.contains(message.id) { Button("Retry loading message") { Task { await store.loadArticle(message.id, threadID: item.threadID) } } }
                    NativeMessageBody(bodyText: replyTextSections(message.body).own)
                    ForEach(Array((message.images ?? []).enumerated()), id: \.offset) { _, data in
                        if let image = UIImage(data: data) { Image(uiImage: image).resizable().scaledToFit() }
                    }
                    if !replyTextSections(message.body).history.isEmpty { NativeMessageBody(bodyText: replyTextSections(message.body).history) }
                    ForEach(message.warnings ?? [], id: \.self) { Text($0).font(.footnote).foregroundStyle(.orange) }
                }.padding(16).frame(maxWidth: .infinity, minHeight: 800, alignment: .topLeading)
                    .background(HorizontalSwipe { move($0) })
                    .background(EdgeBack(active: edgeBackActive && !composing && !actions && blockTarget == nil) { dismiss() })
            }
            Color.clear.frame(height: 1)
                .frame(maxWidth: .infinity)
        }.id(item.messageID).background(.black).contentShape(Rectangle())
            .onAppear { edgeBackActive = true }.onDisappear { edgeBackActive = false }
            .scrollIndicators(.hidden).toolbar(.hidden, for: .navigationBar).navigationBarBackButtonHidden(true)
            .safeAreaInset(edge: .top, spacing: 0) {
                ReaderHeader { ReaderBack(title: thread?.groupName ?? "general.chat") { dismiss() } } right: { Color.clear.frame(width: 44, height: 44) }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                ReaderBottom {
                    Button { composing = true } label: { Image(systemName: "arrowshape.turn.up.left").frame(width: 44, height: 44) }.accessibilityLabel("Reply")
                    Spacer(minLength: 0)
                    Button { move(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }.disabled(index == 0).accessibilityLabel("Previous message")
                    Spacer(minLength: 0)
                    Button { move(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }.disabled(index + 1 >= route.count).accessibilityLabel("Next message")
                    Spacer(minLength: 0)
                    Button { moveThread(-1) } label: { Image(systemName: "chevron.up").frame(width: 44, height: 44) }.disabled(threadDestination(-1) == nil).accessibilityLabel("Previous thread")
                    Spacer(minLength: 0)
                    Button { moveThread(1) } label: { Image(systemName: "chevron.down").frame(width: 44, height: 44) }.disabled(threadDestination(1) == nil).accessibilityLabel("Next thread")
                    Spacer(minLength: 0)
                    Button { actions = true } label: { Image(systemName: "square.and.arrow.up").frame(width: 44, height: 44) }.accessibilityLabel("Message actions")
                }.font(.system(size: 23))
            }
            .overlay {
                if actions {
                    ReaderActionSheet(items: [
                        ReaderAction(title: message?.favourite == true ? "Remove Favourite" : "Mark As Favourite", action: { store.favourite(item.messageID, threadID: item.threadID) }),
                        ReaderAction(title: "Mark Thread Read", action: { store.markThreadRead(item.threadID) })
                    ], cancel: { actions = false })
                }
            }
            .sheet(item: $blockTarget) { target in BlockUserSheet(target: target) { dismiss() } }
            .task(id: item.messageID) { store.markRead(item.messageID, threadID: item.threadID); await store.loadArticle(item.messageID, threadID: item.threadID) }
            .sheet(isPresented: $composing) { if let thread, let message { ReplyScreen(thread: thread, message: message, onSent: onReplySent) } }
    }
    func threadDestination(_ delta: Int) -> Int? { adjacentThreadIndex(threadIDs: route.map(\.threadID), index: index, delta: delta) }
    func moveThread(_ delta: Int) { if let destination = threadDestination(delta) { index = destination; store.markRead(item.messageID, threadID: item.threadID) } }
    func move(_ delta: Int) {
        guard route.indices.contains(index + delta) else { return }
        index += delta; store.markRead(item.messageID, threadID: item.threadID)
    }
}
struct ReplyScreen: View {
    @EnvironmentObject var store: ReaderStore
    @Environment(\.dismiss) var dismiss
    var thread: NewsThread
    var message: NewsMessage
    var isNewPost = false
    var onSent: () -> Void
    @State private var draft = ReplyDraft()
    @State private var loadingHistory = true
    @State private var historyReady = false
    @State private var sending = false
    @State private var errorText: String?
    @State private var picker = false
    @State private var photoActions = false
    @State private var importing = false
    @State private var photoSlots = 3
    @State private var photoTask: Task<Void, Never>?
    @State private var camera = false
    @State private var settings = false
    var server: NewsServer? { store.snapshot.servers.first { $0.id == (thread.serverID ?? "demo") } }
    var draftKey: String { (thread.serverID ?? "demo") + "|" + (thread.groupName ?? "general.chat") + "|" + message.id }
    var isLive: Bool { thread.serverID != nil }
    var identityReady: Bool { guard let server else { return false }; return !server.name.isEmpty && server.email.contains("@") }
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                if isNewPost {
                    TextField("Subject", text: Binding(get: { draft.subject ?? "" }, set: { draft.subject = $0; edited() })).padding(12).disabled(sending)
                } else { Text("Re: \(thread.subject)").padding(12) }
                Divider()
                if loadingHistory { ProgressView("Loading reply history…").padding() }
                TextEditor(text: Binding(get: { draft.text }, set: { draft.text = $0; edited() }))
                    .scrollContentBackground(.hidden).scrollIndicators(.hidden).padding(8).disabled(loadingHistory || !historyReady || sending)
                if importing {
                    HStack {
                        ProgressView("Preparing photo…")
                        Spacer()
                        Button("Cancel") { photoTask?.cancel(); importing = false }
                    }.padding(12)
                }
                if isLive && !identityReady {
                    Button("先喺 Server 設定 Name／Email") { settings = true }.padding(12)
                }
                if let errorText { Text(errorText).font(.footnote).foregroundStyle(.orange).padding(12) }
                if !loadingHistory && !historyReady { Button("Retry history") { Task { await loadHistory() } }.padding(12) }
                if draft.status == "uncertain" || draft.status == "duplicate" {
                    Button("用新識別碼再試") { draft.changed(); saveDraft(); errorText = nil }.padding(12).disabled(sending)
                }
            }.background(.black).toolbar(.hidden, for: .navigationBar)
                .safeAreaInset(edge: .top, spacing: 0) {
                    HStack(spacing: 6) {
                        Button("Cancel") { dismiss() }.frame(minHeight: 44).disabled(sending)
                        Group {
                            if draft.photos.isEmpty { Text(isNewPost ? "New Post" : "Reply").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white) }
                            else {
                                HStack(spacing: 0) {
                                    ForEach(draft.photos) { photo in
                                        ZStack(alignment: .topTrailing) {
                                            ReplyPhotoThumbnail(photo: photo).clipShape(RoundedRectangle(cornerRadius: 4)).padding(4)
                                            Button { draft.photos.removeAll { $0.id == photo.id }; edited() } label: {
                                                Image(systemName: "xmark.circle.fill").font(.system(size: 14)).foregroundStyle(.white, .black).frame(width: 22, height: 22)
                                            }.accessibilityLabel("Remove photo").disabled(sending)
                                        }.frame(width: 44, height: 44)
                                    }
                                }
                            }
                        }.frame(maxWidth: .infinity)
                        HStack(spacing: 8) {
                            Button { photoActions = true } label: { Image(systemName: "camera").font(.system(size: 21)).frame(width: 44, height: 44) }
                            .accessibilityLabel("Attach Photo")
                            .disabled(draft.photos.count >= 3 || sending || importing || loadingHistory || !historyReady)
                            Button(sending ? "Sending…" : "Send") { Task { await send() } }.frame(minHeight: 44)
                                .disabled(sending || loadingHistory || !historyReady || importing || !identityReady || (isNewPost && (draft.subject ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) || (replyTextSections(draft.text).own.isEmpty && draft.photos.isEmpty))
                        }
                    }.frame(height: 52).padding(.horizontal, 12).background(.black).buttonStyle(.plain).foregroundStyle(Color(red: 0.04, green: 0.52, blue: 1))
                }
                .task { await loadHistory() }
                .overlay {
                    if photoActions {
                        ReaderActionSheet(title: "Attach Photo", items: [
                            ReaderAction(title: "Take New", action: {
                                if UIImagePickerController.isSourceTypeAvailable(.camera) { camera = true }
                                else { errorText = "模擬器冇相機；真 iPhone 可以影相。" }
                            }),
                            ReaderAction(title: "Choose Existing", action: { photoSlots = max(1, 3-draft.photos.count); picker = true })
                        ], cancel: { photoActions = false })
                    }
                }
                .sheet(isPresented: $picker) { AlbumPhotoPicker(limit: photoSlots) { assets in picker = false; importPhotos(assets) } }
                .onDisappear { photoTask?.cancel() }
                .sheet(isPresented: $camera) { CameraCapture { image in importCameraPhoto(image) } }
                .sheet(isPresented: $settings) { if let server { ServerEditor(server: server, isNew: false) } }
                .interactiveDismissDisabled(sending)

        }
    }
    func loadHistory() async {
        loadingHistory = true; defer { loadingHistory = false }
        if let saved = store.snapshot.replyDrafts?[draftKey] { draft = saved; historyReady = true; return }
        if isNewPost { historyReady = true; saveDraft(); return }
        do { draft.text = "\n\n" + (try await store.replyHistory(thread: thread, message: message)); historyReady = true; saveDraft(); errorText = nil }
        catch { errorText = "未能載入父訊息 history：" + error.localizedDescription }
    }
    func saveDraft() { store.saveReplyDraft(draft, key: draftKey) }
    func edited() { draft.changed(); saveDraft(); errorText = nil }
    func appendPhoto(_ photo: ReplyPhoto) throws {
        guard draft.photos.count < 3 else { throw NewsError.failure("最多三張相") }
        draft.photos.append(photo); edited()
    }
    func importPhotos(_ items: [PHAsset]) {
        guard !items.isEmpty, !importing else { return }
        importing = true; errorText = nil
        photoTask = Task {
            defer { if !Task.isCancelled { importing = false } }
            for item in items.prefix(max(0, 3-draft.photos.count)) {
                do {
                    try Task.checkCancellation()
                    let data = try await PhotoAssetDataRequest().load(item)
                    try Task.checkCancellation()
                    let photo = try await Task.detached(priority: .userInitiated) { try PhotoPreparation.prepare(data) }.value
                    try Task.checkCancellation()
                    try appendPhoto(photo)
                } catch is CancellationError { return }
                catch { if !Task.isCancelled { errorText = error.localizedDescription } }
            }
        }
    }
    func importCameraPhoto(_ image: UIImage) {
        guard !importing, draft.photos.count < 3 else { return }
        importing = true; errorText = nil
        photoTask = Task {
            defer { if !Task.isCancelled { importing = false } }
            do {
                let photo = try await Task.detached(priority: .userInitiated) {
                    try autoreleasepool {
                        let scale = min(1, CGFloat(PhotoPreparation.maxDimension) / max(image.size.width, image.size.height))
                        let size = CGSize(width: max(1, image.size.width * scale), height: max(1, image.size.height * scale))
                        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
                        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
                        guard let data = resized.jpegData(compressionQuality: 0.85) else { throw PhotoPreparation.PhotoError.invalid }
                        return try PhotoPreparation.prepare(data)
                    }
                }.value
                try Task.checkCancellation(); try appendPhoto(photo)
            } catch is CancellationError { }
            catch { if !Task.isCancelled { errorText = error.localizedDescription } }
        }
    }
    func send() async {
        guard let server, !sending else { return }
        sending = true; errorText = nil; defer { sending = false }
        if !isLive {
            var reply = NewsMessage(id: draft.messageID, parentID: message.id, author: server.name, body: draft.text)
            reply.images = draft.photos.map(\.data)
            if isNewPost {
                reply.parentID = nil
                let newThread = NewsThread(id: draft.messageID, subject: draft.subject ?? "", messages: [reply], groupName: thread.groupName)
                store.snapshot.pending.append(PendingReply(threadID: newThread.id, message: reply, newThread: newThread))
            } else { store.snapshot.pending.append(PendingReply(threadID: thread.id, message: reply)) }
            store.snapshot.replyDrafts?[draftKey] = nil; dismiss(); onSent(); return
        }
        let refs = isNewPost ? [] : (Array(NSOrderedSet(array: (message.references ?? []) + [message.id])) as? [String] ?? [message.id])
        let subject = isNewPost ? (draft.subject ?? "").trimmingCharacters(in: .whitespacesAndNewlines) : (thread.subject.lowercased().hasPrefix("re:") ? thread.subject : "Re: " + thread.subject)
        let fingerprint = postingFingerprint(text: draft.text, photos: draft.photos, name: server.name, email: server.email, subject: subject, refs: refs)
        if let old = draft.fingerprint, old != fingerprint { draft.changed() }
        draft.fingerprint = fingerprint
        let attempt = draft
        do {
            _ = try buildReply(draft: attempt, server: server, group: thread.groupName ?? "", subject: subject, refs: refs)
            draft.status = "uncertain"; saveDraft()
            try await store.submitReply(draft: attempt, server: server, group: thread.groupName ?? "", subject: subject, refs: refs)
            store.snapshot.replyDrafts?[draftKey] = nil; dismiss(); onSent()
        } catch {
            let description = error.localizedDescription
            if description.localizedCaseInsensitiveContains("duplicate") { draft.status = "duplicate" }
            else if description.hasPrefix("4") || description.hasPrefix("5") { draft.status = "rejected" }
            saveDraft(); errorText = description
        }
    }
}
struct ReplyPhotoThumbnail: View {
    let photo: ReplyPhoto
    @State private var image: UIImage?
    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFit() }
            else { ProgressView() }
        }.frame(width: 36, height: 36)
        .task(id: photo.id) {
            let bytes = photo.data
            let data = await Task.detached(priority: .utility) { PhotoPreparation.thumbnail(bytes) }.value
            guard !Task.isCancelled else { return }
            image = data.flatMap { UIImage(data: $0) }
        }
    }
}
struct CameraCapture: UIViewControllerRepresentable {
    @Environment(\.dismiss) var dismiss
    var onPhoto: (UIImage) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController(); picker.sourceType = .camera; picker.delegate = context.coordinator; return picker
    }
    func updateUIViewController(_ view: UIImagePickerController, context: Context) {}
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        var parent: CameraCapture
        init(_ parent: CameraCapture) { self.parent = parent }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            let image = info[.originalImage] as? UIImage
            parent.dismiss()
            if let image { parent.onPhoto(image) }
        }
    }
}

struct ReaderSearch: View {
    @Binding var text: String
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.gray)
            TextField("Search", text: $text).textInputAutocapitalization(.never).autocorrectionDisabled()
            if !text.isEmpty { Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.gray) }.accessibilityLabel("Clear search") }
        }.padding(.horizontal, 9).frame(height: 36).background(Color(white: 0.11), in: RoundedRectangle(cornerRadius: 10)).padding(.horizontal, 16).padding(.bottom, 14).padding(.top, 6)
    }
}
