import Foundation
func check(_ condition: @autoclosure () -> Bool, _ label: String) { guard condition() else { fatalError(label) }; print("PASS \(label)") }
func rejects(_ label: String, _ action: () throws -> Void) { do { try action(); fatalError(label) } catch { print("PASS \(label)") } }
let png = Data([137,80,78,71,13,10,26,10,1,2,3])
let photo = ReplyPhoto(data: png, mime: "image/png")
let server = NewsServer(title: "test", host: "fixture", name: "yrNewsEx 測試", email: "yrnewsex-test@example.invalid", groups: ["test.test"])
var draft = ReplyDraft(text: "Native reply photo test 😀\n\n> Parent: old history", photos: [photo])
let payload = try buildReply(draft: draft, server: server, group: "test.test", subject: "Re: 試野", refs: ["<root@fixture>"])
let decoded = try decodeArticle(payload)
check(decoded.body.contains("😀") && decoded.images == [png], "MIME emoji and image roundtrip")
let raw = latin(payload)
check(raw.range(of: "Content-Type: image/png")!.lowerBound < raw.range(of: Data("> Parent: old history".utf8).base64EncodedString())!.lowerBound, "photo before quoted history")
check(articleHeaders(payload)["references"] == "<root@fixture>", "References parent")
check(try! matchingArticle(payload, payload), "matching readable article accepted")
var changed = draft; changed.photos = [ReplyPhoto(data: Data([137,80,78,71,13,10,26,10,9]), mime: "image/png")]
let other = try buildReply(draft: changed, server: server, group: "test.test", subject: "Re: 試野", refs: ["<root@fixture>"])
check(!(try! matchingArticle(other, payload)), "different image duplicate rejected")
let id = draft.messageID; draft.changed(); check(draft.messageID != id, "edited draft gets new Message-ID")
let restored = try JSONDecoder().decode(ReplyDraft.self, from: JSONEncoder().encode(draft))
check(restored.messageID == draft.messageID && restored.photos == draft.photos, "draft identity and photo persist")
var tooMany = draft; tooMany.photos = [photo,photo,photo,photo]
rejects("four attachments rejected") { _ = try buildReply(draft: tooMany, server: server, group: "test.test", subject: "test", refs: []) }
var unsafeServer = server; unsafeServer.name = "Bad\r\nNewsgroups: other"
rejects("header injection rejected") { _ = try buildReply(draft: draft, server: unsafeServer, group: "test.test", subject: "test", refs: []) }
var oversized = draft; oversized.photos = [ReplyPhoto(data: Data(repeating: 0, count: 5*1024*1024+1), mime: "image/jpeg")]
rejects("oversized image rejected") { _ = try buildReply(draft: oversized, server: server, group: "test.test", subject: "test", refs: []) }
if CommandLine.arguments.count > 1 {
    let client = try NNTPClient(host: "127.0.0.1", port: Int(CommandLine.arguments[1])!); defer { client.close() }
    try client.post(payload)
    let readback = try client.rawArticle(group: "test.fixture", identifier: draft.messageID)
    check(try! matchingArticle(readback, payload), "POST transport and exact readback")
}
var topic = ReplyDraft(text: "A new topic", subject: "New topic", photos: [photo])
let topicPayload = try buildReply(draft: topic, server: server, group: "test.test", subject: topic.subject!, refs: [])
check(articleHeaders(topicPayload)["references"] == nil && articleHeaders(topicPayload)["in-reply-to"] == nil, "New topic has no reply ancestry")
let topicRestored = try JSONDecoder().decode(ReplyDraft.self, from: JSONEncoder().encode(topic))
check(topicRestored.subject == "New topic" && topicRestored.photos.count == 1, "New post subject and photo survive draft restoration")
var large = Data([0xff,0xd8,0xff]); large.append(Data(repeating: 73, count: 1024*1024))
let triple = ReplyDraft(text: "Three photos\n\n> History", photos: (0..<3).map { _ in ReplyPhoto(data: large, mime: "image/jpeg") })
let started = Date()
let triplePayload = try buildReply(draft: triple, server: server, group: "test.test", subject: "three photo fixture", refs: ["<root@fixture>"])
let elapsed = Date().timeIntervalSince(started)
check(elapsed < 10, "Three 1 MB attachments encode without quadratic String indexing")
print(String(format: "Three-photo MIME build: %.3f seconds", elapsed))
let tripleDecoded = try decodeArticle(triplePayload)
check(tripleDecoded.images == [large, large, large] && tripleDecoded.body.contains("> History"), "Three-photo MIME preserves bytes and quoted history")
let mimeLines = latin(triplePayload).components(separatedBy: "\r\n")
check(mimeLines.filter { !$0.contains(":") && !$0.hasPrefix("--") }.allSatisfy { $0.count <= 76 }, "Large Base64 lines remain RFC compliant")
if CommandLine.arguments.count > 1 {
    let client = try NNTPClient(host: "127.0.0.1", port: Int(CommandLine.arguments[1])!); defer { client.close() }
    try client.post(triplePayload)
    let readback = try client.rawArticle(group: "test.fixture", identifier: triple.messageID)
    check(try! matchingArticle(readback, triplePayload), "Three large photo POST and readback match on local server")
}
