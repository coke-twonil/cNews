import Foundation
func check(_ value: @autoclosure () -> Bool, _ label: String) { guard value() else { fatalError(label) }; print("PASS \(label)") }
let directory = FileManager.default.temporaryDirectory.appendingPathComponent("yrnewsex-writer-" + UUID().uuidString)
defer { try? FileManager.default.removeItem(at: directory) }
let file = directory.appendingPathComponent("snapshot.json")
let writer = SnapshotFileWriter(file: file)
var snapshot = demoSnapshot()
var draft = ReplyDraft(text: "Reply", photos: [ReplyPhoto(data: Data(repeating: 42, count: 2*1024*1024), mime: "image/jpeg")])
for index in 0..<50 {
    draft.text = "Draft \(index)"
    snapshot.replyDrafts = ["demo|general.chat|reply": draft]
    writer.schedule(snapshot) { error in fatalError(error) }
}
writer.flush()
let restored = try JSONDecoder().decode(ReaderSnapshot.self, from: Data(contentsOf: file))
check(restored.replyDrafts?["demo|general.chat|reply"]?.text == "Draft 49", "Coalesced background writes persist latest draft in order")
check(restored.replyDrafts?["demo|general.chat|reply"]?.photos.first?.data == draft.photos.first?.data, "Photo bytes survive asynchronous persistence")
check(restored.threads.count == snapshot.threads.count, "Article cache retained alongside photo draft")
let rejected = DispatchSemaphore(value: 0)
let badWriter = SnapshotFileWriter(file: file.appendingPathComponent("cannot-write.json"))
badWriter.schedule(snapshot) { _ in rejected.signal() }
badWriter.flush()
check(rejected.wait(timeout: .now()+1) == .success, "Persistence error is reported rather than losing draft silently")
