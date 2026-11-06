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
