import Foundation
func check(_ condition: @autoclosure () -> Bool, _ label: String) {
    guard condition() else { fatalError(label) }
    print("PASS \(label)")
}
let thread = demoSnapshot().threads[2]
check(thread.tree.map { $0.message.id } == ["t2m0", "t2m1", "t2m2", "t2m3", "t2m4", "t2m5", "t2m6", "t2m7", "t2m8"], "depth first reading order")
check(thread.tree.map { $0.depth } == [0,1,2,3,2,1,2,3,2], "branched hierarchy")
var uniqueThread = thread
for i in uniqueThread.messages.indices { uniqueThread.messages[i].author = uniqueThread.messages[i].id }
let quote = uniqueThread.history(replyingTo: "t2m7")
check(quote.contains(">>>> t2m0:"), "four ancestor quote")
check(!quote.contains("t2m2:") && !quote.contains("t2m8:"), "sibling excluded from quote")
let cycle = NewsThread(id: "cycle", subject: "cycle", messages: [NewsMessage(id:"a",parentID:"b",author:"A",body:"A"),NewsMessage(id:"b",parentID:"a",author:"B",body:"B")])
check(cycle.tree.count == 2, "cycles terminate and retain messages")
check(downloadSelection(available: [90,101,102,105,106], newestDownloaded: 100, count: 2, latest: false) == [101,102], "Next starts after newest downloaded")
check(downloadSelection(available: [90,101,102,105,106], newestDownloaded: 100, count: 2, latest: true) == [105,106], "Latest selects newest batch")
let restored = try JSONDecoder().decode(ReaderSnapshot.self, from: JSONEncoder().encode(demoSnapshot()))
check(restored.threads[2].tree.count == 9, "persistent hierarchy roundtrip")
var blockedThread = thread
blockedThread.messages[1].senderIP = "192.0.2.24"
let blocked = BlockedUser(username: "Alex", email: "alex@example.invalid", ip: "192.0.2.24")
let filtered = blockedThread.visible(blocked: [blocked])!
check(filtered.messages.map(\.id) == ["t2m0", "t2m5", "t2m6", "t2m7", "t2m8"], "IP block hides complete descendant branch, preserves siblings")
check(blockedThread.visible(blocked: [])!.messages.count == 9, "Unblock restores untouched cache")
blockedThread.messages[0].senderIP = "192.0.2.24"
check(blockedThread.visible(blocked: [blocked]) == nil, "Blocked root hides entire thread")
var sameIP = NewsThread(id: "same", subject: "Other", messages: [NewsMessage(id: "other", author: "Other <other@example.invalid>", body: "", senderIP: "192.0.2.24")])
check(sameIP.visible(blocked: [blocked]) == nil, "Different email with same IP is blocked")
sameIP.messages[0].senderIP = "198.51.100.1"
check(sameIP.visible(blocked: [blocked]) != nil, "Different IP remains visible")
check(canonicalIP("2001:0db8:0:0::1") == "2001:db8::1", "Equivalent IPv6 addresses normalize")
check(canonicalIP("news.example.invalid") == nil, "Hostname is never treated as sender IP")
check(senderIdentity("Alex <alex@example.invalid>").email == "alex@example.invalid", "Block confirmation preserves sender identity")
check(adjacentThreadIndex(threadIDs: ["a","a","b","b","c"], index: 3, delta: -1) == 0, "Up jumps to first message of previous thread")
check(adjacentThreadIndex(threadIDs: ["a","a","b","b","c"], index: 2, delta: 1) == 4, "Down jumps to first message of next thread")
check(adjacentThreadIndex(threadIDs: ["a","a"], index: 1, delta: 1) == nil, "Thread navigation respects last boundary")
check(thread.matches("coffee", scope: "Sender") && !thread.matches("coffee", scope: "Subject"), "Sender search is independent from Subject")
check(thread.matches("多謝", scope: "Message") && !thread.matches("多謝", scope: "Sender"), "Message search uses body only")
var saved = demoSnapshot()
saved.servers[0].blockedUsers = [blocked]
saved.threads[0].messages[0].favourite = true
saved.refreshCounts = ["demo|general.chat": 17]
let before = try JSONEncoder().encode(saved)
let roundtrip = try JSONDecoder().decode(ReaderSnapshot.self, from: before)
check(roundtrip.servers[0].blockedUsers == [blocked] && roundtrip.threads[0].messages[0].favourite == true, "Block identity and favourites survive relaunch")
saved.threads[0].messages[0].read = true
check(saved.refreshCounts?["demo|general.chat"] == 17, "Reading does not change last Refresh count")
let legacy = Data(#"{"servers":[],"threads":[],"pending":[]}"#.utf8)
let migrated = try JSONDecoder().decode(ReaderSnapshot.self, from: legacy)
check(migrated.refreshCounts == nil, "Old cache migrates without deleting data")

var searchOnly = NewsThread(id: "search", subject: "Title", messages: [NewsMessage(id: "search1", author: "A", body: "", bodyLoaded: false, searchBody: "Cached search text")])
check(searchOnly.matches("cached", scope: "Message") && searchOnly.messages[0].bodyLoaded == false, "Text search cache does not pretend images are fully loaded")
var deletion = demoSnapshot()
let live = NewsServer(id: "live-public", title: "Live", host: "example.invalid", name: "A", email: "a@example.invalid", groups: ["test.test"], blockedUsers: [blocked])
let otherServer = NewsServer(id: "live-public-other", title: "Keep", host: "example.invalid", name: "B", email: "b@example.invalid", groups: ["test.test"])
deletion.servers += [live, otherServer]
let deletedMessage = NewsMessage(id: "delete", author: "A", body: "", favourite: true)
deletion.threads += [NewsThread(id: "delete-thread", subject: "Delete", messages: [deletedMessage], serverID: live.id, groupName: "test.test"), NewsThread(id: "keep-thread", subject: "Keep", messages: [deletedMessage], serverID: otherServer.id, groupName: "test.test")]
let deleteKey = groupKey(live.id, "test.test"), keepKey = groupKey(otherServer.id, "test.test")
deletion.liveGroups = [deleteKey: LiveGroupCache(messages: [deletedMessage]), keepKey: LiveGroupCache(messages: [deletedMessage])]
deletion.replyDrafts = [deleteKey + "|delete": ReplyDraft(text: "delete"), keepKey + "|keep": ReplyDraft(text: "keep")]
deletion.refreshCounts = [deleteKey: 5, keepKey: 7]
deletion.pending = [PendingReply(threadID: "delete-thread", message: deletedMessage), PendingReply(threadID: "keep-thread", message: deletedMessage)]
deletion.deleteServer(live.id)
check(!deletion.servers.contains { $0.id == live.id } && !deletion.threads.contains { $0.id == "delete-thread" }, "Delete removes only selected server and its articles")
check(deletion.liveGroups?[deleteKey] == nil && deletion.replyDrafts?[deleteKey + "|delete"] == nil && deletion.refreshCounts?[deleteKey] == nil, "Delete clears selected server caches, drafts and refresh count")
check(deletion.liveGroups?[keepKey]?.messages.count == 1 && deletion.replyDrafts?[keepKey + "|keep"]?.text == "keep" && deletion.refreshCounts?[keepKey] == 7, "Similar server ID retains its data")
check(deletion.pending.map(\.threadID) == ["keep-thread"], "Delete removes pending replies belonging to removed threads")
let deletedRestored = try JSONDecoder().decode(ReaderSnapshot.self, from: JSONEncoder().encode(deletion))
check(deletedRestored.deletedServerIDs?.contains("live-public") == true, "Removal marker survives relaunch to prevent default server resurrection")
deletion.deleteServer("demo")
check(!deletion.threads.contains { $0.serverID == nil } && deletion.servers.contains { $0.id == otherServer.id }, "Demo deletion removes demo threads and preserves Live servers")
