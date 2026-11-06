import SwiftUI
import PhotosUI

@MainActor
final class ReaderStore: ObservableObject {
    @Published var snapshot: ReaderSnapshot { didSet { save() } }
    @Published var storageError: String?
    @Published var busy = false
    @Published var progress = ""
    @Published var loadingArticles = Set<String>()
    private let file: URL
    init() {
        file = URL.applicationSupportDirectory.appending(path: "yrNewsEx/native-demo.json")
        if FileManager.default.fileExists(atPath: file.path) {
            do { snapshot = try JSONDecoder().decode(ReaderSnapshot.self, from: Data(contentsOf: file)) }
            catch { snapshot = demoSnapshot(); storageError = "未能讀取本機資料：\(error.localizedDescription)" }
        } else { snapshot = demoSnapshot() }
        if !snapshot.servers.contains(where: { $0.id == "live-public" }) {
            snapshot.servers.append(NewsServer(id: "live-public", title: "news.twonil.hk · Live", host: "news.twonil.hk", name: "", email: "", groups: ["general.chat", "test.test"]))
        }
        if !snapshot.threads.contains(where: { $0.id == "native-scroll-demo" }) { snapshot.threads.append(scrollDemoThread()) }
    }
    func save() {
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(snapshot).write(to: file, options: .atomic)
        } catch { storageError = "未能儲存：\(error.localizedDescription)" }
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
    func refresh() {
        for reply in snapshot.pending {
            if let t = snapshot.threads.firstIndex(where: { $0.id == reply.threadID }), !snapshot.threads[t].messages.contains(where: { $0.id == reply.message.id }) {
                snapshot.threads[t].messages.append(reply.message)
            }
        }
        snapshot.pending.removeAll()
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
        do {
            for offset in stride(from: 0, to: numbers.count, by: 500) {
                try Task.checkCancellation()
                let batch = Array(numbers[offset..<min(offset+500, numbers.count)])
                progress = "Downloading \(offset)/\(numbers.count)"
                let headers = try await Task.detached {
                    let client = try NNTPClient(host: server.host, port: server.port); defer { client.close() }
                    return try client.headers(group: group, numbers: batch)
                }.value
                let key = groupKey(server.id, group)
                var cache = snapshot.liveGroups?[key] ?? LiveGroupCache()
                var known = Set(cache.messages.map(\.id))
                for message in headers where known.insert(message.id).inserted { cache.messages.append(message) }
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
                rebuild(server: server, group: group)
            }
        } catch { storageError = error.localizedDescription }
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
                Section {
                    NavigationLink("Subscribe Group") { SubscriptionScreen(selection: $server.groups, server: server) }
                } footer: { Text("Live 會直接連線載入群組及文章；119 普通 NNTP，563 TLS。暫未支援帳密登入；test.test 已開放相片回覆，其他群組只讀。Name／Email 會隨發文公開顯示。") }
            }
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                ReaderHeader(title: isNew ? "Add Server" : "Server") {
                    Button("Cancel") { dismiss() }.frame(minHeight: 44)
                } right: {
                    Button("Done") {
                        if let i = store.snapshot.servers.firstIndex(where: { $0.id == server.id }) { store.snapshot.servers[i] = server }
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
    @State private var unreadOnly = false
    @State private var reading: ReadingSession?
    @State private var edgeBackActive = false
    @Environment(\.dismiss) private var dismiss
    @State private var availableNumbers: [Int] = []
    @State private var downloadDialog = false
    @State private var checking = false
    @State private var quantity = 500
    @State private var customQuantity = "500"
    var threads: [NewsThread] {
        return store.snapshot.threads.filter { t in
            let belongs = server.id == "demo" ? (group == "general.chat" && t.serverID == nil) : (t.serverID == server.id && t.groupName == group)
            return belongs && (!unreadOnly || t.unread > 0) && (query.isEmpty || t.subject.localizedCaseInsensitiveContains(query)) }
    }
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                Text(group).font(.system(size: 34, weight: .bold)).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.bottom, 8)
                ReaderSearch(text: $query)
                if checking { ProgressView("Checking new messages…").padding() }
                if store.busy { ProgressView(store.progress).padding() }
                if threads.isEmpty { Text("未有本機文章").foregroundStyle(.secondary).padding(30) }
                ForEach(threads) { thread in
                    VStack(spacing: 0) {
                        ForEach(expanded.contains(thread.id) ? thread.tree : Array(thread.tree.prefix(1)), id: \.message.id) { entry in
                            HStack(spacing: 8) {
                                if entry.depth > 0 { Text("└").foregroundStyle(.gray) }
                                Circle().fill(entry.message.read ? Color.clear : Color.blue).frame(width: 6, height: 6)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(entry.depth == 0 ? thread.subject : "Re: \(thread.subject)").font(.system(size: 17)).foregroundStyle(entry.message.read ? .gray : .white).lineLimit(1)
                                    Text(entry.message.author).font(.system(size: 13)).foregroundStyle(.gray)
                                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                                    .onTapGesture {
                                        let route = threads.flatMap { t in t.tree.map { ReadingItem(threadID: t.id, messageID: $0.message.id) } }
                                        reading = ReadingSession(route: route, initial: ReadingItem(threadID: thread.id, messageID: entry.message.id))
                                    }.accessibilityAddTraits(.isButton)
                                if entry.depth == 0 {
                                    Button { toggle(thread.id) } label: { Text("\(thread.unread)/\(thread.messages.count)").font(.system(size: 15)).frame(minWidth: 44, minHeight: 44) }.accessibilityLabel("Expand thread")
                                }
                            }.padding(.leading, 12 + CGFloat(min(entry.depth, 12)) * 18).padding(.trailing, 12).frame(minHeight: 64).contentShape(Rectangle())
                            Divider().overlay(Color(white: 0.08))
                        }
                    }
                    .background(HorizontalSwipe { direction in
                        if direction < 0 { expanded.insert(thread.id) } else { expanded.remove(thread.id) }
                    })
                }
            }.background(EdgeBack(active: edgeBackActive && !downloadDialog && reading == nil) { dismiss() })
        }
            .onAppear { edgeBackActive = true }.onDisappear { edgeBackActive = false }
            .scrollIndicators(.hidden).background(.black).toolbar(.hidden, for: .navigationBar).navigationBarBackButtonHidden(true)
            .safeAreaInset(edge: .top, spacing: 0) {
                ReaderHeader { ReaderBack(title: "Groups") { dismiss() } } right: {
                    Button { if server.id == "demo" { store.refresh() } else { Task { await checkMessages() } } } label: { Image(systemName: "arrow.clockwise").font(.system(size: 21)).frame(width: 44, height: 44) }.accessibilityLabel("Refresh").disabled(checking || store.busy)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                ReaderBottom {
                    Button(unreadOnly ? "All" : "Unread") { unreadOnly.toggle() }.frame(minHeight: 44)
                    Spacer()
                    Text("\(threads.reduce(0) { $0 + $1.unread }) Unread Messages").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                    Spacer()
                    Text("\(threads.count)").font(.footnote).foregroundStyle(.gray).frame(width: 44)
                }
            }
            .task { if server.id != "demo" { store.rebuild(server: server, group: group) } }
            .sheet(isPresented: $downloadDialog) {
                VStack(spacing: 20) {
                    Text("\(availableNumbers.count) new messages").font(.headline)
                    Text("Next 由本機最新已下載文章之後開始；Latest 取最新一批。")
                        .font(.footnote).foregroundStyle(.secondary)
                    Picker("Download", selection: $quantity) { Text("500").tag(500); Text("1,000").tag(1000); Text("2,000").tag(2000); Text("More…").tag(-1); Text("All").tag(0) }.pickerStyle(.menu)
                    if quantity == -1 { TextField("Quantity", text: $customQuantity).keyboardType(.numberPad).textFieldStyle(.roundedBorder) }
                    Button("Next \(chosenCount)") { startDownload(latest: false) }.disabled(chosenCount < 1)
                    Button("Latest \(chosenCount)") { startDownload(latest: true) }.disabled(chosenCount < 1)
                    Button("Cancel") { downloadDialog = false }
                }.padding(24).presentationDetents([.medium, .large])
            }
            .navigationDestination(item: $reading) { item in ArticleScreen(route: item.route, initial: item.initial, onReplySent: { reading = nil }) }
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
            else if !availableNumbers.isEmpty { await store.download(server: server, group: group, numbers: availableNumbers) }
        } catch is CancellationError { return }
        catch { store.storageError = error.localizedDescription }
    }
    func startDownload(latest: Bool) {
        let count = chosenCount
        guard count > 0 else { return }
        let numbers = latest ? Array(availableNumbers.suffix(count)) : Array(availableNumbers.prefix(count))
        downloadDialog = false
        Task { await store.download(server: server, group: group, numbers: numbers) }
    }
    func toggle(_ id: String) { if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) } }
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
                    Text(message.author).foregroundStyle(.secondary)
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
                    .background(EdgeBack(active: edgeBackActive && !composing) { dismiss() })
            }
            Color.clear.frame(height: 1)
                .frame(maxWidth: .infinity)
        }.id(item.messageID).background(.black).contentShape(Rectangle())
            .onAppear { edgeBackActive = true }.onDisappear { edgeBackActive = false }
            .scrollIndicators(.hidden).toolbar(.hidden, for: .navigationBar).navigationBarBackButtonHidden(true)
            .safeAreaInset(edge: .top, spacing: 0) {
                ReaderHeader { ReaderBack(title: "Back") { dismiss() } } right: { Color.clear.frame(width: 44, height: 44) }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                ReaderBottom {
                    Button { move(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }.disabled(index == 0).accessibilityLabel("Previous message")
                    Spacer()
                    Button(thread?.serverID == nil || thread?.groupName == "test.test" ? "Reply" : "Read only") { composing = true }.frame(minWidth: 80, minHeight: 44).disabled(thread?.serverID != nil && thread?.groupName != "test.test")
                    Spacer()
                    Button { move(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }.disabled(index + 1 >= route.count).accessibilityLabel("Next message")
                }
            }
            .task(id: item.messageID) { store.markRead(item.messageID, threadID: item.threadID); await store.loadArticle(item.messageID, threadID: item.threadID) }
            .sheet(isPresented: $composing) { if let thread, let message { ReplyScreen(thread: thread, message: message, onSent: onReplySent) } }
    }
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
    var onSent: () -> Void
    @State private var draft = ReplyDraft()
    @State private var showingSent = false
    @State private var loadingHistory = true
    @State private var historyReady = false
    @State private var sending = false
    @State private var errorText: String?
    @State private var picker = false
    @State private var selection: [PhotosPickerItem] = []
    @State private var importing = false
    @State private var camera = false
    @State private var settings = false
    var server: NewsServer? { store.snapshot.servers.first { $0.id == (thread.serverID ?? "demo") } }
    var draftKey: String { (thread.serverID ?? "demo") + "|" + (thread.groupName ?? "general.chat") + "|" + message.id }
    var isLive: Bool { thread.serverID != nil }
    var identityReady: Bool { guard let server else { return false }; return !server.name.isEmpty && server.email.contains("@") }
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                Text("Re: \(thread.subject)").padding(12)
                Divider()
                if loadingHistory { ProgressView("Loading reply history…").padding() }
                TextEditor(text: Binding(get: { draft.text }, set: { draft.text = $0; edited() }))
                    .scrollContentBackground(.hidden).scrollIndicators(.hidden).padding(8).disabled(loadingHistory || !historyReady || sending)
                if !draft.photos.isEmpty {
                    ScrollView(.horizontal) {
                        HStack {
                            ForEach(draft.photos) { photo in
                                ZStack(alignment: .topTrailing) {
                                    if let image = UIImage(data: photo.data) { Image(uiImage: image).resizable().scaledToFit().frame(width: 80, height: 70) }
                                    Button { draft.photos.removeAll { $0.id == photo.id }; edited() } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.white, .black) }.accessibilityLabel("Remove photo")
                                }
                            }
                        }
                    }.frame(height: 80).padding(.horizontal, 12).disabled(sending)
                }
                HStack {
                    Menu {
                        Button("Choose Existing") { picker = true }
                        Button("Take a New Photo") {
                            if UIImagePickerController.isSourceTypeAvailable(.camera) { camera = true }
                            else { errorText = "模擬器冇相機；真 iPhone 可以影相。" }
                        }
                    } label: { Label("Attach Photo", systemImage: "camera") }
                    .disabled(draft.photos.count >= 3 || sending || importing || loadingHistory || !historyReady)
                    Spacer(); Text("\(draft.photos.count)/3").foregroundStyle(.secondary)
                }.padding(12)
                if importing { ProgressView("Preparing photo…").padding(.horizontal, 12) }
                if isLive && !identityReady {
                    Button("先喺 Server 設定 Name／Email") { settings = true }.padding(12)
                }
                if let errorText { Text(errorText).font(.footnote).foregroundStyle(.orange).padding(12) }
                if !loadingHistory && !historyReady { Button("Retry history") { Task { await loadHistory() } }.padding(12) }
                if draft.status == "uncertain" || draft.status == "duplicate" {
                    Button("用新識別碼再試") { draft.changed(); saveDraft(); errorText = nil }.padding(12).disabled(sending)
                }
                Text(isLive ? "Send 會公開回覆到 \(thread.groupName ?? "")；相片放喺 history 前。" : "Demo：只儲存本機回覆，Refresh 先顯示。")
                    .font(.footnote).foregroundStyle(.secondary).padding(12)
            }.background(.black).toolbar(.hidden, for: .navigationBar)
                .safeAreaInset(edge: .top, spacing: 0) {
                    ReaderHeader(title: "Reply") {
                        Button("Cancel") { dismiss() }.frame(minHeight: 44).disabled(sending)
                    } right: {
                        Button(sending ? "Sending…" : "Send") { Task { await send() } }.frame(minHeight: 44)
                            .disabled(sending || loadingHistory || !historyReady || importing || !identityReady || (replyTextSections(draft.text).own.isEmpty && draft.photos.isEmpty))
                    }
                }
                .task { await loadHistory() }
                .photosPicker(isPresented: $picker, selection: $selection, maxSelectionCount: max(1, 3-draft.photos.count), matching: .images)
                .onChange(of: selection) { _, items in
                    Task {
                        importing = true; defer { importing = false; selection = [] }
                        for item in items.prefix(max(0, 3-draft.photos.count)) {
                            do {
                                guard let data = try await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else { throw NewsError.failure("相片無法讀取") }
                                try addPhoto(image)
                            } catch { errorText = error.localizedDescription }
                        }
                    }
                }
                .sheet(isPresented: $camera) { CameraCapture { image in do { try addPhoto(image) } catch { errorText = error.localizedDescription } } }
                .sheet(isPresented: $settings) { if let server { ServerEditor(server: server, isNew: false) } }
                .interactiveDismissDisabled(sending)
                .alert(isLive ? "Sent" : "Saved locally", isPresented: $showingSent) {
                    Button("OK") { dismiss(); onSent() }
                } message: { Text("回覆已保存。返回列表撳 Refresh 先會以未讀顯示。") }
        }
    }
    func loadHistory() async {
        loadingHistory = true; defer { loadingHistory = false }
        if let saved = store.snapshot.replyDrafts?[draftKey] { draft = saved; historyReady = true; return }
        do { draft.text = "\n\n" + (try await store.replyHistory(thread: thread, message: message)); historyReady = true; saveDraft(); errorText = nil }
        catch { errorText = "未能載入父訊息 history：" + error.localizedDescription }
    }
    func saveDraft() { store.saveReplyDraft(draft, key: draftKey) }
    func edited() { draft.changed(); saveDraft(); errorText = nil }
    func addPhoto(_ image: UIImage) throws {
        guard draft.photos.count < 3 else { throw NewsError.failure("最多三張相") }
        guard let data = image.jpegData(compressionQuality: 0.85), data.count <= 5*1024*1024 else { throw NewsError.failure("每張相最多 5 MB") }
        draft.photos.append(ReplyPhoto(data: data, mime: "image/jpeg")); edited()
    }
    func send() async {
        guard let server, !sending else { return }
        sending = true; errorText = nil; defer { sending = false }
        if !isLive {
            var reply = NewsMessage(id: draft.messageID, parentID: message.id, author: server.name, body: draft.text)
            reply.images = draft.photos.map(\.data)
            store.snapshot.pending.append(PendingReply(threadID: thread.id, message: reply))
            store.snapshot.replyDrafts?[draftKey] = nil; showingSent = true; return
        }
        let refs = Array(NSOrderedSet(array: (message.references ?? []) + [message.id])) as? [String] ?? [message.id]
        let subject = thread.subject.lowercased().hasPrefix("re:") ? thread.subject : "Re: " + thread.subject
        let fingerprint = postingFingerprint(text: draft.text, photos: draft.photos, name: server.name, email: server.email, subject: subject, refs: refs)
        if let old = draft.fingerprint, old != fingerprint { draft.changed() }
        draft.fingerprint = fingerprint
        let attempt = draft
        do {
            _ = try buildReply(draft: attempt, server: server, group: thread.groupName ?? "", subject: subject, refs: refs)
            draft.status = "uncertain"; saveDraft()
            try await store.submitReply(draft: attempt, server: server, group: thread.groupName ?? "", subject: subject, refs: refs)
            store.snapshot.replyDrafts?[draftKey] = nil; showingSent = true
        } catch {
            let description = error.localizedDescription
            if description.localizedCaseInsensitiveContains("duplicate") { draft.status = "duplicate" }
            else if description.hasPrefix("4") || description.hasPrefix("5") { draft.status = "rejected" }
            saveDraft(); errorText = description
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
            if let image = info[.originalImage] as? UIImage { parent.onPhoto(image) }; parent.dismiss()
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
